#!/bin/bash
# There is no Rust runtime library to share.
. "$(dirname "$0")/../common.sh"
versions

for rc in "$RUSTC" "$RUSTC_OLD"; do
        sysroot=$($rc --print sysroot)
        host=$($rc -vV | awk '/^host:/{print $2}')
        run "ls $sysroot/lib/rustlib/$host/lib | grep -E '^lib(core|alloc|std)-'"
done

# A dynamically linked std program needs a libstd with the build hash in its name.
run "$RUSTC --edition 2021 -C prefer-dynamic $HERE/hello.rs -o hello" || exit 1
run "$RUSTC_OLD --edition 2021 -C prefer-dynamic $HERE/hello.rs -o hello-old" || exit 1
run "readelf -d hello hello-old | grep -E 'File:|NEEDED.*std'"

# -C prefer-dynamic does nothing for a staticlib, the -Z flag that would is nightly.
run "$RUSTC --edition 2021 --crate-type staticlib -C prefer-dynamic $HERE/lib.rs -o libdyn.a"
run "$RUSTC --edition 2021 --crate-type staticlib -Zstaticlib-prefer-dynamic $HERE/lib.rs -o libdyn2.a"

n1=$(readelf -d hello | grep -o 'libstd-[0-9a-f]*\.so')
n2=$(readelf -d hello-old | grep -o 'libstd-[0-9a-f]*\.so')
[ -n "$n1" ] && [ "$n1" != "$n2" ] || not_reproduced "libstd names match"
reproduced "core/alloc are rlib-only and libstd is $n1 vs $n2"
