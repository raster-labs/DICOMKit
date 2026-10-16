/* Test driver: prepare bytes before arming; also run each path in a fresh process. */
#include <fenv.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

extern uint8_t dicom_decimal_scalar_probe(const void *, intptr_t, uint64_t *);
extern void ds_probe_arm(void), ds_probe_disarm(void);
extern uint64_t ds_probe_allocations(void), ds_probe_mappings(void);

static void run(const char *hex, int repetitions) {
    uint8_t bytes[128];
    size_t count = strcspn(hex, "\r\n") / 2;
    if (count > sizeof bytes) exit(2);
    for (size_t i = 0; i < count; ++i) {
        unsigned int byte;
        if (sscanf(hex + 2*i, "%2x", &byte) != 1) exit(2);
        bytes[i] = byte;
    }
    uint64_t bits = 0, allocations = 0, mappings = 0, first_bits = 0;
    uint8_t status = 0, first_status = 0;
    int stable = 1;
    const int modes[] = {FE_TONEAREST, FE_DOWNWARD, FE_UPWARD, FE_TOWARDZERO};
    for (int i = 0; i < repetitions; ++i) {
        if (fesetround(modes[i % 4]) != 0 || fegetround() != modes[i % 4]) exit(3);
        ds_probe_arm();
        status = dicom_decimal_scalar_probe(count ? bytes : NULL, (intptr_t)count, &bits);
        ds_probe_disarm();
        allocations += ds_probe_allocations(); mappings += ds_probe_mappings();
        if (i == 0) { first_bits = bits; first_status = status; }
        else if (bits != first_bits || status != first_status) stable = 0;
    }
    printf("{\"status\":%u,\"bits\":\"%016" PRIx64 "\",\"allocations\":%" PRIu64
           ",\"mappings\":%" PRIu64 ",\"stable\":%d,\"calls\":%d}\n",
           status, bits, allocations, mappings, stable, repetitions);
}
int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "--control") == 0) {
        ds_probe_arm();
        void *p = malloc(65536);
        void *m = mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0);
        ds_probe_disarm();
        printf("{\"allocations\":%" PRIu64 ",\"mappings\":%" PRIu64 "}\n",
               ds_probe_allocations(), ds_probe_mappings());
        free(p); if (m != MAP_FAILED) munmap(m, 4096);
    } else if (argc > 1) {
        run(argv[1], argc > 2 ? atoi(argv[2]) : 400);
    } else {
        char line[258];
        while (fgets(line, sizeof line, stdin)) run(line, 4);
    }
    return 0;
}
