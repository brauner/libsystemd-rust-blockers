#include <stdint.h>

/* The first fields of struct Header, src/libsystemd/sd-journal/journal-def.h. */
struct header {
        uint8_t signature[8];
        uint32_t compatible_flags;
        uint32_t incompatible_flags;
        uint8_t state;
        uint8_t reserved[7];
        uint8_t ids[4][16];     /* file_id, machine_id, tail_entry_boot_id, seqnum_id */
        uint64_t header_size;
        uint64_t arena_size;
        uint64_t hash_tables[4];
        uint64_t tail_object_offset;
        uint64_t n_objects;
        uint64_t n_entries;
};

/* n_entries read before and after wait_for_journald(). */
struct reads {
        uint64_t before, after;
};

/* Anything the compiler cannot see into: a syscall, journal_file_move_to_object(), ... */
void wait_for_journald(void);
