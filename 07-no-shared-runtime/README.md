# 07. There's no Rust runtime library to share

`core` and `alloc` only exist as static archives (`.rlib`). `std` also
ships a shared object, but its file name carries a hash per compiler
build. It's `libstd-7e719de9c4abc98f.so` for 1.99.1 and
`libstd-6273572f18644c87.so` for 1.85.0, and a program linked with
`-C prefer-dynamic` needs exactly that file.

A `staticlib` can't use the shared std on stable. `-C prefer-dynamic` is
ignored for it and `-Zstaticlib-prefer-dynamic` is a nightly option.

Debian ships `libstd-rust-1.96`, but the only reverse dependencies are
the toolchain itself.

## Why it matters

Every Rust artifact carries its own copy of the runtime parts it uses.
For `#![no_std]` code that's core and `compiler_builtins`, which is
small (about 4 KB per artifact, see 12). With std it was 1.18 MB per
stripped program, or 308 KB with LTO and `panic=abort`, measured in
2026-08. That's why our Rust is `#![no_std]` (docs/CODING_STYLE.md,
"## Rust").

## Reproducer

    ./07-no-shared-runtime/run.sh

This lists `core`, `alloc` and `std` in the sysroots of `$RUSTC` and
`$RUSTC_OLD`:

    $ ls ~/.rustup/toolchains/1.99.1-x86_64-unknown-linux-gnu/lib/rustlib/x86_64-unknown-linux-gnu/lib | grep -E '^lib(core|alloc|std)-'
    liballoc-3988244237fec6ee.rlib
    liballoc-3988244237fec6ee.rmeta
    libcore-1d288395a3394ed3.rlib
    libcore-1d288395a3394ed3.rmeta
    libstd-7e719de9c4abc98f.rlib
    libstd-7e719de9c4abc98f.rmeta
    libstd-7e719de9c4abc98f.so
    [exit status 0]

    $ ls ~/.rustup/toolchains/1.85.0-x86_64-unknown-linux-gnu/lib/rustlib/x86_64-unknown-linux-gnu/lib | grep -E '^lib(core|alloc|std)-'
    liballoc-715bc629a88bca60.rlib
    libcore-406129d0e3fbc101.rlib
    libstd-6273572f18644c87.rlib
    libstd-6273572f18644c87.so
    [exit status 0]

Then it builds hello.rs with `-C prefer-dynamic` using both compilers.
Each program needs the libstd of its own compiler:

    $ readelf -d hello hello-old | grep -E 'File:|NEEDED.*std'
    File: hello
     0x0000000000000001 (NEEDED)             Shared library: [libstd-7e719de9c4abc98f.so]
    File: hello-old
     0x0000000000000001 (NEEDED)             Shared library: [libstd-6273572f18644c87.so]
    [exit status 0]

For a `staticlib` rustc takes `-C prefer-dynamic` without complaint, and
the option it actually looks at is nightly:

    $ rustc +1.99.1 --edition 2021 --crate-type staticlib -C prefer-dynamic 07-no-shared-runtime/lib.rs -o libdyn.a
    [exit status 0]

    $ rustc +1.99.1 --edition 2021 --crate-type staticlib -Zstaticlib-prefer-dynamic 07-no-shared-runtime/lib.rs -o libdyn2.a
    error: the option `Z` is only accepted on the nightly compiler
    [...]
    [exit status 1]

The Debian part was checked by hand against unstable on 2026-10-26 and
isn't part of run.sh:

    $ apt-cache rdepends libstd-rust-1.96
    libstd-rust-1.96
    Reverse Depends:
      libstd-rust-dev
      rustfmt
      rust-clippy
      rust-analyzer

## Upstream

- compiler/rustc_metadata/src/dependency_format.rs:105-111 picks the
  linkage of a `staticlib`'s dependencies. It only looks at
  `-Zstaticlib-prefer-dynamic`, never at `-C prefer-dynamic`.
- `staticlib_prefer_dynamic` and `staticlib_allow_rdylib_deps` came from
  rust-lang/rust#106560 (merged 2023-05). They're still in the `-Z`
  block, compiler/rustc_session/src/options.rs:2921 and :2927.
- rust-lang/rust#111594, a "slim" staticlib without a copy of std, is
  open.
- rust-lang/rfcs#3993 "Support External Linkers" (opened 2026-08-04) is
  open. It would stabilize a version of the rlib format plus a "standard
  library bundle", so a C linker can link Rust code without rustc doing
  the final link.

## Workarounds

`#![no_std]`, which we already use. It still costs a small copy of core
per artifact.
