#!/bin/bash
# No LTO across the C/Rust boundary with the toolchains distros use.
. "$(dirname "$0")/../common.sh"
versions
run "$CLANG --version | head -1"
run "$BINDGEN --version"

disas() { objdump -d --no-show-raw-insn "$1" | awk -v f="<$2>:" '$2 == f, /^$/'; }

R="--edition 2021 -O -C panic=abort"
cp "$HERE/rs.rs" .
# C trampolines as in src/rust/systemd-shared/meson.build:54.
run "$BINDGEN --use-core --ctypes-prefix core::ffi --wrap-static-fns --wrap-static-fns-path wrap --allowlist-function isempty $HERE/h.h -o h.rs" || exit 1
run "tail -1 wrap.c"
run "$RUSTC $R --crate-type staticlib rs.rs -o librs.a" || exit 1

# (a) GCC LTO, with the flags dpkg-buildflags and Fedora use for systemd.
G="-O2 -fPIC -fvisibility=hidden -flto=auto -ffat-lto-objects -I$HERE"
run "$CC $G -c $HERE/count.c -o count.o && $CC $G -c $HERE/lib.c -o lib.o && $CC $G -c wrap.c -o wrap.o" || exit 1
run "$CC $G -shared -Wl,--no-undefined -Wl,--version-script=$HERE/lib.sym lib.o count.o wrap.o librs.a -o libgcc.so" || exit 1
# Only calls to the Rust function are left in count_both().
run "disas libgcc.so count_both | grep call" || not_reproduced "Rust function inlined under GCC LTO"
# The Rust loop calls the trampoline for every element.
run "disas libgcc.so rs_count_empty | grep -E 'call|isempty'"
run "disas libgcc.so isempty__extern"

# (b) clang and rustc -C linker-plugin-lto. rustc 1.99 emits LLVM 23 bitcode.
T="--target=x86_64-unknown-linux-gnu"
C="-O2 -fPIC -fvisibility=hidden -flto=thin"
run "$CLANG $T $C -I$HERE -c $HERE/count.c -o count.lto.o && $CLANG $T $C -I$HERE -c $HERE/lib.c -o lib.lto.o && $CLANG $T $C -I$HERE -c wrap.c -o wrap.lto.o" || exit 1
run "$RUSTC $R --crate-type staticlib -C linker-plugin-lto rs.rs -o librs-lto.a" || exit 1
B="-shared -Wl,--no-undefined -Wl,--version-script=$HERE/lib.sym"
O="count.lto.o wrap.lto.o librs-lto.a"
run "$CLANG $T $C $B lib.lto.o $O -fuse-ld=lld -o x.so" && not_reproduced "ld.lld $($CLANG -dumpversion) read rustc's bitcode"
run "$CLANG $T $C $B lib.lto.o $O -fuse-ld=gold -o x.so"
# The MSRV's bitcode (LLVM 19) is older than clang's, that works.
run "$RUSTC_OLD $R --crate-type staticlib -C linker-plugin-lto rs.rs -o librs-old.a" || exit 1
run "$CLANG $T $C $B lib.lto.o ${O/librs-lto.a/librs-old.a} -fuse-ld=lld -o libclang-old.so" || exit 1
run "disas libclang-old.so count_both | grep -c call"
# rustc's own lld has LLVM 23 and inlines everything into count_both().
GCC_LD=$(dirname "$($RUSTC --print target-libdir)")/bin/gcc-ld
run "$CLANG $T $C $B lib.lto.o $O -fuse-ld=lld -B $GCC_LD -o libclang.so" || exit 1
run "disas libclang.so count_both | grep -c call"
# clang's default triple isn't rustc's, fatal with our -Wl,--fatal-warnings.
run "$CLANG $C -I$HERE -c $HERE/lib.c -o lib-pc.lto.o" || exit 1
run "$CLANG $T $C $B lib-pc.lto.o $O -fuse-ld=lld -B $GCC_LD -Wl,--fatal-warnings -o x.so"

# (c) Since 1.90 rustc links with rust-lld, which can't read GCC LTO objects.
run "$CC -O2 -fPIC -flto=auto -c $HERE/c.c -o c.o && ar rcs libc-lto.a c.o" || exit 1
M="$R --crate-type bin $HERE/main.rs -L . -l c"
run "$RUSTC $M -l static=c-lto -o main" && not_reproduced "rust-lld linked GCC LTO objects"
run "$RUSTC_OLD $M -l static=c-lto -o main-old && ./main-old" || exit 1
run "$RUSTC $M -l static=c-lto -C linker-features=-lld -o main && ./main" || exit 1
# Fat LTO objects also carry machine code. rust-lld links that, without LTO.
run "$CC -O2 -fPIC -flto=auto -ffat-lto-objects -c $HERE/c.c -o cfat.o && ar rcs libc-fat.a cfat.o" || exit 1
run "$RUSTC $M -l static=c-fat -o main-fat && ./main-fat && readelf -p .comment main-fat | grep -o 'Linker: LLD [0-9.]*'"

reproduced "no C<->Rust inlining with GCC LTO, rustc 1.99 bitcode rejected by LLVM 21, rust-lld cannot read GCC LTO objects"
