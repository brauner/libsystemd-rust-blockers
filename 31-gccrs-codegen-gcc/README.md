# 31. The GCC based Rust compilers can't fill the gap yet

GCC supports alpha, hppa, m68k and sh4, so a GCC based Rust compiler
would close the gap from 30. Neither of the two is usable today.

gccrs 16.2, the Rust front end in GCC 16, refuses to compile anything
unless passed `-frust-incomplete-and-experimental-compiler-do-not-use`.
With that flag it has no `core`, and it can't compile one. The core of
Rust 1.49.0, which is what gccrs aims for, gets through macro expansion
and then fails with 337 errors, 1935 at the end, without producing an
object.

rustc_codegen_gcc, the libgccjit backend for rustc, is "WIP" and needs a
patched libgccjit. Stable rustc can't load it and nightly ships it for
x86_64 Linux only. It can also only target CPUs rustc knows, and rustc
has no alpha, hppa or sh and no C ABI for CPUs it doesn't know.

## Why it matters

For alpha, hppa and sh4 there is no LLVM backend (30). A GCC based
compiler is the only way to get Rust into libsystemd there.

Even a working gccrs would be aimed at the wrong language version. Its
milestones are all for Rust 1.49 (December 2020). Our Rust code is
edition 2021 (meson.build:8) with an MSRV of 1.85 (meson.build:380), and
it uses things that came after 1.49:

- `core::ffi::CStr` and `c_char`, stable since 1.64
  (src/rust/systemd-shared/cstr.rs:5).
- `c"..."` literals, stable since 1.77
  (src/rust/systemd-shared/errno.rs:22).

## Reproducer

    ./31-gccrs-codegen-gcc/run.sh

For gccrs it compiles a trivial `#![no_std]` crate without and with the
flag. gccrs quotes names with Unicode quotes, they are ASCII here:

    $ $GCCRS -B$GCCRS_B --version | head -1
    x86_64-linux-gnu-gccrs-16 (Debian 16.2.0-3) 16.2.0
    $ $GCCRS -B$GCCRS_B -c lib.rs -o lib.o 2>&1 | head -1
    crab1: fatal error: gccrs is not yet able to compile Rust code properly. Most of the errors produced will be the fault of gccrs and not the crate you are trying to compile. [...]
    $ $GCCRS -B$GCCRS_B -frust-incomplete-and-experimental-compiler-do-not-use -c lib.rs -o lib.o 2>&1 | head -4
    crab1: error: failed to locate crate 'core'
    crab1: error: unknown crate 'core'
    crab1: error: unknown crate 'core'
    lib.rs:2:35: error: Cannot find path 'core::cmp::max' in this scope [E0433]

nocore.rs uses nothing from core and still needs it:

    $ $GCCRS -B$GCCRS_B -frust-incomplete-and-experimental-compiler-do-not-use -c nocore.rs -o nocore.o 2>&1 | head -2
    crab1: error: failed to locate crate 'core'
    crab1: error: unknown crate 'core'

Then it archives library/core at tag 1.49.0 from `$RUST_SRC`. The
stdarch submodule isn't in the checkout, so an empty `core::arch` stands
in for it. It runs gccrs on that core up to each pipeline stage in turn.
The first two are clean:

    $ $GCCRS -B$GCCRS_B -frust-incomplete-and-experimental-compiler-do-not-use -frust-edition=2018 -frust-crate=core -frust-compile-until=attributecheck -w -c lib.rs -o core.o 2>&1 | count
    0 errors
    $ [...] -frust-compile-until=expansion -w -c lib.rs -o core.o 2>&1 | count
    0 errors
    $ [...] -frust-compile-until=astvalidation -w -c lib.rs -o core.o 2>&1 | count
    337 errors
    $ [...] -frust-compile-until=typecheck -w -c lib.rs -o core.o 2>&1 | count
    1935 errors

