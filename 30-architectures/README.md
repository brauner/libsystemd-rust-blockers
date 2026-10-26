# 30. rustc can't build for alpha, hppa and sh4, and only experimentally for m68k

systemd builds for the architectures in src/basic/architecture.h. rustc
1.99.1 has no target at all for 9 of them, and the LLVM inside it has no
backend for them either. For 9 more it only has tier 3 targets, for
which the Rust project ships no `core`.

Of the 9 without a target, IA64, TILEGX and 31-bit S390 are gone from
the kernel. ARC and NIOS2 are alive, but only Buildroot builds systemd
for ARC, and nobody for NIOS2. The ones that matter are the
architectures distributions build systemd for today. alpha, hppa and sh4
have no rustc target and no LLVM backend. m68k has a tier 3 target and
an experimental LLVM backend, but rustc's `#[repr(C)]` layout of 64-bit
types there doesn't match the C ABI GCC uses.

## Why it matters

src/basic/architecture.h:13-45 has 33 architectures, plus x32 at line 65
(X86_64 with `__ILP32__`). The `#if` chain ends with
`#error "Please register your architecture here!"` (line 242), so we
build nowhere else. Four branches end with
`#error "Missing LIB_ARCH_TUPLE ..."` (lines 94, 101, 180 and 219, for
PPC_LE, PARISC64, SH64 and CRIS), so we don't build there either.

libsystemd is built wherever systemd is. With Rust inside, there would
be no libsystemd at all on alpha, hppa and sh4. As of 2026-10-26:

- In Debian sid, systemd 262.1-1 is "Installed" on all release
  architectures and on alpha, hppa, m68k, powerpc, ppc64, sh4, sparc64
  and x32
  (https://buildd.debian.org/status/package.php?p=systemd&suite=sid).
- In Debian sid, rustc 1.97.1+dfsg1-1 is "Installed" on all release
  architectures and on powerpc, ppc64, sparc64, x32 and hurd-amd64. It
  is "BD-Uninstallable" on alpha, hppa, m68k and sh4, with
  `rustc build-depends on missing: cargo:<arch> (>= 1.96.0+dfsg)`
  (https://buildd.debian.org/status/package.php?p=rustc&suite=sid).
- There is no rustc to build that cargo with either. The debian-ports
  pools return 404 for `pool-<arch>/main/r/rustc/` and
  `pool-<arch>/main/c/cargo/` on all four, while
  `pool-<arch>/main/s/systemd/` has 262.1-1, for example
  https://deb.debian.org/debian-ports/pool-m68k/main/s/systemd/.
- Gentoo (gentoo/gentoo a7e31ebf9a9e) has
  `KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~loong ~m68k ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86"`
  in sys-apps/systemd-262.1.ebuild:24. dev-lang/rust-1.99.0.ebuild:64
  lacks alpha, hppa, m68k and s390. dev-lang/rust-bin-1.99.0.ebuild:27
  lacks alpha, hppa and m68k.
- In Buildroot (1b9281e4a6b7), package/systemd/Config.in:1-14 enables
  systemd on arc, armeb, aarch64_be, m68k, mips*, sh4* and sparc. Its
  Rust support stops at tier 2 (package/rustc/Config.in.host:14-18 and
  107-113), so none of these get Rust.
- Every Debian release architecture has a tier 1 or 2 target, and so do
  all 9 Alpine architectures (rust 1.99.1-r0 in edge/main,
  https://pkgs.alpinelinux.org/packages?name=rust&branch=edge).

The kernel side, as of Linux master 21a7f44fd076 (2026-10-24, the 7.4
merge window):

| systemd | kernel |
|---------|--------|
| ALPHA, ARC, ARC_BE, M68K, MIPS*, NIOS2, PARISC, SH, SPARC | supported (alpha is "Odd Fixes" in MAINTAINERS) |
| PARISC64 | 64-bit kernels only, the userland is 32-bit |
| RISCV32 | `ARCH_RV32I` depends on `NONPORTABLE` |
| ARM_BE | deprecated in v7.3 (fe91e4e9da70) |
| ARM64_BE | `BROKEN` since v6.18 (1cf89b6bf660), removed for 7.4 (134b0fbc5c24) |
| IA64 | removed in v6.7 (cf8e8658100d) |
| SH64 | removed in v5.8 (37744feebc08) |
| CRIS, TILEGX | removed in v4.17 (c690eddc2f3b, bb9d812643d8) |
| S390 (31-bit) | kernel removed in v4.1 (5a79859ae0f3), compat in v6.19 (8e0b986c59c6) |
| PPC_LE | no such kernel, `CPU_LITTLE_ENDIAN` depends on `PPC_BOOK3S_64` |

## Reproducer

    ./30-architectures/run.sh

It reads the enum from architecture.h and maps each architecture to the
rustc Linux targets for that CPU. For each one it picks the best of the
N targets and shows:

- TIER and MD-LINE, its tier and line in platform-support.md, "h"
  meaning with host tools.
- 1.99, the tier in the target's own metadata in 1.99.1.
- LLVM, whether the LLVM in `$RUSTC` can create a target machine for it.
- RUST-STD, whether rustup ships rust-std for it, going by the
  toolchain's channel manifest.

Where architecture.h has a `LIB_ARCH_TUPLE` `#error`, the verdict says
that systemd doesn't build there either:

    # rustc 1.99.1 (58cf8f9c3 2026-10-13)
    [...]
    $ git -C $SYSTEMD_SRC log -1 --format='systemd %h %cs' && git -C $RUST_SRC log -1 --format='rust %h %cs'
    systemd e9795a90b7 2026-10-25
    rust 846e51f66b1 2026-10-26
    [...]
    $ grep -n 'error "Missing LIB_ARCH_TUPLE' $SYSTEMD_SRC/src/basic/architecture.h
    94:#    error "Missing LIB_ARCH_TUPLE for PPCLE"
    101:#  error "Missing LIB_ARCH_TUPLE for HPPA64"
    180:#  error "Missing LIB_ARCH_TUPLE for SH64"
    219:#  error "Missing LIB_ARCH_TUPLE for CRIS"

    ARCH         BEST RUSTC TARGET (of N)             TIER MD-LINE 1.99 LLVM  RUST-STD -> VERDICT
    ALPHA        -                                    -    -       -    -     - -> MISSING
    ARC          -                                    -    -       -    -     - -> MISSING
    ARC_BE       -                                    -    -       -    -     - -> MISSING
    ARM          arm-unknown-linux-gnueabi (17)       2h   98      2    yes   yes -> OK
    ARM64        aarch64-unknown-linux-gnu (5)        1h   45      1    yes   yes -> OK
    ARM64_BE     aarch64_be-unknown-linux-gnu (3)     3    298     3    yes   no -> TIER3
    ARM_BE       armeb-unknown-linux-gnueabi (1)      3    308     3    yes   no -> TIER3
    CRIS         -                                    -    -       -    -     - -> MISSING, no systemd build either
    IA64         -                                    -    -       -    -     - -> MISSING
    LOONGARCH64  loongarch64-unknown-linux-gnu (3)    2h   102     2    yes   yes -> OK
    M68K         m68k-unknown-linux-gnu (1)           3    360     3    yes   no -> TIER3
    MIPS         mips-unknown-linux-gnu (4)           3    362     3    yes   no -> TIER3
    MIPS64       mips64-unknown-linux-gnuabi64 (3)    3    366     3    yes   no -> TIER3
    MIPS64_LE    mips64el-unknown-linux-gnuabi64 (3)  3    368     3    yes   no -> TIER3
    MIPS_LE      mipsel-unknown-linux-gnu (4)         3    372     3    yes   no -> TIER3
    NIOS2        -                                    -    -       -    -     - -> MISSING
    PARISC       -                                    -    -       -    -     - -> MISSING
    PARISC64     -                                    -    -       -    -     - -> MISSING, no systemd build either
    PPC          powerpc-unknown-linux-gnu (4)        2h   104     2    yes   yes -> OK
    PPC64        powerpc64-unknown-linux-gnu (3)      2h   105     2    yes   yes -> OK
    PPC64_LE     powerpc64le-unknown-linux-gnu (2)    2h   107     2    yes   yes -> OK
    PPC_LE       -                                    -    -       -    -     - -> MISSING, no systemd build either
    RISCV32      riscv32gc-unknown-linux-gnu (2)      3    404     3    yes   no -> TIER3
    RISCV64      riscv64gc-unknown-linux-gnu (3)      2h   109     2    yes   yes -> OK
    S390         -                                    -    -       -    -     - -> MISSING
    S390X        s390x-unknown-linux-gnu (2)          2h   111     2    yes   yes -> OK
    SH           -                                    -    -       -    -     - -> MISSING
    SH64         -                                    -    -       -    -     - -> MISSING, no systemd build either
    SPARC        sparc-unknown-linux-gnu (1)          3    430     3    yes   no -> TIER3
    SPARC64      sparc64-unknown-linux-gnu (1)        2    207     2    yes   yes -> OK
    TILEGX       -                                    -    -       -    -     - -> MISSING
    X86          i686-unknown-linux-gnu (4)           1h   46      1    yes   yes -> OK
    X86_64       x86_64-unknown-linux-gnu (7)         1h   49      1    yes   yes -> OK
    X32          x86_64-unknown-linux-gnux32 (1)      2    233     2    yes   yes -> OK

The missing CPUs have no rustc target for any other OS either:

    $ grep -E '^(alpha|hppa|parisc|sh[0-9]?-|ia64|nios2|cris|tile|arc)' targets || echo 'no target for alpha, hppa/parisc, sh, ia64, nios2, cris, tile or arc'
    no target for alpha, hppa/parisc, sh, ia64, nios2, cris, tile or arc

To ask the LLVM inside rustc about those CPUs it uses custom target
specs, with m68k as the control. Custom targets need
`-Zunstable-options`, so this uses `RUSTC_BOOTSTRAP=1`:

    $ rustc +1.99.1 --target ./base.json --print target-cpus 2>&1 | head -1
    error: error loading target specification: custom targets are unstable and require `-Zunstable-options`

    $ RUSTC_BOOTSTRAP=1 rustc +1.99.1 -Z unstable-options --target ./alpha.json --print target-cpus 2>&1 | head -1
    error: failed to parse target machine config to target machine: could not create LLVM TargetMachine for triple: alpha-unknown-linux-gnu

hppa, sh4, ia64, nios2, arc, s390 and tilegx fail the same way. Only
m68k prints its CPUs:

    $ RUSTC_BOOTSTRAP=1 rustc +1.99.1 -Z unstable-options --target ./m68k.json --print target-cpus 2>&1 | head -1
    Available CPUs for this target:

Stable rustc has no `core` for m68k and can't build one. With
`RUSTC_BOOTSTRAP=1` it builds core from the 1.99.1 sources:

    $ rustc +1.99.1 --edition 2021 --crate-type rlib --target m68k-unknown-linux-gnu lib.rs 2>&1 | head -3
    error[E0463]: can't find crate for `core`
      |
      = note: the `m68k-unknown-linux-gnu` target may not be installed

    $ rustc +1.99.1 --edition 2024 --crate-type rlib --crate-name core --target m68k-unknown-linux-gnu -O -Cpanic=abort library/core/src/lib.rs -o libcore.rlib 2>&1 | grep -m1 E0554
    error[E0554]: `#![feature]` may not be used on the stable release channel

    $ RUSTC_BOOTSTRAP=1 rustc +1.99.1 --edition 2024 --crate-type rlib --crate-name core --target m68k-unknown-linux-gnu -O -Cpanic=abort library/core/src/lib.rs -o libcore.rlib && ls libcore.rlib
    libcore.rlib

With that core, layout.rs gets rustc to print the alignment of `u64` and
`f64` and the size of `#[repr(C)]` `struct { u8, u64 }` and
`struct { u8, f64 }` on m68k:

    $ RUSTC_BOOTSTRAP=1 rustc +1.99.1 --edition 2021 --crate-type rlib --target m68k-unknown-linux-gnu --extern core=libcore.rlib --emit=metadata layout.rs 2>&1 | grep -E '^[0-9]+ \| const|found one with' | sed 's/^ *|  *-* *\^* //'
    4 | const _: [(); 0] = [(); core::mem::align_of::<u64>()];
    expected an array with a size of 0, found one with a size of 4
    5 | const _: [(); 0] = [(); core::mem::align_of::<f64>()];
    expected an array with a size of 0, found one with a size of 8
    6 | const _: [(); 0] = [(); core::mem::size_of::<S>()];
    expected an array with a size of 0, found one with a size of 12
    7 | const _: [(); 0] = [(); core::mem::size_of::<D>()];
    expected an array with a size of 0, found one with a size of 16

    MISSING: ALPHA ARC ARC_BE IA64 NIOS2 PARISC S390 SH TILEGX
    MISSING, systemd does not build there either: CRIS PARISC64 PPC_LE SH64
    TIER3: ARM64_BE ARM_BE M68K MIPS MIPS64 MIPS64_LE MIPS_LE RISCV32 SPARC
    OK: ARM ARM64 LOONGARCH64 PPC PPC64 PPC64_LE RISCV64 S390X SPARC64 X86 X86_64 X32

    RESULT: REPRODUCED: 9 architectures systemd builds on have no rustc target (ALPHA,ARC,ARC_BE,IA64,NIOS2,PARISC,S390,SH,TILEGX), 9 only tier 3 ones

The C side of the m68k check isn't in run.sh because it needs an m68k
cross compiler. With Debian's (cpp-16-m68k-linux-gnu,
gcc-16-m68k-linux-gnu 16.2.0-3cross1) and layout.c from this directory:

    $ m68k-linux-gnu-gcc-16 -S -O2 -o - layout.c | grep -A1 -E '^(a64|af|sS|sD):'
    sD:
            .long   10
    --
    sS:
            .long   10
    --
    af:
            .long   2
    --
    a64:
            .long   2

So on m68k, `#[repr(C)] struct { u8, u64 }` is 12 bytes in Rust and 10
in C, and the field offsets differ. GCC's manual documents the 16-bit
alignment of `long long` and `double` as the m68k ABI (`-mno-align-int`,
https://gcc.gnu.org/onlinedocs/gcc/M680x0-Options.html). libsystemd's
public types contain 64-bit fields, e.g. `sd_id128_t`
(`uint64_t qwords[2]`).

## Upstream

The tiers are from src/doc/rustc/src/platform-support.md, with tier 1 at
lines 24-64, tier 2 at 65-243 and tier 3 from line 244. The metadata in
1.99.1 agrees for every row.

LLVM has no backend for alpha, PA-RISC, SuperH, IA-64, Nios II, CRIS or
TILE, and its SystemZ backend is for 64-bit s390x only (the probe for
31-bit s390 fails). The full list in llvm/lib/Target is AArch64 AMDGPU
ARC ARM AVR BPF CSKY DirectX Hexagon Lanai LoongArch M68k MSP430 Mips
NVPTX PowerPC RISCV SPIRV Sparc SystemZ VE WebAssembly X86 XCore Xtensa.
It's the same in rust-lang/llvm-project f738f3b0ed65 (the
src/llvm-project submodule at 846e51f66b1) and in llvm/llvm-project main
7f43d3dacc14 (2026-10-26). ARC, CSKY, DirectX, M68k and Xtensa are
experimental (llvm/CMakeLists.txt:629-635). rustc's LLVM is built with
M68k, CSKY, AVR and Xtensa, but not ARC
(src/bootstrap/src/core/build_steps/llvm.rs:483-491).

rustc doesn't know these CPUs either. `enum Arch`
(compiler/rustc_target/src/spec/mod.rs:1763-1795) has no alpha, hppa,
sh, ia64, nios2 or arc. The C ABI lowering for an unknown arch is
`panic!("no lowering implemented for {arch}")`
(compiler/rustc_target/src/callconv/mod.rs:778-779). That matters for
any non-LLVM backend too, see 31.

For m68k, the target's page
src/doc/rustc/src/platform-support/m68k-unknown-linux-gnu.md still says
"core and std are currently missing" (:69-71) and "native builds, which
are currently untested" (:48). That's out of date, the reproducer builds
core. The data layout
(compiler/rustc_target/src/spec/targets/m68k_unknown_linux_gnu.rs:19)
has no entries for i64 and f64, so LLVM's defaults (4 and 8) apply. The
rustc_codegen_gcc maintainer pointed this out on 2025-12-20 in
rust-lang/rustc_codegen_gcc#744. It's unchanged at 846e51f66b1.
rust-lang/rust#117252 "Wrong alignment for m68k pointer types" has been
open since 2023-10-26, and #143024 "Crash when compiling to m68k" is
open too.

## Workarounds

For alpha, hppa and sh4 there's none with rustc. The GCC based compilers
are the only way, and neither is usable today (31).

For m68k we'd have to build core with `RUSTC_BOOTSTRAP=1`, i.e. use the
stable compiler as a nightly one, get the data layout fixed upstream,
and have Debian bootstrap rustc and cargo for the port, which has never
been done.

The other tier 3 targets (mips*, sparc, riscv32, armeb, aarch64_be) need
a distribution to build rustc for them itself, without upstream CI.
Gentoo does for mips (`~mips` on dev-lang/rust). Debian no longer builds
systemd for any of them.

Or we keep a C implementation of everything in libsystemd for these
architectures, i.e. maintain it twice.
