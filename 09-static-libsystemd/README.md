# 09. A libsystemd.a with Rust inside breaks the Rust programs that link it

A Rust program can't link a static library that contains a Rust static
library built by the same rustc. The link fails on the duplicate panic
handler `__rustc::rust_begin_unwind`, which the program's std defines as
well. A C program linking it together with any other Rust static library
fails the same way, see 08.

## Why it matters

We support a static libsystemd. `-Dstatic-libsystemd=true|pic|no-pic`
(meson_options.txt:45) installs libsystemd.a (meson.build:2127). With
Rust inside, programs that contain Rust themselves could no longer link
it. Building it isn't possible today anyway, see 10.

## Reproducer

    ./09-static-libsystemd/run.sh

This builds sd.rs into a libsystemd.a that only holds a Rust part and
links app.rs, an ordinary Rust program using std, against it:

    $ rustc +1.99.1 --edition 2021 -O 09-static-libsystemd/app.rs -L . -l static=systemd -o app
    error: linking with `cc` failed: exit status: 1
    [...]
      = note: rust-lld: error: duplicate symbol: __rustc::rust_begin_unwind
              >>> defined at sd.89926b25a36d323-cgu.0
              >>>            libsystemd.sd.89926b25a36d323-cgu.0.rcgu.o:(__rustc::rust_begin_unwind) in archive ./libsystemd.a
              >>> defined at panicking.rs:612 (library/std/src/panicking.rs:612)
              >>>            std-7e719de9c4abc98f.std.68c81ae915296b05-cgu.0.rcgu.o:(.text._RNvCs5fGHjzWXRav_7___rustc17rust_begin_unwind+0x0) in archive [...]/libstd-7e719de9c4abc98f.rlib

With the nightly option from 08, unlocked by `RUSTC_BOOTSTRAP=1`, the
same program links and runs:

    $ RUSTC_BOOTSTRAP=1 rustc +1.99.1 --edition 2021 -C panic=abort -O --crate-type staticlib -Zstaticlib-rename-internal-symbols 09-static-libsystemd/sd.rs -o libsystemd.a
    $ rustc +1.99.1 --edition 2021 -O 09-static-libsystemd/app.rs -L . -l static=systemd -o app && ./app
    8

## Upstream

The same as 08. The fix is the nightly-only
`-Zstaticlib-rename-internal-symbols` (rust-lang/rust#156950).
rust-lang/rust#104707 "Don't leak non-exported symbols from staticlibs"
is open.

## Workarounds

None on stable, other than dropping the static libsystemd.
