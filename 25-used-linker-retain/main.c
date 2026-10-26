/* Entries like BUS_ERROR_MAP_ELF_REGISTER and STATIC_DESTRUCTOR_REGISTER. */
#include <stdio.h>

struct entry {
        const char *name;
};

__attribute__((section("my_set"), used, retain, aligned(sizeof(void *))))
static const struct entry c_entry = { "c" };

extern const struct entry __start_my_set[], __stop_my_set[];

/* Defined next to the Rust entry, so that the linker pulls that object in. */
void rust_init(void);

int main(void) {
        rust_init();
        for (const struct entry *e = __start_my_set; e < __stop_my_set; e++)
                printf("entry: %s\n", e->name);
        return 0;
}
