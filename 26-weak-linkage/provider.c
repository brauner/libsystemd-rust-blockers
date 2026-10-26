/* Like src/shared/log-assert-critical.c, which libsystemd.so doesn't link. */
#include <stdbool.h>

bool optional_hook(void) {
        return true;
}
