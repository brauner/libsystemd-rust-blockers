#include <stdint.h>

uint32_t rs_add(uint32_t a, uint32_t b);

/* The C part of the library. rs_add() comes from add.c or from rs.rs. */
uint32_t c_add3(uint32_t a, uint32_t b, uint32_t c) {
        return rs_add(rs_add(a, b), c);
}
