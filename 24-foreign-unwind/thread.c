/* pthread_exit() and pthread_cancel() are forced unwinds in glibc. */
#define _GNU_SOURCE
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

void lib_call(void (*cb)(void));

static void exit_callback(void) {
        pthread_exit((void *) 42);
}

/* Blocks in ppoll(), a cancellation point, like sd_bus_wait() does. */
static void cancel_callback(void) {
        ppoll(NULL, 0, NULL, NULL);
}

static void *thread(void *cb) {
        lib_call(cb);
        puts("thread: lib_call returned");
        return NULL;
}

int main(int argc, char *argv[]) {
        int cancel = argc > 1 && strcmp(argv[1], "cancel") == 0;
        pthread_t t;
        void *ret;

        setvbuf(stdout, NULL, _IONBF, 0);
        pthread_create(&t, NULL, thread, cancel ? cancel_callback : exit_callback);
        if (cancel)
                pthread_cancel(t);
        pthread_join(t, &ret);
        printf("main: thread ended: %s\n",
               ret == PTHREAD_CANCELED ? "cancelled" : ret == (void *) 42 ? "pthread_exit(42)" : "returned");
        return 0;
}
