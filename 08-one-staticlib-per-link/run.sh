#!/bin/bash
# Two Rust staticlibs from the same rustc can't be linked together.
. "$(dirname "$0")/../common.sh"
versions

R="--edition 2021 -C panic=abort -O --crate-type staticlib"
run "$RUSTC $R $HERE/basic.rs -o libbasic_rust.a" || exit 1
run "$RUSTC $R $HERE/sd.rs -o libsystemd_rust.a" || exit 1
run "nm -C libbasic_rust.a libsystemd_rust.a 2>/dev/null | grep -E ' T .*rust_begin_unwind'"
run "$CC -O2 $HERE/main.c libbasic_rust.a libsystemd_rust.a -Wl,--gc-sections -o main" && \
        not_reproduced "the two staticlibs linked"

# The nightly fix from rust-lang/rust#156950, unlocked with RUSTC_BOOTSTRAP=1.
run "$RUSTC $R -Zstaticlib-rename-internal-symbols $HERE/basic.rs -o libbasic_rust.a"
run "RUSTC_BOOTSTRAP=1 $RUSTC $R -Zstaticlib-rename-internal-symbols $HERE/basic.rs -o libbasic_rust.a" && \
run "RUSTC_BOOTSTRAP=1 $RUSTC $R -Zstaticlib-rename-internal-symbols $HERE/sd.rs -o libsystemd_rust.a" && \
run "$CC -O2 $HERE/main.c libbasic_rust.a libsystemd_rust.a -Wl,--gc-sections -o main && ./main"

reproduced "duplicate __rustc::rust_begin_unwind from two staticlibs"