The most frequent errors at astvalidation:

    $ [...] -frust-compile-until=astvalidation -w -c lib.rs -o core.o 2>&1 | grep 'error:' | sed 's/:[0-9]*:[0-9]*: error:/: error:/' | sort | uniq -c | sort -rn | head -5
         16 ./num/flt2dec/mod.rs: error: could not resolve macro invocation 'assert' [E0433]
         11 ./num/flt2dec/strategy/grisu.rs: error: could not resolve macro invocation 'assert' [E0433]
         11 ./num/flt2dec/strategy/dragon.rs: error: could not resolve macro invocation 'assert' [E0433]
          3 ./num/flt2dec/mod.rs: error: could not resolve trait 'Clone'
          3 ./num/error.rs: error: could not resolve trait 'PartialEq'

A full build also ends with 1935 errors and produces no object:

    $ [...] -frust-crate=core -w -c lib.rs -o core.o 2>&1 | count; ls core.o
    1935 errors
    ls: cannot access 'core.o': No such file or directory
    [exit status 2]

Without the stub, using the real stdarch at 3c3664355ef4 (the 1.49.0
submodule commit, tree-identical to the copy in GCC 16.2), gccrs gives
339 errors at astvalidation and 9640 in a full build. That was checked
by hand and isn't part of run.sh.

