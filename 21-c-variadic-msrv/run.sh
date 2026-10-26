#!/bin/bash
# C-variadic definitions need rustc 1.99, our MSRV is 1.85.
. "$(dirname "$0")/../common.sh"
versions
set -o pipefail
export LC_ALL=C

# 1. The public functions that are C-variadic or take a va_list, from clang's AST.
sed -n '/^_systemd_headers = \[/,/^\]/p' "$SYSTEMD_SRC/src/systemd/meson.build" | grep -o 'sd-[a-z0-9-]*\.h' > public.h.list
{ sed 's/.*/#include "&"/' public.h.list; printf '#include <stdarg.h>\nvoid va_list_probe(va_list ap);\n'; } > public.c
{ printf '#include "%s"\n' "$SYSTEMD_SRC"/src/systemd/*.h; printf '#include <stdarg.h>\nvoid va_list_probe(va_list ap);\n'; } > all.c

run "wc -l < public.h.list"
run "$CLANG -fsyntax-only -Xclang -ast-dump=json -I$SYSTEMD_SRC/src/systemd public.c | jq -r -f $HERE/count.jq | sort -u > public.txt"
run "cat public.txt"
run "cut -d' ' -f2,3 public.txt | sort | uniq -c"
# All the extern ones are exported by libsystemd.so.
run "grep -oE 'sd_[a-z0-9_]+' $SYSTEMD_SRC/src/libsystemd/libsystemd.sym | sort -u > exported.txt"
run "grep ' extern$' public.txt | cut -d' ' -f1 | sort | comm -12 - exported.txt | wc -l"
# The headers that are not installed add these.
run "$CLANG -fsyntax-only -Xclang -ast-dump=json all.c | jq -r -f $HERE/count.jq | sort -u > all.txt"
run "comm -13 public.txt all.txt"

# 2. Such functions in Rust, with our MSRV and with the current stable.
RF="--edition 2021 --crate-type staticlib -C panic=abort -O"
if run "$RUSTC_OLD $RF $HERE/variadic.rs -o libvariadic.a 2>&1 | tee old.err"; then
        not_reproduced "C-variadic definitions compile on $($RUSTC_OLD --version)"
fi
grep 'error\[E0658\]: C-variadic functions are unstable' old.err >/dev/null ||
        not_reproduced "$($RUSTC_OLD --version) rejects variadic.rs, but not as unstable"

run "$RUSTC $RF $HERE/variadic.rs -o libvariadic.a" &&
        run "$CC -O2 -Wall $HERE/main.c libvariadic.a -o variadic" &&
        run "./variadic | tee out.txt" &&
        run "diff -u $HERE/expected.txt out.txt" ||
        not_reproduced "C-variadic definitions do not work on $($RUSTC --version)"

# 3. sd_journal_send() reads a long double from its va_list, 1.99 cannot.
run "grep -n 'VA_FORMAT_ADVANCE' $SYSTEMD_SRC/src/libsystemd/sd-journal/journal-send.c"
run "grep -n 'long double' $SYSTEMD_SRC/src/basic/stdio-util.h"
if run "$RUSTC --edition 2021 --crate-type lib --emit=metadata -o long-double.rmeta $HERE/long-double.rs"; then
        not_reproduced "$($RUSTC --version) reads an f128 from a VaList"
fi
run "grep -rn 'long double' $RUST_SRC/library/core/src/ffi"
# What the closest stable types do with a long double from C, on x86_64.
if [ "$(uname -m)" = x86_64 ]; then
        run "$RUSTC $RF $HERE/send.rs -o libsend.a" &&
                run "$CC -O2 -Wall $HERE/send.c libsend.a -o send" &&
                run "./send | tee send.out"
        want=$(sed -n 's/^C: *//p' send.out)
        [ "$want" = "A=1.000000 B=2.000000 C=3.000000" ] || not_reproduced "the C reference is broken"
        [ "$(sed -n 's/^Rust, f64: *//p' send.out)" = "$want" ] && not_reproduced "f64 steps over a long double"
        [ "$(sed -n 's/^Rust, 2 x u64: *//p' send.out)" = "$want" ] && not_reproduced "2 x u64 step over a long double"
fi

# 4. Where the MSRV comes from, and which rustc Debian ships.
run "grep -n -B2 \"^rust_msrv = \" $SYSTEMD_SRC/meson.build"
run "git -C $SYSTEMD_SRC log -1 --format='%h %s%n%n%b' -S\"rust_msrv = '1.85'\" -- meson.build | grep -B1 -A1 'Debian 13'"
run "grep -n 'Debian 13' $SYSTEMD_SRC/docs/HACKING.md"
run "grep -n 'c_variadic' $RUST_SRC/compiler/rustc_feature/src/accepted.rs"
run "curl -s -m 30 'https://qa.debian.org/madison.php?package=rustc&text=on'"

msg="C-variadic definitions need rustc 1.99, systemd's MSRV is 1.85"
[ "$(uname -m)" = x86_64 ] && msg="$msg, and 1.99.1 cannot read an x86_64 long double from a VaList"
reproduced "$msg"
