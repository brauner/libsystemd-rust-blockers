#!/bin/bash
# A panic in no_std Rust library code aborts the process that called it.
. "$(dirname "$0")/../common.sh"
versions
set -o pipefail
ulimit -c 0

# 1. How systemd builds Rust code.
run "grep -n -B2 -E \"'-C(overflow-checks=yes|panic=abort)'\" $SYSTEMD_SRC/meson.build"

# 2. Implicit panics in extern "C" functions, called from C with one bad argument each.
RF="--edition 2021 --crate-type staticlib -C panic=abort -C overflow-checks=yes -O"
run "$RUSTC $RF $HERE/lib.rs -o liblib.a" &&
        run "$CC -O2 -Wall $HERE/main.c liblib.a -o main" ||
        not_reproduced "build failed"
for t in index copy unwrap overflow; do
        run "./main $t"
        rc=$?
        [ $rc -gt 128 ] && echo "caller killed by SIG$(kill -l $((rc - 128)))"
        [ $rc -eq $((128 + $(kill -l ABRT))) ] || not_reproduced "'$t' did not abort the caller"
done

# 3. A panic handler cannot return, unwinding needs std, and so does catch_unwind().
if run "$RUSTC $RF $HERE/handler.rs -o libhandler.a"; then
        not_reproduced "a returning panic handler compiles"
fi
if run "$RUSTC --edition 2021 --crate-type staticlib -C panic=unwind -O $HERE/lib.rs -o libunwind.a"; then
        not_reproduced "no_std code builds with panic=unwind"
fi
run "grep -n -B1 'pub fn catch_unwind' $RUST_SRC/library/std/src/panic.rs"
run "grep -n -B2 'pub unsafe fn catch_unwind' $RUST_SRC/library/core/src/intrinsics/mod.rs"
run "grep -n -A1 '^#!\[unstable' $RUST_SRC/library/core/src/intrinsics/mod.rs"

# 4. What libsystemd does with a bad argument, assert_return().
run "grep -n -A17 '^#define assert_log' $SYSTEMD_SRC/src/basic/assert-util.h"
run "grep -n -A8 '^void log_assert_failed_return' $SYSTEMD_SRC/src/basic/assert-util.c"
run "grep -n -A13 '^_public_ int sd_bus_message_appendv(' $SYSTEMD_SRC/src/libsystemd/sd-bus/bus-message.c | grep assert_return"
run "$CC -O2 -Wall $HERE/einval.c -l:libsystemd.so.0 -o einval" && run ./einval
# Only libsystemd-shared defines the hook that makes assert_return() abort.
lib=$(ldd ./einval | awk '/libsystemd\.so\.0/ { print $3 }')
run "nm -D $lib | grep assert_return_is_critical"
run "grep -n -E 'BUILD_MODE_DEVELOPER|SYSTEMD_ASSERT_RETURN_IS_CRITICAL' $SYSTEMD_SRC/src/shared/log-assert-critical.c"

# 5. Everything that links libsystemd's code.
run "grep -n -A11 '^libsystemd = shared_library' $SYSTEMD_SRC/meson.build"
run "grep -n -A15 '^libshared = shared_library' $SYSTEMD_SRC/src/shared/meson.build"
run "grep -n -A3 '^executable_template = {' $SYSTEMD_SRC/meson.build"
run "grep -n '= executable_template +' $SYSTEMD_SRC/meson.build"
run "grep -n -A7 \"'name' : 'systemd',\$\" $SYSTEMD_SRC/src/core/meson.build"
run "grep -n -A10 -E '^(nss|pam)_template = \{' $SYSTEMD_SRC/meson.build"

reproduced "an implicit panic in a no_std extern \"C\" function aborts the calling process"
