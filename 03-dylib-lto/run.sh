#!/bin/bash
# A Rust-ABI shared library cannot be built with LTO on stable.
. "$(dirname "$0")/../common.sh"
versions

R="--edition 2021 -C panic=abort -O"
run "$RUSTC $R --crate-type dylib $HERE/sdshared.rs" || exit 1
ok=1
for lto in fat thin; do
        run "$RUSTC $R --crate-type dylib -C lto=$lto $HERE/sdshared.rs -o lto-$lto.so" && ok=0
done
# The C-ABI crate types take it.
run "$RUSTC $R --crate-type staticlib -C lto=fat $HERE/sdshared.rs" || ok=0
run "$RUSTC $R --crate-type cdylib -C lto=fat $HERE/sdshared.rs -o cdylib.so" || ok=0
# The escape hatch is a nightly flag.
run "$RUSTC $R --crate-type dylib -C lto=fat -Zdylib-lto $HERE/sdshared.rs -o lto-z.so"

[ $ok -eq 1 ] || not_reproduced "unexpected LTO behaviour"
reproduced "-C lto is rejected for crate type dylib without the nightly -Zdylib-lto"
