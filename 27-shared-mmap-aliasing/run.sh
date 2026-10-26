#!/bin/bash
# Through &Header, rustc assumes the MAP_SHARED journal header doesn't change.
. "$(dirname "$0")/../common.sh"
versions

R="--edition 2021 -O -C panic=abort --crate-type staticlib $HERE/reader.rs"

run "$RUSTC $R -o libreader.a" || exit 1
run "$CC -O2 -I$HERE -c $HERE/reader.c $HERE/main.c" || exit 1
run "$CC main.o reader.o libreader.a -o journal" || exit 1
run "./journal | tee out"

# &Header is a noalias readonly pointer, so the load after the call is gone.
run "$RUSTC $R --emit=llvm-ir -o - | grep -e '^define.*@reads_' -e ' load ' -e '@wait_for_journald()'"
run "objdump -d --no-show-raw-insn -M intel --disassemble=reads_ref libreader.a | grep -A7 '<reads_ref>:'"
run "objdump -d --no-show-raw-insn -M intel --disassemble=reads_c reader.o | grep -A12 '<reads_c>:'"

# ObjectHeader is _packed_. Rust rejects references to its fields.
P="--edition 2021 --crate-type lib $HERE/packed.rs -o x.rlib"
run "$RUSTC $P" && not_reproduced "a reference to a packed field compiles"
run "$RUSTC $P --cfg ok" || exit 1
run "$RUSTC $P --cfg atomic"

grep -F 'Rust, &Header:' out | grep -F 'before 0, after 0' >/dev/null &&
grep -F 'C, const struct header *:' out | grep -F 'before 0, after 1' >/dev/null ||
        not_reproduced "the &Header reader saw the new entry"
reproduced "reading through &Header, rustc keeps n_entries from before the call (noalias readonly); C, a raw pointer and read_volatile() read it again"
