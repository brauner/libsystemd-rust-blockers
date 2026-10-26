/* Weak, so NULL unless the linking unit defines it, like mempool_enabled(). */
#include <stdbool.h>
#include <stdio.h>

bool optional_hook(void) __attribute__((weak));

void report(void) {
        if (optional_hook)
                printf("C: optional_hook() linked in, returns %d\n", optional_hook());
        else
                puts("C: optional_hook() not linked in");
}
