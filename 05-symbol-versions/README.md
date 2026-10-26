# 05. A shared library linked by rustc can't have versioned symbols

For every `dylib` and `cdylib` rustc writes its own anonymous version
script, `{ global: ...; local: *; };`, and passes it to the linker.
There's no option to replace it or to name the version node. If we add
named version nodes like libsystemd's on top:

- rust-lld, rustc's default linker on x86_64 Linux, warns and drops the
  versions.
- GNU ld refuses to link.

## Why it matters

libsystemd.so's ABI consists of named version nodes. There are 44 of
them in src/libsystemd/libsystemd.sym, from `LIBSYSTEMD_209` to
`LIBSYSTEMD_263`. Every program linked against it records
`sd_*@LIBSYSTEMD_nnn`. So libsystemd.so has to keep being linked by the
C toolchain (meson.build:2108 `libsystemd = shared_library(`, with
`-Wl,--version-script=`).

## Reproducer

    ./05-symbol-versions/run.sh

This builds the same two exports in C (sd.c) and in Rust as a `cdylib`
(sd.rs), both with demo.sym, which is shaped like libsystemd.sym. The C
library gets its versions:

    $ nm -D --defined-only libc.so
    0000000000000000 A LIBDEMO_209
    0000000000000000 A LIBDEMO_210
    0000000000001110 T sd_demo_close@@LIBDEMO_210
    0000000000001100 T sd_demo_open@@LIBDEMO_209
    [exit status 0]

rust-lld warns and links the Rust library without them:

    $ rustc +1.99.1 ... --crate-type cdylib 05-symbol-versions/sd.rs -C link-arg=-Wl,--version-script=05-symbol-versions/demo.sym -o librust-lld.so
    warning: linker stderr: rust-lld: attempt to reassign symbol 'sd_demo_open' of VER_NDX_GLOBAL to version 'LIBDEMO_209'
             rust-lld: attempt to reassign symbol 'sd_demo_close' of VER_NDX_GLOBAL to version 'LIBDEMO_210'
    [...]
    [exit status 0]

    $ nm -D --defined-only librust-lld.so
    0000000000001680 T sd_demo_close
    0000000000001688 T sd_demo_open
    [exit status 0]

The same build with GNU ld, `-C linker-features=-lld`, shows that rustc
passes its own version script first and ours last. GNU ld refuses the
combination:

    $ rustc +1.99.1 ... -C linker-features=-lld -o librust-bfd.so
    error: linking with `cc` failed: exit status: 1
      |
      = note:  "cc" "-Wl,--version-script=$W/rustcvC1czt/list" "-Wl,--no-undefined-version" [...] "-Wl,--version-script=05-symbol-versions/demo.sym"
      = note: some arguments are omitted. use `--verbose` to show all linker arguments
      = note: /usr/bin/x86_64-linux-gnu-ld.bfd: anonymous version tag cannot be combined with other version tags
              /usr/bin/x86_64-linux-gnu-ld.bfd: unable to find version dependency `LIBDEMO_209'
              /usr/bin/x86_64-linux-gnu-ld.bfd: anonymous version tag cannot be combined with other version tags
              collect2: error: ld returned 1 exit status
    [...]
    [exit status 1]

## Upstream

rustc writes the version script in
compiler/rustc_codegen_ssa/src/back/linker.rs:866-889 for every target
with `limit_rdylib_exports` set, which includes Linux (the check is at
:806). rust-lang/rust#22399 (versioned libraries) was closed as not
planned on 2025-03-01, pending an RFC.

## Workarounds

Link libsystemd.so with the C toolchain and put the Rust code in as a
`staticlib`, which is the only way it can get in. 08-12 list what that
costs.
