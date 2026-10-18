/* Single-threaded allocation probe. All fixtures, callback storage, and reporting
 * belong to the caller. Nothing in this file is shipped in library products. */
#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

extern int32_t verified_source_metrics_probe(int32_t, intptr_t, void *, uint64_t *);
extern void ds_probe_arm(void), ds_probe_disarm(void);
extern uint64_t ds_probe_allocations(void), ds_probe_mappings(void);

enum { BLOCK_BYTES = 65536, TOKEN_LIMIT = 16, CALLS = 33 };
struct token { intptr_t payload, control; int32_t resource; int live; };
struct state {
    struct token tokens[TOKEN_LIMIT];
    intptr_t page, source_bytes, charged, peak, header_payload;
    uint64_t admitted, retired, expected_maps;
    unsigned checkpoints;
    int retained, released, failed;
};

static int32_t fail(struct state *s) { s->failed = 1; return 97; }

int32_t vsm_retain(void *raw) {
    struct state *s = raw;
    if (!s || s->retained || s->released) return 97;
    s->retained = 1;
    return 0;
}

int32_t vsm_admit(void *raw, int32_t resource, intptr_t payload,
                  intptr_t control, uint64_t *out) {
    struct state *s = raw;
    if (out) *out = 0;
    if (!s || !out) return 97;
    if (!s->retained || s->released || s->admitted >= TOKEN_LIMIT ||
        (resource != 0 && resource != 5) || control != s->page || payload < 0 ||
        payload % s->page != 0 || payload > BLOCK_BYTES + s->page) return fail(s);
    if ((s->admitted == 0 && (resource != 5 || payload != 0)) ||
        (s->admitted > 0 && payload == 0)) return fail(s);
    const uint64_t blocks = ((uint64_t)s->source_bytes + BLOCK_BYTES - 1) / BLOCK_BYTES;
    if (s->admitted == 1 || s->admitted == 2) {
        /* Empty path storage and the fixed header plus at most two digests each
           fit one page in this qualified source layout. Reject overcharging. */
        if (resource != 5 || payload != s->page) return fail(s);
    } else if (s->admitted >= 3) {
        intptr_t expected_payload = s->page; /* The output is at most five bytes. */
        if (s->admitted != 3 + blocks) {
            uint64_t block = s->admitted < 3 + blocks ? s->admitted - 3 : s->admitted - 4 - blocks;
            if (block >= blocks) return fail(s);
            intptr_t bytes = s->source_bytes - (intptr_t)block * BLOCK_BYTES;
            if (bytes > BLOCK_BYTES) bytes = BLOCK_BYTES;
            expected_payload = ((bytes + s->page - 1) / s->page) * s->page;
        }
        if (resource != 0 || payload != expected_payload) return fail(s);
    }
    /* Every reservation here owns a control mapping; all but ledger bootstrap
       also own a payload mapping. No external stack/lease reservation is used. */
    if (ds_probe_mappings() != s->expected_maps) return fail(s);
    struct token *t = &s->tokens[s->admitted];
    *t = (struct token){payload, control, resource, 1};
    s->expected_maps += payload > 0 ? 2 : 1;
    s->charged += payload + control;
    if (s->charged > s->peak) s->peak = s->charged;
    ++s->admitted;
    *out = s->admitted;
    return 0;
}

void vsm_release(void *raw, uint64_t token) {
    struct state *s = raw;
    if (!s) return;
    if (s->released || token == 0 || token > s->admitted ||
        !s->tokens[token - 1].live) { (void)fail(s); return; }
    struct token *t = &s->tokens[token - 1];
    t->live = 0;
    s->charged -= t->payload + t->control;
    ++s->retired;
}

int32_t vsm_transfer(void *raw, uint64_t token, int32_t resource) {
    (void)token; (void)resource;
    return raw ? fail(raw) : 97; /* This probe never requests a transfer. */
}

