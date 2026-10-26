#include "header.h"

struct reads reads_c(const struct header *h) {
        uint64_t before = h->n_entries;

        wait_for_journald();
        return (struct reads) { before, h->n_entries };
}
