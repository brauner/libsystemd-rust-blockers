# 08. Two Rust static libraries can't be linked together

A Rust static library, crate type `staticlib`, is a final artifact. It
carries its own panic handler, `__rustc::rust_begin_unwind`, plus its
own copy of `core` and `compiler_builtins`. The mangled name of that
handler only depends on the compiler. So two static libraries built by
the same rustc can't be linked into one program or shared object. The
link fails with a duplicate symbol.

The fix exists as the nightly option
`-Zstaticlib-rename-internal-symbols`.

## Why it matters

Our C code is split into static libraries that meson combines in
different ways:

- libsystemd-shared pulls in libbasic_static, libshared_static and
  libsystemd_static with `link_whole` (src/shared/meson.build:466).
- The NSS modules link libsystemd_static, libshared_static and
  libbasic_static (meson.build:2335).

If each of them had its own Rust part, every one of these links would
fail. The whole tree would need exactly one Rust static library holding
all of our Rust code, and every C library and program would link that.

## Reproducer

    ./08-one-staticlib-per-link/run.sh

This builds the Rust parts of a libbasic_static and a libsystemd_static,
basic.rs and sd.rs, as two static libraries with the same rustc. Both of
them contain the panic handler:

    $ nm -C libbasic_rust.a libsystemd_rust.a 2>/dev/null | grep -E ' T .*rust_begin_unwind'
    0000000000000000 T __rustc::rust_begin_unwind
    0000000000000000 T __rustc::rust_begin_unwind

So a C program, main.c, can't link both of them:

    $ gcc -O2 08-one-staticlib-per-link/main.c libbasic_rust.a libsystemd_rust.a -Wl,--gc-sections -o main
    /usr/bin/x86_64-linux-gnu-ld.bfd: libsystemd_rust.a(libsystemd_rust.sd.89926b25a36d323-cgu.0.rcgu.o): in function `__rustc::rust_begin_unwind':
    [...]: multiple definition of `__rustc::rust_begin_unwind'; libbasic_rust.a[...]: first defined here
    collect2: error: ld returned 1 exit status

Stable rustc rejects the option:

    $ rustc +1.99.1 --edition 2021 -C panic=abort -O --crate-type staticlib -Zstaticlib-rename-internal-symbols 08-one-staticlib-per-link/basic.rs -o libbasic_rust.a
    error: the option `Z` is only accepted on the nightly compiler

`RUSTC_BOOTSTRAP=1` unlocks it on a stable compiler, which is not
something to ship. With both libraries rebuilt that way the program
links and runs:

    $ RUSTC_BOOTSTRAP=1 rustc +1.99.1 ... -Zstaticlib-rename-internal-symbols 08-one-staticlib-per-link/basic.rs -o libbasic_rust.a
    $ RUSTC_BOOTSTRAP=1 rustc +1.99.1 ... -Zstaticlib-rename-internal-symbols 08-one-staticlib-per-link/sd.rs -o libsystemd_rust.a
    $ gcc -O2 08-one-staticlib-per-link/main.c libbasic_rust.a libsystemd_rust.a -Wl,--gc-sections -o main && ./main
    8 16

## Upstream

`-Zstaticlib-rename-internal-symbols` came with rust-lang/rust#156950,
merged on 2026-06-16, and is nightly only
(compiler/rustc_session/src/options.rs:2925).

rust-lang/rfcs#3993, about C linkers linking rlibs, and
rust-lang/rust#73632 "Formal support for linking rlibs using a non-Rust
linker" are both still open.

## Workarounds

One crate graph for the whole tree, built as a single static library.