void vsm_release_context(void *raw) {
    struct state *s = raw;
    if (!s) return;
    if (!s->retained || s->released || s->charged != 0 || s->retired != s->admitted)
        (void)fail(s);
    s->released = 1;
}

int32_t vsm_checkpoint(void *raw, int32_t stage, intptr_t metadata,
                       intptr_t encoded, intptr_t total, intptr_t owners) {
    struct state *s = raw;
    if (!s) return 97;
    if (stage < 0 || stage > 6 || s->released || s->failed ||
        s->checkpoints != ((1u << stage) - 1)) return fail(s);
    intptr_t actual_metadata = 0, actual_encoded = 0, actual_owners = 0;
    for (uint64_t i = 0; i < s->admitted; ++i) {
        const struct token *t = &s->tokens[i];
        if (!t->live) continue;
        ++actual_owners;
        actual_metadata += t->control + (t->resource == 5 ? t->payload : 0);
        actual_encoded += t->resource == 0 ? t->payload : 0;
    }
    if (metadata != actual_metadata || encoded != actual_encoded ||
        total != s->charged || total != metadata + encoded || owners != actual_owners ||
        ds_probe_mappings() != s->expected_maps) return fail(s);
    if (stage == 0 || stage == 6) {
        if (owners != 1 || metadata != s->page || encoded != 0 || !s->tokens[0].live)
            return fail(s);
    } else {
        /* Capture's third reservation owns the admitted source header and digest
           table; the preceding empty path owner is temporary even for descriptors. */
        if (s->admitted < 3 || !s->tokens[0].live || s->tokens[1].live ||
            !s->tokens[2].live || s->tokens[2].resource != 5) return fail(s);
        s->header_payload = s->tokens[2].payload;
        if (metadata != 2 * s->page + s->header_payload + (stage == 3 ? s->page : 0) ||
            owners != (stage == 3 ? 3 : 2) || encoded != (stage == 3 ? s->page : 0))
            return fail(s);
    }
    s->checkpoints |= 1u << stage;
    return 0;
}

static int verify_metrics(const uint64_t *v, intptr_t size) {
    uint64_t blocks = ((uint64_t)size + BLOCK_BYTES - 1) / BLOCK_BYTES;
    uint64_t copies = size == 0 ? 0 : size > BLOCK_BYTES ? 2 : 1;
    uint64_t copied = size < 5 ? (uint64_t)size : 5;
    if (v[9] != 1 || v[19] != 1 || v[3] != blocks + 1 || v[4] != 2 * blocks ||
        v[5] != blocks + 1 || v[6] != blocks || v[7] != (uint64_t)size || v[8] != 32 * blocks)
        return 0;
    if (v[13] != v[3] + copies || v[14] != v[4] + copies ||
        v[15] != v[5] + copies || v[16] != v[6] + copies ||
        v[17] != 2 * (uint64_t)size || v[18] != v[8] + copied) return 0;
    /* Zero elapsed time is valid. Compare monotonic totals, not a time budget. */
    return v[10] >= v[0] && v[11] >= v[1] && v[12] >= v[2];
}

