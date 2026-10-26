#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int rust_join(const char *word, size_t n);
int rust_join_try_reserve(const char *word, size_t n);

/* The same in C, the way libsystemd does it. */
static int c_join(const char *word, size_t n) {
        size_t len = 0, allocated = 0;
        char *s = NULL;

        for (size_t i = 0; i < n; i++) {
                char item[64];
                int l = snprintf(item, sizeof(item), "%s%s%zu", i > 0 ? " " : "", word, i);

                if (len + l + 1 > allocated) {
                        size_t a = (len + l + 1) * 2;
                        char *t = realloc(s, a);
                        if (!t) {
                                free(s);
                                return -ENOMEM;
                        }
                        s = t;
                        allocated = a;
                }
                memcpy(s + len, item, l + 1);
                len += l;
        }

        free(s);
        return (int) len;
}

int main(int argc, char *argv[]) {
        size_t n = strtoul(argv[2], NULL, 0);
        int r;

        if (strcmp(argv[1], "c_join") == 0)
                r = c_join("systemd", n);
        else if (strcmp(argv[1], "rust_join") == 0)
                r = rust_join("systemd", n);
        else
                r = rust_join_try_reserve("systemd", n);

        if (r < 0)
                printf("%s(n=%zu) = %d (%s)\n", argv[1], n, r, strerror(-r));
        else
                printf("%s(n=%zu) = %d\n", argv[1], n, r);
        printf("caller still running\n");
        return 0;
}
