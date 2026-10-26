#!/bin/bash
# A dylib only works with the rustc that built it.
. "$(dirname "$0")/../common.sh"
versions
printf '# old: %s\n' "$($RUSTC_OLD --version)"

R="-C panic=abort -O"
mkdir new old

run "$RUSTC --edition 2021 --crate-type dylib $R $HERE/sdshared.rs --out-dir new" || exit 1
run "$RUSTC --edition 2021 $R $HERE/user.rs -L new --extern sdshared=new/libsdshared.so -o user" || exit 1
run "LD_LIBRARY_PATH=new ./user"
[ $? -eq 5 ] || not_reproduced "same rustc does not work either"

# The same library with the other rustc on either side.
run "$RUSTC_OLD --edition 2021 $R $HERE/user.rs -L new --extern sdshared=new/libsdshared.so -o user-old" && \
        not_reproduced "older rustc accepted the newer dylib"
run "$RUSTC_OLD --edition 2021 --crate-type dylib $R $HERE/sdshared.rs --out-dir old" || exit 1
run "$RUSTC --edition 2021 $R $HERE/user.rs -L old --extern sdshared=old/libsdshared.so -o user-new" && \
        not_reproduced "newer rustc accepted the older dylib"

reproduced "a dylib is usable only by the rustc that built it"
