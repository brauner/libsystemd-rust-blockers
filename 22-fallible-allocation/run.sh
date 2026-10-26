#!/bin/bash
# alloc aborts on allocation failure where libsystemd returns -ENOMEM.
. "$(dirname "$0")/../common.sh"
versions
set -o pipefail
ulimit -c 0

# 1. libsystemd reports a failed allocation as -ENOMEM, and documents it.
run "git -C $SYSTEMD_SRC grep -o 'return -ENOMEM' -- src/libsystemd | wc -l"
run "git -C $SYSTEMD_SRC grep -o -E '[a-z_]*log_oom[a-z_]*\(' -- src/libsystemd | sed 's/.*://' | sort | uniq -c"
run "git -C $SYSTEMD_SRC grep -l -e '-ENOMEM' -- 'man/sd*.xml' | wc -l"
run "grep -n 'xpointer=\"errors\"' $SYSTEMD_SRC/man/sd_bus_message_append.xml"
run "grep -n -A2 '<constant>-ENOMEM</constant>' $SYSTEMD_SRC/man/sd_bus_message_append_basic.xml"

# 2. The same with alloc on malloc(). A 100 MiB address space makes malloc() fail.
RF="--edition 2021 --crate-type staticlib -C panic=abort -O"
run "$RUSTC $RF $HERE/join.rs -o libjoin.a" &&
        run "$CC -O2 -Wall $HERE/main.c libjoin.a -o join" ||
        not_reproduced "build failed"
for f in c_join rust_join rust_join_try_reserve; do
        run "./join $f 3"
done
run "(ulimit -v 102400; ./join c_join 10000000)"
run "(ulimit -v 102400; ./join rust_join_try_reserve 10000000)"
run "(ulimit -v 102400; ./join rust_join 10000000)"
rc=$?
[ $rc -gt 128 ] && echo "rust_join() caller killed by SIG$(kill -l $((rc - 128)))"
[ $rc -eq $((128 + $(kill -l ABRT))) ] || not_reproduced "rust_join() did not abort"

# 3. Box::try_new(), Vec::push_within_capacity() and Vec::try_push().
if run "$RUSTC --edition 2021 --crate-type lib --emit=metadata -o try.rmeta $HERE/try.rs 2>&1 | tee try.err"; then
        not_reproduced "the fallible APIs compile on $($RUSTC --version)"
fi
run "grep -E '^error\[E0(658|599)\]' try.err"
[ "$(grep -c -E '^error\[E0(658|599)\]' try.err)" -eq 3 ] || not_reproduced "unexpected errors for try.rs"

# 4. Where an allocation failure goes, what 1.100 stabilizes, and -Zoom=panic.
run "grep -n -A3 '^const fn handle_error' $RUST_SRC/library/alloc/src/raw_vec/mod.rs"
run "grep -n -A6 'pub unsafe fn __rdl_alloc_error_handler' $RUST_SRC/library/alloc/src/alloc.rs"
run "grep -n -B4 -E 'pub fn (try_new|new_in)\\(x: T' $RUST_SRC/library/alloc/src/boxed.rs"
run "grep -n -B2 -E 'pub fn (push_within_capacity|try_with_capacity|try_reserve)\\(' $RUST_SRC/library/alloc/src/vec/mod.rs"
echo '#![no_std]' > empty.rs
run "RUSTC_BOOTSTRAP=1 $RUSTC_OLD -Zoom=panic --crate-type lib --emit=metadata -o empty.rmeta empty.rs"
run "RUSTC_BOOTSTRAP=1 $RUSTC -Zoom=panic --crate-type lib --emit=metadata -o empty.rmeta empty.rs"
c=$(git -C "$RUST_SRC" log -1 --first-parent --format=%h -S'oom: OomStrategy' -- compiler/rustc_session/src/options.rs)
run "git -C $RUST_SRC show -s --date=short --format='%h %cd %s%n%b' $c | grep -E 'Auto merge|Zoom'"
run "git -C $RUST_SRC show $c:src/version"

reproduced "an allocation failure in alloc's infallible API aborts the caller instead of returning -ENOMEM"