static int control(void) {
    intptr_t page = getpagesize();
    ds_probe_arm();
    void *p = malloc(64);
    void *m = mmap(NULL, (size_t)page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (p) *(volatile unsigned char *)p = 7;
    ds_probe_disarm();
    uint64_t allocations = ds_probe_allocations(), mappings = ds_probe_mappings();
    int ok = p && m != MAP_FAILED && allocations > 0 && mappings == 1;
    free(p);
    if (m != MAP_FAILED && munmap(m, (size_t)page) != 0) ok = 0;
    printf("{\"control\":true,\"allocations\":%" PRIu64 ",\"mappings\":%" PRIu64
           ",\"passed\":%s}\n", allocations, mappings, ok ? "true" : "false");
    return ok ? 0 : 1;
}

static int fixture(intptr_t size) {
    char path[] = "/tmp/dicomkit-metrics-probe-XXXXXX";
    int fd = mkstemp(path);
    if (fd < 0) return -1;
    if (unlink(path) != 0) { close(fd); return -1; }
    unsigned char bytes[BLOCK_BYTES];
    memset(bytes, 0x5a, sizeof bytes);
    intptr_t done = 0;
    while (done < size) {
        size_t count = (size_t)(size - done);
        if (count > sizeof bytes) count = sizeof bytes;
        ssize_t amount = write(fd, bytes, count);
        if (amount < 0 && errno == EINTR) continue;
        if (amount <= 0) { close(fd); return -1; }
        done += amount;
    }
    return fd;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--control") == 0) return control();
    intptr_t size;
    if (argc != 2) return 2;
    if (strcmp(argv[1], "empty") == 0) size = 0;
    else if (strcmp(argv[1], "single") == 0) size = 19;
    else if (strcmp(argv[1], "cross-block") == 0) size = BLOCK_BYTES + 13;
    else return 2;
    const intptr_t page = getpagesize();
    const int fd = fixture(size);
    if (fd < 0) return 2;
    uint64_t cold_allocations = 0, hot_allocations = 0, maps = 0, values[20] = {0};
    intptr_t header = 0, peak = 0;
    int32_t status = 0;
    int completed = 0, ok = 1;
    const uint64_t blocks = ((uint64_t)size + BLOCK_BYTES - 1) / BLOCK_BYTES;
    const uint64_t per_call_maps = 7 + 4 * blocks;
    for (int call = 0; call < CALLS; ++call) {
        struct state state = {0};
        state.page = page;
        state.source_bytes = size;
        memset(values, 0, sizeof values);
        ds_probe_arm();
        status = verified_source_metrics_probe(fd, size, &state, values);
        ds_probe_disarm();
        const uint64_t allocations = ds_probe_allocations(), mappings = ds_probe_mappings();
        if (call == 0) cold_allocations = allocations; else hot_allocations += allocations;
        maps += mappings;
        ++completed;
        if (status != 0 || allocations != 0 || state.failed || !state.retained || !state.released ||
            state.checkpoints != 127 || state.charged != 0 || state.admitted != state.retired ||
            state.expected_maps != mappings || mappings != per_call_maps ||
            state.admitted != 4 + 2 * blocks || !verify_metrics(values, size)) {
            ok = 0;
            break;
        }
        if (call > 0 && header != state.header_payload) { ok = 0; break; }
        header = state.header_payload;
        if (state.peak > peak) peak = state.peak;
    }
    if (close(fd) != 0) ok = 0;
    printf("{\"scenario\":\"%s\",\"sourceBytes\":%" PRIdPTR ",\"calls\":%d,"
           "\"coldAllocations\":%" PRIu64 ",\"hotAllocations\":%" PRIu64 ","
           "\"mappings\":%" PRIu64 ",\"expectedMappingsPerCall\":%" PRIu64 ","
           "\"headerPayloadBytes\":%" PRIdPTR ",\"pageBytes\":%" PRIdPTR ","
           "\"peakAdmittedBytes\":%" PRIdPTR ",\"swiftStatus\":%d,"
           "\"readCalls\":%" PRIu64 ",\"hashUpdates\":%" PRIu64 ","
           "\"hashFinalizations\":%" PRIu64 ",\"copyCalls\":%" PRIu64 ","
           "\"bytesRead\":%" PRIu64 ",\"bytesCopied\":%" PRIu64 ","
           "\"readNanoseconds\":%" PRIu64 ",\"hashNanoseconds\":%" PRIu64 ","
           "\"copyNanoseconds\":%" PRIu64 ",\"passed\":%s}\n",
           argv[1], size, completed, cold_allocations, hot_allocations, maps, per_call_maps,
           header, page, peak, status, values[13], values[14], values[15], values[16],
           values[17], values[18], values[10], values[11], values[12], ok ? "true" : "false");
    return ok ? 0 : 1;
}
