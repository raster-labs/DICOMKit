/* Disposable test instrumentation only; never linked into DICOMKit products. */
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <sys/mman.h>

static int mode;
static int armed;
static int maps;
static int unmaps;
void dc_external_probe_arm(int value) { mode = value; maps = 0; unmaps = 0; armed = 1; }
void dc_external_probe_disarm(void) { armed = 0; }
int dc_external_probe_maps(void) { return maps; }
int dc_external_probe_unmaps(void) { return unmaps; }

static void *probe_mmap(void *address, size_t size, int protection, int flags, int fd, off_t offset) {
    if (armed) {
        ++maps;
        if (mode == 1) return mmap(NULL, 0, protection, flags, fd, offset); /* Real kernel EINVAL. */
    }
    return mmap(address, size, protection, flags, fd, offset);
}
static int probe_mutex_init(pthread_mutex_t *mutex, const pthread_mutexattr_t *attributes) {
    if (armed && (mode == 2 || mode == 3)) return EAGAIN;
    return pthread_mutex_init(mutex, attributes);
}
static int probe_munmap(void *address, size_t size) {
    if (armed) {
        ++unmaps;
        if (mode == 3) return munmap((char *)address + 1, size); /* Real kernel EINVAL. */
    }
    return munmap(address, size);
}
#define INTERPOSE(replacement, original) \
    __attribute__((used, section("__DATA,__interpose"))) \
    static const struct { const void *replacement; const void *original; } pair_##original = \
        {(const void *)(uintptr_t)&replacement, (const void *)(uintptr_t)&original}
INTERPOSE(probe_mmap, mmap);
INTERPOSE(probe_mutex_init, pthread_mutex_init);
INTERPOSE(probe_munmap, munmap);
