#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

int rust_get_byte(const uint8_t *buf, size_t n, size_t i);
int rust_set_id(uint8_t *id, const uint8_t *src, size_t n);
int rust_find(const uint8_t *buf, size_t n, uint8_t c);
uint64_t rust_usec_add(uint64_t t, uint64_t timeout);

int main(int argc, char *argv[]) {
        uint8_t buf[4] = { 1, 2, 3, 4 }, id[16];

        /* Each call has one bad argument. */
        if (strcmp(argv[1], "index") == 0)
                printf("rust_get_byte() = %d\n", rust_get_byte(buf, sizeof(buf), 4));
        else if (strcmp(argv[1], "copy") == 0)
                printf("rust_set_id() = %d\n", rust_set_id(id, buf, sizeof(buf)));
        else if (strcmp(argv[1], "unwrap") == 0)
                printf("rust_find() = %d\n", rust_find(buf, sizeof(buf), 5));
        else if (strcmp(argv[1], "overflow") == 0)
                printf("rust_usec_add() = %" PRIu64 "\n", rust_usec_add(UINT64_MAX - 1, 2));

        printf("caller still running\n");
        return 0;
}
