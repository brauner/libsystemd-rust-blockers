/* Two threads each set their default event, then read it back. */
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>

void *rust_default_event_get(void);
void rust_default_event_set(void *e);

static pthread_barrier_t barrier;

static void *thread(void *p) {
        rust_default_event_set(p);
        pthread_barrier_wait(&barrier); /* both have set theirs */
        printf("thread %zu: default event %p\n", (size_t) (uintptr_t) p, rust_default_event_get());
        return NULL;
}

int main(void) {
        pthread_t a, b;

        pthread_barrier_init(&barrier, NULL, 2);
        pthread_create(&a, NULL, thread, (void *) 0x1);
        pthread_create(&b, NULL, thread, (void *) 0x2);
        pthread_join(a, NULL);
        pthread_join(b, NULL);
        printf("main: default event %p\n", rust_default_event_get());
        return 0;
}
