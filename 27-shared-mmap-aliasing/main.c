/* journald and the reader map the same file MAP_SHARED, like mmap-cache.c. */
#define _GNU_SOURCE
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>

#include "header.h"

struct reads reads_c(const struct header *h);
struct reads reads_ref(const struct header *h);
struct reads reads_ptr(const struct header *h);
struct reads reads_volatile(const struct header *h);

static struct header *journald;

/* journald appends an entry while the reader waits. */
void wait_for_journald(void) {
        journald->n_entries++;
}

static void show(const char *what, struct reads (*reads)(const struct header *), const struct header *h) {
        journald->n_entries = 0;
        struct reads r = reads(h);
        printf("%-26s n_entries before %llu, after %llu\n", what,
               (unsigned long long) r.before, (unsigned long long) r.after);
}

int main(void) {
        int fd = memfd_create("journal", 0);

        if (fd < 0 || ftruncate(fd, 4096) < 0)
                return 1;

        const struct header *h = mmap(NULL, 4096, PROT_READ, MAP_SHARED, fd, 0);
        journald = mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
        if (h == MAP_FAILED || journald == MAP_FAILED)
                return 1;

        show("C, const struct header *:", reads_c, h);
        show("Rust, &Header:", reads_ref, h);
        show("Rust, *const Header:", reads_ptr, h);
        show("Rust, read_volatile():", reads_volatile, h);
        return 0;
}
