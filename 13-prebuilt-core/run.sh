#!/bin/bash
# The prebuilt core can't be rebuilt with our own flags on stable.
. "$(dirname "$0")/../common.sh"
versions

core=$(ls "$($RUSTC --print sysroot)"/lib/rustlib/*/lib/libcore-*.rlib)
mkdir core && (cd core && ar x "$core")
run "ls core"
# Built with panic=unwind, so it has a landing pad (see 11).
run "readelf -S -W core/*.o | grep -c gcc_except_table"
# Built without -Zcf-protection, so no x86 IBT/SHSTK property note (see 33).
run "readelf -n core/*.o | grep -E 'x86 feature' || echo 'no x86 feature property'"

# rustc says it itself when a no_std crate asks for unwinding.
run "$RUSTC --edition 2021 --crate-type staticlib -C panic=unwind $HERE/lib.rs -o x.a"

# cargo's build-std is nightly, and meson has nothing like it.
mkdir -p crate/src && cp "$HERE/lib.rs" crate/src/lib.rs
printf '[package]\nname = "x"\nversion = "0.0.0"\nedition = "2021"\n[lib]\ncrate-type = ["staticlib"]\n' > crate/Cargo.toml
run "(cd crate && $CARGO build --offline -Zbuild-std=core 2>&1 | head -2)"

grep -q gcc_except_table <(readelf -S -W core/*.o) || not_reproduced "core has no landing pads"
reproduced "the prebuilt core cannot be replaced on stable"
