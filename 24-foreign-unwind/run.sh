#!/bin/bash
# A foreign unwind through a no_std panic=abort Rust frame skips Drop or aborts.
. "$(dirname "$0")/../common.sh"
versions
ulimit -c 0     # some of the test programs abort on purpose

# systemd's Rust flags (meson.build:461-482, plus meson's debug-assertions).
R="--edition 2021 -O -C debug-assertions=yes -C overflow-checks=yes --crate-type staticlib $HERE/lib.rs"

# Run a test program like run() does, and keep its output and exit status.
declare -A out status
try() {
        local key=$1; shift
        printf '\n$ %s\n' "$*"
        out[$key]=$("$@" 2>&1)
        status[$key]=$?
        [ -n "${out[$key]}" ] && printf '%s\n' "${out[$key]}"
        printf '[exit status %d]\n' "${status[$key]}"
}

# What a run did, in a few words.
outcome() {
        local o=${out[$1]}
        case ${status[$1]} in
        0)   [[ $o == *ran* ]] && echo "cleanup ran, passed on" || echo "cleanup skipped, passed on" ;;
        134) [[ $o == *"terminate called"* ]] && echo "std::terminate()" ||
             { [[ $o == *ran* ]] && echo "cleanup ran, abort()" || echo "abort()"; } ;;
        *)   echo "exit status ${status[$1]}" ;;
        esac
}

# Plain C passes exceptions through because gcc emits unwind tables anyway.
run "$CC -Q --help=common | grep -e -fasynchronous-unwind-tables"

run "$CXX -O2 -c $HERE/main.cpp" || exit 1
run "$CC -O2 -pthread -c $HERE/thread.c" || exit 1

# The library call in C, as Debian builds it and with Fedora's -fexceptions.
run "$CC -O2 -c $HERE/lib.c -o c.o" || exit 1
run "$CC -O2 -fexceptions -c $HERE/lib.c -o c-fexceptions.o" || exit 1

# The library call in Rust, within the policy: no_std, panic=abort.
run "$RUSTC $R -C panic=abort -o rust-C.a" || exit 1
run "$RUSTC $R -C panic=abort --cfg c_unwind -o rust-C-unwind.a" || exit 1
run "$RUSTC_OLD $R -C panic=abort -o rust-1.85-C.a" || exit 1

# panic=unwind needs std, and "C-unwind" needs a personality routine.
run "$RUSTC $R -C panic=unwind -o x.a" && not_reproduced "no_std builds with panic=unwind"
run "$RUSTC $R -C panic=abort --cfg c_unwind --cfg no_personality -o x.a" || exit 1
run "$CXX -Wl,--gc-sections main.o x.a -o x" && not_reproduced "C-unwind links without rust_eh_personality"

# extern "C": a nounwind call without a landing pad, and no uwtable on 1.85.
for rc in "$RUSTC" "$RUSTC_OLD"; do
        run "$rc $R -C panic=abort --emit=llvm-ir -o - | grep -e '^define.*@lib_call' -e '%cb()' -e '^attributes'"
done
# extern "C-unwind": a landing pad that runs the Drop, then panic_cannot_unwind().
run "$RUSTC $R -C panic=abort --cfg c_unwind --emit=llvm-ir -o - | sed -n '/^define.*@lib_call/,/^}/p' | grep -e '^define' -e '%cb()' -e landingpad -e '^ *cleanup$' -e '; call'"

# Outside the policy, for comparison: with std.
run "$RUSTC $R --cfg with_std -C panic=abort --cfg c_unwind -o std-abort-C-unwind.a" || exit 1
run "$RUSTC $R --cfg with_std -C panic=unwind -o std-unwind-C.a" || exit 1
run "$RUSTC $R --cfg with_std -C panic=unwind --cfg c_unwind -o std-unwind-C-unwind.a" || exit 1

libs="c.o c-fexceptions.o rust-C.a rust-1.85-C.a rust-C-unwind.a std-abort-C-unwind.a std-unwind-C.a std-unwind-C-unwind.a"
for lib in $libs; do
        n=${lib%.*}
        printf '\n######## %s\n' "$lib"
        run "$CXX -Wl,--gc-sections main.o $lib -o throw-$n" || exit 1
        run "$CC -pthread -Wl,--gc-sections thread.o $lib -o thread-$n" || exit 1
        try "throw $n" ./throw-$n
        try "exit $n" ./thread-$n exit
        try "cancel $n" ./thread-$n cancel
done

printf '\n%-20s %-27s %-27s %s\n' "" "C++ throw" "pthread_exit()" "pthread_cancel()"
for lib in $libs; do
        n=${lib%.*}
        printf '%-20s %-27s %-27s %s\n' "$n" "$(outcome "throw $n")" "$(outcome "exit $n")" "$(outcome "cancel $n")"
done

[[ ${out[throw c-fexceptions]} == *"cleanup ran"*caught* &&
   ${out[cancel c-fexceptions]} == *"cleanup ran"*cancelled* &&
   ${out[throw rust-C]} != *"drop ran"* && ${out[cancel rust-C]} != *"drop ran"* &&
   ${status[throw rust-C-unwind]} == 134 && ${status[cancel rust-C-unwind]} == 134 ]] ||
        not_reproduced "Rust frames behave like C frames built with -fexceptions"
reproduced "C built with -fexceptions runs its cleanup and passes the unwind on; a no_std panic=abort Rust frame skips its Drop (extern \"C\", undefined behavior) or aborts (extern \"C-unwind\")"
