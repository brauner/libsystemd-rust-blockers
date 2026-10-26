#include <stdbool.h>

/* As isempty() in systemd's src/fundamental/string-util.h:104. */
static inline bool isempty(const char *a) {
        return !a || a[0] == '\0';
}
