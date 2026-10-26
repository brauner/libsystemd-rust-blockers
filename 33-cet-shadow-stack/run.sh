#!/bin/bash
# Rust code in a C shared library drops its IBT/SHSTK (CET) marking.
. "$(dirname "$0")/../common.sh"
versions

# systemd passes these to rustc (meson.build:478-482).
R="--edition 2021 -O -C panic=abort -C overflow-checks=yes --crate-type staticlib"
# Leave out the crt files, Debian's aren't marked.
L="-shared -nostartfiles -Wl,--gc-sections"

run "readelf -n \$($CC -print-file-name=crti.o) | grep 'x86 feature' || echo 'no x86 feature property in crti.o'"

# The library in C only, compiled like distros compile C (-fcf-protection).
run "$CC -O2 -fPIC -fcf-protection=full -c $HERE/lib.c -o lib.o" || exit 1
run "$CC -O2 -fPIC -fcf-protection=full -c $HERE/add.c -o add.o" || exit 1
run "$CC $L lib.o add.o -o libc-only.so" || exit 1
run "readelf -n libc-only.so | grep 'x86 feature'" || not_reproduced "C-only library not marked"

# The same library with rs_add() in Rust.
run "$RUSTC $R $HERE/rs.rs -o librs.a" || exit 1
run "$CC $L lib.o librs.a -o libwith-rust.so" || exit 1
run "readelf -n libwith-rust.so | grep 'x86 feature'" && not_reproduced "still marked"

# Have the linker name the unmarked inputs.
run "$CC $L lib.o librs.a -o x.so -Wl,-z,cet-report=error"
mkdir core && (cd core && ar x "$($RUSTC --print target-libdir)"/libcore-*.rlib)
run "readelf -n core/*.o | grep -c 'x86 feature'"

# -Zcf-protection is nightly only and doesn't mark the prebuilt core.
run "$RUSTC $R -Z cf-protection=full $HERE/rs.rs -o librs-cf.a"
run "RUSTC_BOOTSTRAP=1 $RUSTC $R -Z cf-protection=full $HERE/rs.rs -o librs-cf.a" || exit 1
run "$CC $L lib.o librs-cf.a -o x.so -Wl,-z,cet-report=error"
run "$CC $L lib.o librs-cf.a -o libwith-rust-cf.so" || exit 1
run "readelf -n libwith-rust-cf.so | grep 'x86 feature'" && not_reproduced "marked with -Zcf-protection"

# -Zstack-protector is nightly only too, and the prebuilt core has none.
run "$RUSTC $R -Z stack-protector=strong $HERE/rs.rs -o librs-sp.a"
run "nm core/*.o | grep -c __stack_chk_fail"

reproduced "IBT/SHSTK marking dropped by stable Rust code and by the prebuilt core"
