#!/bin/bash
# A cdylib can't be used as a crate, Rust programs only get its C ABI.
. "$(dirname "$0")/../common.sh"
versions

R="--edition 2021 -C panic=abort -O"
run "$RUSTC $R --crate-type cdylib $HERE/sdshared.rs -o libsdshared.so" || exit 1
run "readelf -S -W libsdshared.so | grep '\.rustc' || echo 'no .rustc section'"
run "$RUSTC $R $HERE/user.rs -L . --extern sdshared=libsdshared.so -o user" && \
        not_reproduced "the cdylib was accepted as a crate"
run "$RUSTC $R $HERE/user-ffi.rs -L . -o user-ffi" || exit 1
run "LD_LIBRARY_PATH=. ./user-ffi"
[ $? -eq 5 ] || not_reproduced "the C ABI route does not work either"
reproduced "a cdylib is not a crate, Rust users go through extern \"C\" declarations"
