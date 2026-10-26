#include <stddef.h>

size_t c_count_empty(const char *const *v, size_t n);   /* C, in count.c */
size_t rs_count_empty(const char *const *v, size_t n);  /* Rust, in rs.rs */

__attribute__((visibility("default")))
size_t count_both(const char *const *v, size_t n) {
        return c_count_empty(v, n) + rs_count_empty(v, n);
}
