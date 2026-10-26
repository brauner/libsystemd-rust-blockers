#include <stdio.h>
#include <stdint.h>

uint32_t rs_basic(uint32_t v);
uint32_t rs_sd(uint32_t v);

int main(void) {
        printf("%u %u\n", rs_basic(1), rs_sd(2));
        return 0;
}
