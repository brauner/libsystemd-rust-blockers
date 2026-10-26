# 01. A Rust-ABI shared library only works with the rustc that built it

A shared library with a Rust API, crate type `dylib`, can only be used
by programs that are built with exactly the same rustc. Any other
compiler, older or newer, refuses it.

## Why it matters

libsystemd.so is our public library and its ABI is stable. There are 44
version nodes in src/libsystemd/libsystemd.sym, from `LIBSYSTEMD_209` to
`LIBSYSTEMD_263`. The programs linking it are built by other projects,
at other times and with other compilers. So whatever we write in Rust
inside of libsystemd, the interface it offers has to stay C.

For libsystemd-shared, our private library, being tied to one rustc
would be tolerable since we rebuild it together with every program using
it anyway. 02-07 cover what else a Rust-ABI shared library costs.

## Reproducer

    ./01-dylib-rustc-lock/run.sh

This builds sdshared.rs as a `dylib` with `$RUSTC` (1.99.1) and with
`$RUSTC_OLD` (1.85.0) and then builds user.rs against each library with
the other compiler:

    1.99.1 library, 1.99.1 program:  links and runs ([exit status 5])
    1.99.1 library, 1.85.0 program:  error[E0786]: found invalid metadata files for crate `sdshared`
    1.85.0 library, 1.99.1 program:  error[E0786]: found invalid metadata files for crate `sdshared`

With 1.97.1 against the 1.99.1 library the error is E0514 instead. That
one was checked by hand and isn't part of run.sh:

    error[E0514]: found crate `sdshared` compiled by an incompatible version of rustc
      = note: the following crate versions were found:
              crate `sdshared` compiled by rustc 1.99.1 (58cf8f9c3 2026-10-13): .../libsdshared.so

## Upstream

There's no stable Rust ABI. crABI, rust-lang/rfcs#3470, was opened on
2023-08-11 and is still open. rust-lang/rust#22399 "rustc need a way to
generate versioned libraries" was closed as not planned on 2025-03-01
with "this *definitely* needs an RFC".

## Workarounds

None for libsystemd.so. Its Rust users keep binding the C API like they
do today.
