#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

ssize_t rs_format_id(uint64_t id, char *p, size_t n);

__attribute__((visibility("default"))) ssize_t sd_demo_format_id(uint64_t id, char *p, size_t n) {
        return rs_format_id(id, p, n);
}
