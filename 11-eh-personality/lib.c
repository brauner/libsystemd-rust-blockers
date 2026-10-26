#include <stddef.h>
#include <stdint.h>

uint64_t rs_sum(const uint8_t *p, size_t n);

__attribute__((visibility("default"))) uint64_t sd_demo_sum(const uint8_t *p, size_t n) {
        return rs_sum(p, n);
}