For rustc_codegen_gcc it tries `-Zcodegen-backend=gcc` on stable, counts
the gcc components the stable channel manifest marks as available, and
greps the rust tree for the backend's status:

    $ rustc +1.99.1 -Zcodegen-backend=gcc --crate-type lib lib.rs 2>&1 | head -1
    error: the option `Z` is only accepted on the nightly compiler
    $ awk [...] ~/.rustup/toolchains/1.99.1-x86_64-unknown-linux-gnu/lib/rustlib/multirust-channel-manifest.toml
    68 target entries, 0 available
    $ ls $RUST_SRC/compiler/rustc_codegen_gcc/target_specs
    m68k-unknown-linux-gnu.json
    $ sed -n '/pub enum Arch {/,/^    }/p' $RUST_SRC/compiler/rustc_target/src/spec/mod.rs | grep -o '"[a-z0-9_]*"' | paste -s -d ' '
    "aarch64" "amdgpu" "arm" "arm64ec" "avr" "bpf" "csky" "hexagon" "loongarch32" "loongarch64" "m68k" "mips" "mips32r6" "mips64" "mips64r6" "msp430" "nvptx64" "powerpc" "powerpc64" "riscv32" "riscv64" "s390x" "sparc" "sparc64" "spirv" "wasm32" "wasm64" "x86" "x86_64" "xtensa"
    $ grep -n -B1 'no lowering implemented' $RUST_SRC/compiler/rustc_target/src/callconv/mod.rs
    778-            arch @ (Arch::SpirV | Arch::Other(_)) => {
    779:                panic!("no lowering implemented for {arch}")

    RESULT: REPRODUCED: gccrs cannot compile core 1.49.0, rustc_codegen_gcc is nightly and x86_64 only, and rustc has no C ABI for alpha, hppa or sh

## Upstream

The gccrs side was checked on 2026-10-26. GCC 16 vendors core and
stdarch from Rust 1.49.0 (libgrust/rustc-lib/version-info at gcc-16.2.0
has `LIBCORE_TAG=1.49.0`). The core/src tree there (8ae3b7abcb70) is
identical to rust 1.49.0's. GCC 16's testsuite compiles that core only
up to attributecheck, the stage right after parsing
(gcc/testsuite/rust/core/core.exp:33 at releases/gcc-16.2.0 has
`-frust-compile-until=attributecheck`). On gccrs master it has moved to
`-frust-compile-until=typecheck` with Rust-GCC/gccrs#4932 "core: Test
until typecheck", merged 2026-09-22.

The GCC 16 release notes have no Rust section at all
(https://gcc.gnu.org/gcc-16/changes.html). GCC 15's said the parser
handles all of core, alloc and std, and that macro expansion handles all
of core 1.49 (https://gcc.gnu.org/gcc-15/changes.html#rust).

The June 2026 report (published 2026-07-08, its text repeated in the
July report) said gccrs was "still progressing towards our objective of
being able to compile the Linux kernel in time for RustConf in
September"
(https://rust-gcc.github.io/2026/07/08/2026-06-monthly-report.html).
Note that this is about the kernel, not about core. The latest report is
for August 2026, published 2026-09-08
(https://rust-gcc.github.io/2026/09/08/2026-08-monthly-report.html). Its
"Typechecking fixes core 1.49" milestone was at 60%, and it said "The
next steps for compiling core are finishing debugging our type-system,
and then proceeding to our code generation pass. Once this is done, the
compiler will be able to compile core. This should happen in the next
few weeks or months". There is no later report. The newest weekly report
in Rust-GCC/Reporting is 2026-07-27.

In GCC 16 and on gccrs master, only x86 defines `cfg(target_arch)`
(gcc/config/i386/i386-rust-and-jit.inc:2-4). There are no Rust target
hooks for alpha, pa, sh or m68k. Debian builds no gccrs for the ports
either. The debian-ports pools for alpha, hppa, m68k and sh4 have gcc-16
16.2.0-3/-4 with gnat, ga68 and libgccjit16, but no gccrs-16.

For rustc_codegen_gcc, in rust-lang/rust 846e51f66b1,
compiler/rustc_codegen_gcc/Readme.md says:

- :1 "# WIP libgccjit codegen backend for rust"
- :12 "The primary goal of this project is to be able to compile Rust
  code on platforms unsupported by LLVM."
- :17-18 "This requires a patched libgccjit in order to work. You need
  to use my fork of gcc"
- :44 "expect ~100 failing UI tests"

compiler/rustc_codegen_gcc/rust-toolchain.toml pins
`nightly-2026-10-19`. Selecting a backend is `-Zcodegen-backend`, an
unstable option (compiler/rustc_session/src/options.rs:2379-2380, 2446).

src/bootstrap/src/core/build_steps/dist.rs keeps the backend out of
stable and beta at :1759-1761, "It is not yet stable and should not be
included.", and skips every target other than x86_64-unknown-linux-gnu
at :1767-1771. :3228-3233 and :3237-3240 do the same for the libgccjit
component. The nightly manifest of 2026-10-26
(https://static.rust-lang.org/dist/channel-rust-nightly.toml) has
`rustc-codegen-gcc-preview` and `gcc-x86_64-unknown-linux-gnu-preview`
for the x86_64-unknown-linux-gnu host only. There is no libgccjit for
any other target.

For a target rustc doesn't have, doc/tips.md:76 says to write a target
spec "(note that the `arch` specified in this file must be supported by
the rust compiler)". That isn't the case for alpha, hppa or sh.
`enum Arch` (compiler/rustc_target/src/spec/mod.rs:1763-1795) doesn't
have them. The C ABI for an unknown arch is a panic
(compiler/rustc_target/src/callconv/mod.rs:778-779), and every non-Rust
ABI goes through it (compiler/rustc_ty_utils/src/abi.rs:635-639). Plus,
custom target specs need `-Zunstable-options` anyway (30).

target_specs/ only has m68k-unknown-linux-gnu.json. The m68k CI
(.github/workflows/m68k.yml:27-33) runs `--std-tests`. The libcore and
rustc test runs are commented out with "FIXME(antoyo): fix those on
m68k." The cross libgccjit builds the CI uses
(cross-cg-gcc-tools/cross-gcc, release master-90.5, 2026-10-20) exist
for aarch64, arm and m68k only.

These rustc_codegen_gcc issues are all open:

- rust-lang/rustc_codegen_gcc#742 "DEC Alpha support" still has "Add
  handling of the Alpha ABI to the Rust compiler" unchecked. On
  2026-02-18 the maintainer wrote that "it might take a couple of months
  before I get back to this".
- rust-lang/rustc_codegen_gcc#744 "Building Rustc on m68k". As of
  2025-11-10 the rustc it built for m68k "fails to even compile the
  simplest program".
- rust-lang/rustc_codegen_gcc#558, which asks for a SuperH backend, with
  no target.

## Workarounds

None today. gccrs needs code generation for core, and the language up to
our MSRV 1.85, not 1.49. rustc_codegen_gcc needs rustc support for
alpha, hppa and sh (target specs and C ABI lowering), stable
distribution of the backend, and a libgccjit for each target.
Distributions would then build Rust code with a second compiler backend
that only runs its std tests on one of those architectures today.
