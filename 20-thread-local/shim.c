/* Workaround 1: the thread-local variable stays in C. */
#include <threads.h>

static thread_local void *default_event = NULL;

void *default_event_get(void) {
        return default_event;
}

void default_event_set(void *e) {
        default_event = e;
}
