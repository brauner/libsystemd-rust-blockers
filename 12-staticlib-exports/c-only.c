/* The same function in C, for the size comparison. */
#include <stdint.h>
#include <stdio.h>
#include <sys/types.h>

__attribute__((visibility("default"))) ssize_t sd_demo_format_id(uint64_t id, char *p, size_t n) {
        int r = snprintf(p, n, "%016llx", (unsigned long long) id);
        return r < 0 || (size_t) r >= n ? -7 : r;
}
