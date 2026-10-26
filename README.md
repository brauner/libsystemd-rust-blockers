# What keeps us from using Rust in libsystemd

Now that systemd allows writing leaf programs in Rust a few people have
asked what exactly keeps us from using Rust in libsystemd itself. So
this is the list I came up with. Each item comes with a reproducer that
proves or disproves it on your machine.

Please note that this is my take on it. Other systemd maintainers may
disagree.

"libsystemd" here means both libsystemd.so, our public library, and
libsystemd-shared, the private library all our programs link. The
context is our Rust policy in docs/CODING_STYLE.md:

- Rust is only used for new leaf programs.
- It's built with meson, there's no cargo.
- Only the `core` and `libc` crates are allowed, so all code is
  `#![no_std]`.
- Rust code talks to the rest of systemd through C linkage only.
- The MSRV is 1.85 because that's what Debian 13 ships.

## Rust-ABI shared libraries

| # | Problem | Result |
|---|---------|--------|
| 01 | A Rust-ABI shared library only works with the rustc that built it | E0786/E0514 |
| 02 | Generic code of a Rust shared library ends up in every program | `-Zshare-generics` is nightly |
| 03 | A Rust-ABI shared library can't be built with LTO on stable | `-Zdylib-lto` is nightly |
| 04 | A Rust-ABI shared library exports all of core, and two of them don't mix | 272 KB vs 4 KB, E0152 |
| 05 | A shared library linked by rustc can't have versioned symbols | rust-lld drops them, GNU ld fails |
| 06 | A C-ABI Rust shared library can't be used from Rust as a crate | E0786 |
| 07 | There's no Rust runtime library to share | rlib only, `libstd-<hash>.so` |

## Rust inside a C library

| # | Problem | Result |
|---|---------|--------|
| 08 | Two Rust static libraries can't be linked together | duplicate `__rustc::rust_begin_unwind` |
| 09 | A libsystemd.a with Rust inside breaks the Rust programs that link it | same as 08 |
| 10 | meson can't put Rust code into a C static library | meson error |
| 11 | A no_std static library needs an unstable lang item to link | undefined `rust_eh_personality` |
| 12 | A staticlib leaks core through libsystemd-shared's export-all version script | 545 exports, 277 KB vs 18 KB |
| 13 | The prebuilt core can't be rebuilt with our flags | `-Zbuild-std` is nightly |

## Language

| # | Problem | Result |
|---|---------|--------|
| 20 | No thread-local statics in no_std Rust on stable | E0658 |
| 21 | No C-variadic definitions at the 1.85 MSRV, and no `long double` on 1.99 | E0658 on 1.85, wrong fields on 1.99.1 |
| 22 | The `alloc` crate aborts on allocation failure, libsystemd returns `-ENOMEM` | SIGABRT instead of -12 |
| 23 | A panic in no_std Rust library code kills the process that called it | SIGABRT |
| 24 | A foreign unwind through a Rust frame skips Drop or aborts | UB or SIGABRT |
| 25 | `--gc-sections` drops `#[used]` section entries at our 1.85 MSRV | ld.lld drops the 1.85 entry |
| 26 | Stable Rust can't reference an optional (weak) symbol | E0658, link error |

## Running them

Each directory has a README.md and a run.sh that ends with a RESULT
line.

    ./run-all.sh            # everything, output in logs/
    ./run-all.sh 21         # one item
    ./run-all.sh 3          # every item starting with 3
    RUSTC="rustc +1.99.1" ./05-symbol-versions/run.sh

common.sh lists the variables (RUSTC, RUSTC_OLD, CARGO, CC, CXX, CLANG,
BINDGEN, GCCRS, GCCRS_B, SYSTEMD_SRC, RUST_SRC). Local settings go into
env.local next to it, which git ignores.

You need rustup with the 1.99.1 and 1.85.0 toolchains, gcc, binutils,
and checkouts of systemd and rust-lang/rust in SYSTEMD_SRC and RUST_SRC.
Some items need more:

- clang: 21, 34, 35
- ld.lld: 25, 35
- g++: 24
- jq and network access to qa.debian.org: 21
- meson: 10
- bindgen: 35, 36
- gccrs: 31

The logs in logs/ were recorded on 2026-10-26 with:

- rustc 1.99.1, the current stable, and 1.85.0 for our MSRV
- gcc 16.2, clang 21.1.8, meson 1.11.1, bindgen 0.72.1, gccrs 16.2
- Debian unstable on x86_64
- systemd main at e9795a90b7 and rust-lang/rust at 846e51f66b1

run-all.sh replaces local paths in the logs with the variable they come
from. Paths into this repository are relative, the per-run work
directory is $W and $HOME is ~.
