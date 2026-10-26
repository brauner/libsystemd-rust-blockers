#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

void rs_hex64(uint64_t x, char *buf);
bool rs_fmt_u64(uint64_t x, char *buf, size_t n);

/* Leave poisoned shadow on the stack below us, as any earlier call would. */
static void __attribute__((noinline)) dirty_stack(void) {
        char junk[4096];
        __asm__ volatile("" : : "r"(junk) : "memory");
}

int main(int argc, char *argv[]) {
        char buf[32];

        dirty_stack();

        if (argc > 1 && strcmp(argv[1], "fmt") == 0)
                rs_fmt_u64(0xdeadbeef, buf, sizeof buf);  /* core::fmt writes the digits */
        else {
                rs_hex64(0xdeadbeef, buf);                 /* the crate writes the digits */
                buf[16] = 0;
        }

        if (buf[0] != 0)                /* MSan checks that buf[0] is initialized */
                printf("%s\n", buf);
        return 0;
}
