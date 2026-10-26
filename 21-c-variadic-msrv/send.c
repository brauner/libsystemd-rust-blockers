#include <stdarg.h>
#include <stdio.h>

int rust_send_f64(char *buf, size_t size, const char *format, ...);
int rust_send_u64x2(char *buf, size_t size, const char *format, ...);
int rust_send_c_helper(char *buf, size_t size, const char *format, ...);

/* The C helper for rust_send_c_helper(). */
void skip_long_double(va_list *ap) {
        (void) va_arg(*ap, long double);
}

/* The same loop in C, like fill_iovec_sprintf() in journal-send.c. */
static int c_send(char *buf, size_t size, const char *format, ...) {
        size_t off = 0;
        va_list ap;

        va_start(ap, format);
        while (format) {
                va_list aq;
                int r;

                if (off > 0)
                        buf[off - 1] = ' ';
                va_copy(aq, ap);
                r = vsnprintf(buf + off, size - off, format, aq);
                va_end(aq);
                off += r + 1;
                (void) va_arg(ap, long double);
                format = va_arg(ap, const char *);
        }
        va_end(ap);
        return off - 1;
}

#define ARGS "A=%Lf", 1.0L, "B=%Lf", 2.0L, "C=%Lf", 3.0L, NULL

int main(void) {
        char buf[256];

        c_send(buf, sizeof(buf), ARGS);
        printf("C:              %s\n", buf);
        rust_send_f64(buf, sizeof(buf), ARGS);
        printf("Rust, f64:      %s\n", buf);
        rust_send_u64x2(buf, sizeof(buf), ARGS);
        printf("Rust, 2 x u64:  %s\n", buf);
        rust_send_c_helper(buf, sizeof(buf), ARGS);
        printf("Rust, C helper: %s\n", buf);
        return 0;
}
