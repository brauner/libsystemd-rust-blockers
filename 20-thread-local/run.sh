#!/bin/bash
# no_std Rust has no thread-local statics on stable.
. "$(dirname "$0")/../common.sh"
versions
set -o pipefail

RF="--edition 2021 --crate-type staticlib -C panic=abort -O"

# sd-event's per-thread default event loop in no_std Rust.
if run "$RUSTC $RF $HERE/tls.rs -o libtls.a 2>&1 | tee tls.err"; then
        not_reproduced "#[thread_local] compiles on $($RUSTC --version)"
fi
grep -E 'error\[E0658\]: the .thread_local. attribute is an experimental feature' tls.err >/dev/null ||
        not_reproduced "rejected, but not as an unstable feature"

# RUSTC_BOOTSTRAP=1 only to show that the feature exists and works.
run "RUSTC_BOOTSTRAP=1 $RUSTC $RF -Zcrate-attr='feature(thread_local)' $HERE/tls.rs -o libtls.a" &&
        run "$CC -O2 -pthread $HERE/main.c libtls.a -o tls" &&
        run ./tls

# libsystemd's thread-local variables, and libbasic's, which is linked into it.
run "git -C $SYSTEMD_SRC grep -n 'static thread_local' -- src/libsystemd"
run "git -C $SYSTEMD_SRC grep 'static thread_local' -- src/libsystemd | wc -l"
run "git -C $SYSTEMD_SRC grep 'static thread_local' -- src/basic | wc -l"

# core has no thread-local storage, thread_local!() is std's.
run "grep -rn 'thread_local' $RUST_SRC/library/core/src"
run "grep -rn 'macro_rules! thread_local' $RUST_SRC/library"

# Workaround 1: the variable lives in C, Rust calls accessors.
run "$CC -O2 -c $HERE/shim.c -o shim.o" &&
        run "$RUSTC $RF $HERE/shim.rs -o libshim.a" &&
        run "$CC -O2 -pthread $HERE/main.c shim.o libshim.a -o shim" &&
        run ./shim &&
        run "objdump -dr --no-show-raw-insn --disassemble=rust_default_event_get libshim.a | sed -n '/<rust_default_event_get>:/,/^\$/p'"
# In a shared library C gets the dynamic TLS model, which works with dlopen().
run "$CC -O2 -fPIC -shared $HERE/shim.c -o libshim.so" &&
        run "readelf -dr libshim.so | grep -E 'TPOFF|DTPMOD|STATIC_TLS'"

# Workaround 2: the TLS access in assembly, x86_64 initial-exec only.
if [ "$(uname -m)" = x86_64 ]; then
        run "$RUSTC_OLD $RF $HERE/asm.rs -o libasm.a" &&
                run "$CC -O2 -pthread $HERE/main.c libasm.a -o asm" &&
                run ./asm &&
                run "$CC -shared -o libasm.so -Wl,--whole-archive libasm.a -Wl,--no-whole-archive" &&
                run "readelf -dr libasm.so | grep -E 'TPOFF|DTPMOD|STATIC_TLS'"
fi

reproduced "#[thread_local] is unstable (E0658) and core has no thread-local storage"
