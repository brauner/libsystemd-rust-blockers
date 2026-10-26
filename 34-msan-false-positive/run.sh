#!/bin/bash
# MSan reports memory that Rust code or the prebuilt core wrote as uninitialized.
. "$(dirname "$0")/../common.sh"
versions
run "$CLANG --version | head -1"

R="--edition 2021 -O -C panic=abort --crate-type staticlib"
M="-fsanitize=memory -fsanitize-memory-track-origins -g -O1"

# What a fuzzer build of libsystemd with Rust code would look like today.
run "$RUSTC $R $HERE/rs.rs -o librs.a" || exit 1
run "$CLANG $M $HERE/main.c librs.a -o main" || exit 1
run "$CLANG -g -O1 $HERE/main.c librs.a -o main-nosan" || exit 1
run "./main-nosan hex"
run "./main hex" && not_reproduced "no MSan report"

# Stable rustc cannot instrument the crate.
run "$RUSTC $R -Z sanitizer=memory $HERE/rs.rs -o librs-msan.a"

# Nightly, faked with RUSTC_BOOTSTRAP=1, refuses because core isn't instrumented.
run "RUSTC_BOOTSTRAP=1 $RUSTC $R -Z sanitizer=memory -Z sanitizer-memory-track-origins $HERE/rs.rs -o librs-msan.a"

# Overriding that fixes the bytes the crate writes, not the ones core writes.
run "RUSTC_BOOTSTRAP=1 $RUSTC $R -Z sanitizer=memory -Z sanitizer-memory-track-origins -C unsafe-allow-abi-mismatch=sanitizer $HERE/rs.rs -o librs-msan.a" || exit 1
run "$CLANG $M $HERE/main.c librs-msan.a -o main-msan" || exit 1
run "./main-msan hex" || not_reproduced "instrumented crate still reported"
run "./main-msan fmt" && not_reproduced "no report for memory written by core"

reproduced "MSan false positives on memory written by Rust code, and by the prebuilt core even with the crate instrumented"
