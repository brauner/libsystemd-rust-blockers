#!/bin/bash
# A shared library linked by rustc can't have versioned symbols.
. "$(dirname "$0")/../common.sh"
versions

R="--edition 2021 -C panic=abort -O --crate-type cdylib $HERE/sd.rs"
V="-C link-arg=-Wl,--version-script=$HERE/demo.sym"

run "$CC -O2 -fPIC -fvisibility=hidden -shared $HERE/sd.c -Wl,--version-script=$HERE/demo.sym -o libc.so" || exit 1
run "nm -D --defined-only libc.so"

# rustc passes its own version script, ours comes second.
run "$RUSTC $R $V -o librust-lld.so"
run "nm -D --defined-only librust-lld.so"
run "$RUSTC $R $V -C linker-features=-lld -o librust-bfd.so"

nm -D --defined-only libc.so | grep -q 'sd_demo_open@@LIBDEMO_209' || not_reproduced "C side not versioned"
nm -D --defined-only librust-lld.so | grep -q '@@LIBDEMO' && not_reproduced "rust-lld kept the versions"
[ -e librust-bfd.so ] && not_reproduced "GNU ld accepted the version script"
reproduced "rust-lld drops the symbol versions, GNU ld refuses the link"
