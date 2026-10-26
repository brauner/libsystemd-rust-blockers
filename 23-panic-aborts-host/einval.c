/* The same kind of mistake against the real libsystemd, a NULL message. */
#include <stdio.h>
#include <string.h>

/* From <systemd/sd-bus.h>, so that only libsystemd.so.0 is needed. */
typedef struct sd_bus_message sd_bus_message;
int sd_bus_message_append(sd_bus_message *m, const char *types, ...);

int main(void) {
        int r = sd_bus_message_append(NULL, "s", "foo");

        printf("sd_bus_message_append(NULL, \"s\", \"foo\") = %d (%s)\n", r, strerror(-r));
        printf("caller still running\n");
        return 0;
}
