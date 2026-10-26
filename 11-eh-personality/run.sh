#!/bin/bash
# A no_std staticlib needs rust_eh_personality to link with our flags.
. "$(dirname "$0")/../common.sh"
versions

# meson's defaults and our --gc-sections.
R="--edition 2021 -C panic=abort -O -C debug-assertions=yes --crate-type staticlib"
L="-fPIC -shared -fvisibility=hidden -Wl,--no-undefined -Wl,--gc-sections"

run "$RUSTC $R $HERE/sum.rs -o libsum.a" || exit 1
run "$CC $L $HERE/lib.c libsum.a -o libdemo.so" && not_reproduced "linked without a personality"

# The reference comes from the one landing pad in the prebuilt core.
core=$(ls "$($RUSTC --print sysroot)"/lib/rustlib/*/lib/libcore-*.rlib)
mkdir core && (cd core && ar x "$core")
run "for o in core/*.o; do readelf -S -W \$o | grep -o '\.gcc_except_table\.[^ ]*'; done | sed 's/^\.gcc_except_table\.//' | c++filt"

# The documented way is a lang item, which stable rejects.
run "$RUSTC --edition 2021 --crate-type lib -C panic=abort $HERE/lang.rs -o /dev/null"
# The flag that would keep core from needing it is nightly too.
run "$RUSTC --edition 2021 -C panic=immediate-abort --crate-type staticlib $HERE/sum.rs -o x.a"

# Defining the internal symbol by hand works.
run "$RUSTC $R --cfg stub $HERE/sum.rs -o libsum-stub.a" || exit 1
run "$CC $L $HERE/lib.c libsum-stub.a -o libdemo.so" || not_reproduced "the stub does not help"
reproduced "undefined rust_eh_personality unless the internal symbol is defined by hand"
