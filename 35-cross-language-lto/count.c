#include <stddef.h>

#include "h.h"

size_t c_count_empty(const char *const *v, size_t n) {
        size_t k = 0;

        for (size_t i = 0; i < n; i++)
                k += isempty(v[i]);
        return k;
}
