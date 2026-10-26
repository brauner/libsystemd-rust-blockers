# 13. The prebuilt core can't be rebuilt with our flags

Every Rust artifact links the core that the Rust project prebuilt and
ships in the sysroot. It's built with `panic=unwind` and without any of
the hardening or instrumentation flags that we or a distribution use for
C code. On stable there's no way to rebuild it:

- cargo's `-Zbuild-std` is nightly.
- meson has no equivalent.
- The accepted build-std RFCs cover cargo only. They note that other
  build systems need `RUSTC_BOOTSTRAP` to build an unmodified standard
  library.

## Why it matters

Whatever flags we build libsystemd with, its Rust part pulls in a core
that doesn't have them. This is the common root of several other items:

- 11, the unwinding personality
- 33, no CET marking
- 34, no MSan instrumentation

## Reproducer

    ./13-prebuilt-core/run.sh

This unpacks the libcore rlib from the sysroot of `$RUSTC`. It holds a
single object file:

    $ ls core
    core-1d288395a3394ed3.core.efd5e57aef94d71e-cgu.0.rcgu.o
    lib.rmeta
    lib.rmeta-link

That object was built with `panic=unwind`, so it has a landing pad (see
11). It was built without `-Zcf-protection`, so it has no x86 IBT/SHSTK
property note (see 33):

    $ readelf -S -W core/*.o | grep -c gcc_except_table
    1

    $ readelf -n core/*.o | grep -E 'x86 feature' || echo 'no x86 feature property'
    no x86 feature property

rustc says it itself when a `#![no_std]` crate asks for unwinding:

    $ rustc +1.99.1 --edition 2021 --crate-type staticlib -C panic=unwind 13-prebuilt-core/lib.rs -o x.a
    error: unwinding panics are not supported without std
      |
      = help: using nightly cargo, use -Zbuild-std with panic="abort" to avoid unwinding
      = note: since the core library is usually precompiled with panic="unwind", rebuilding your crate with panic="abort" may not be enough to fix the problem

Last, it wraps lib.rs into a cargo crate and asks stable cargo to
rebuild core:

    $ (cd crate && cargo +1.99.1 build --offline -Zbuild-std=core 2>&1 | head -2)
    error: the `-Z` flag is only accepted on the nightly channel of Cargo, but this is the `stable` channel
    See https://doc.rust-lang.org/book/appendix-07-nightly-rust.html for more information about Rust release channels.

## Upstream

The build-std RFCs were merged between December 2025 and May 2026, but
none of them is implemented on stable:

- rust-lang/rfcs#3873 "build-std: context", merged 2025-12-31
- rust-lang/rfcs#3874 "build-std: always", merged 2026-04-15
- rust-lang/rfcs#3875 "build-std: explicit dependencies", merged
  2026-05-04

RFC #3874 says "the standard library's build will respect the
`RUSTFLAGS` environment variable". It also says rustc assuming
`RUSTC_BOOTSTRAP` for sysroot builds "is a shared requirement with other
build systems that wish to build an unmodified standard library".

The rust 1.95.0 release notes (RELEASES.md:581) still describe the
standard library as one "which has no stable build mechanism".

## Workarounds

None on stable. The Linux kernel builds its own core from rust-src in
rust/Makefile. To do that it compiles the whole kernel with
`export RUSTC_BOOTSTRAP := 1` (Makefile:641 in v7.3). IOW, it runs the
stable compiler as a nightly one. We could do the same and give up on
stable Rust.
