#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>

int rust_append(char *buf, size_t size, const char *types, ...);
int rust_printv(char *a, char *b, size_t size, const char *fmt, va_list ap);
int rust_print(char *buf, size_t size, const char *fmt, ...);

static int call_printv(char *a, char *b, size_t size, const char *fmt, ...) {
        va_list ap;
        int r;

        va_start(ap, fmt);
        r = rust_printv(a, b, size, fmt, ap);
        va_end(ap);
        return r;
}

int main(void) {
        char a[256], b[256];

        rust_append(a, sizeof(a), "ysbtdi", (uint8_t) 7, "foo", 1, UINT64_MAX, 2.5, -42);
        printf("rust_append: %s\n", a);

        call_printv(a, b, sizeof(a), "%s=%d %.1f %llu", "bar", -1, 0.5, 1ULL << 40);
        printf("rust_printv: %s | %s\n", a, b);

        rust_print(a, sizeof(a), "%s=%d %.1f %llu", "baz", 3, 1.5, 1ULL << 41);
        printf("rust_print:  %s\n", a);
        return 0;
}
