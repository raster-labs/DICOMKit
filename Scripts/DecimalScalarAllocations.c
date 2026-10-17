/* Test-only macOS interposer. No code from this file enters library products. */
#include <malloc/malloc.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>

static int armed;
static uint64_t allocations, mappings;
void ds_probe_arm(void) { allocations = mappings = 0; armed = 1; }
void ds_probe_disarm(void) { armed = 0; }
uint64_t ds_probe_allocations(void) { return allocations; }
uint64_t ds_probe_mappings(void) { return mappings; }

#define COUNT() do { if (armed) ++allocations; } while (0)
static void *p_malloc(size_t n) { COUNT(); return malloc(n); }
static void *p_calloc(size_t n, size_t s) { COUNT(); return calloc(n, s); }
static void *p_realloc(void *p, size_t n) { COUNT(); return realloc(p, n); }
static void *p_valloc(size_t n) { COUNT(); return valloc(n); }
static void *p_aligned_alloc(size_t a, size_t n) { COUNT(); return aligned_alloc(a, n); }
static int p_posix_memalign(void **p, size_t a, size_t n) { COUNT(); return posix_memalign(p, a, n); }
static void *p_zone_malloc(malloc_zone_t *z, size_t n) { COUNT(); return malloc_zone_malloc(z, n); }
static void *p_zone_calloc(malloc_zone_t *z, size_t n, size_t s) { COUNT(); return malloc_zone_calloc(z, n, s); }
static void *p_zone_realloc(malloc_zone_t *z, void *p, size_t n) { COUNT(); return malloc_zone_realloc(z, p, n); }
static void *p_zone_valloc(malloc_zone_t *z, size_t n) { COUNT(); return malloc_zone_valloc(z, n); }
static void *p_zone_memalign(malloc_zone_t *z, size_t a, size_t n) { COUNT(); return malloc_zone_memalign(z, a, n); }
static void *p_mmap(void *a, size_t n, int p, int f, int d, off_t o) {
    if (armed) ++mappings;
    return mmap(a, n, p, f, d, o);
}
#define INTERPOSE(replacement, original) \
    __attribute__((used, section("__DATA,__interpose"))) \
    static const struct { const void *replacement; const void *original; } pair_##original = \
        {(const void *)(uintptr_t)&replacement, (const void *)(uintptr_t)&original}
INTERPOSE(p_malloc, malloc);
INTERPOSE(p_calloc, calloc);
INTERPOSE(p_realloc, realloc);
INTERPOSE(p_valloc, valloc);
INTERPOSE(p_aligned_alloc, aligned_alloc);
INTERPOSE(p_posix_memalign, posix_memalign);
INTERPOSE(p_zone_malloc, malloc_zone_malloc);
INTERPOSE(p_zone_calloc, malloc_zone_calloc);
INTERPOSE(p_zone_realloc, malloc_zone_realloc);
INTERPOSE(p_zone_valloc, malloc_zone_valloc);
INTERPOSE(p_zone_memalign, malloc_zone_memalign);
INTERPOSE(p_mmap, mmap);
