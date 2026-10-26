/* Like sd_bus_process() running a message handler with a _cleanup_ pending. */
#include <stdio.h>

static void cleanup(int *p) {
        puts("lib: cleanup ran");
}

void lib_call(void (*cb)(void)) {
        __attribute__((cleanup(cleanup))) int guard = 0;

        cb();
        puts("lib: callback returned");
}
