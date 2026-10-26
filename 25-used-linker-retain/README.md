# 25. `--gc-sections` drops `#[used]` section entries at our 1.85 MSRV

We register entries in named sections and walk them through
`__start_`/`__stop_`. In C we mark them `retain` (SHF_GNU_RETAIN) so
that `-Wl,--gc-sections` keeps them. rustc 1.85, our MSRV, emits
`#[used]` statics without that flag. ld.lld, which defaults to
`-z start-stop-gc`, then drops the entry silently, and so does ld.bfd
with `-z start-stop-gc`. The explicit Rust form, `#[used(linker)]`, is
unstable.

Since Rust 1.89 a plain `#[used]` is `#[used(linker)]` on ELF and the
section gets the R flag, like our C entries. With rustc 1.99.1 neither
ld.bfd nor ld.lld drops the Rust entry. So this only bites as long as
our MSRV is older than 1.89.

## Why it matters

libsystemd collects sd-bus error maps from a named section.
`BUS_ERROR_MAP_ELF_REGISTER` (src/libsystemd/sd-bus/bus-error.h:37-42)
is `_section_("SYSTEMD_BUS_ERROR_MAP") _used_ _retain_`, and the maps
are walked via `__start_SYSTEMD_BUS_ERROR_MAP`
(src/libsystemd/sd-bus/bus-error.c:51-52,88). Static destructors work
the same way (src/basic/static-destruct.h:14-25).

`_retain_` came with a3aff1c47f "test,static-destruct: Use retain
attribute to prevent linker garbage collection", which fixes
systemd#21847. A clang/lld build dropped the SYSTEMD_TEST_TABLE and
SYSTEMD_STATIC_DESTRUCT sections because lld doesn't let
`__start_`/`__stop_` references keep a section alive. We link with
`-Wl,--gc-sections` (meson.build:632), and users build with lld
(systemd#21847 is such a build).

Our existing Rust programs use the same pattern.
src/rust/systemd-shared/command.rs:660-676 and 862-883 put the option
and verb tables into SYSTEMD_OPTIONS and SYSTEMD_VERBS with `#[used]`
and only reach them through `__start_`/`__stop_`. Built with rustc 1.85
to 1.88 and linked with lld, they have the shape of the dropped entry
below. This wasn't tested in-tree.

## Reproducer

    ./25-used-linker-retain/run.sh

main.c has one entry in section `my_set`, marked
`__attribute__((section("my_set"), used, retain))` like ours, and
prints every entry between `__start_my_set` and `__stop_my_set`.
entry.rs adds one entry from a no_std staticlib with `#[used]` and
`#[unsafe(link_section = "my_set")]`. main.c calls `rust_init()` from
the same object, so the linker always pulls that object in and only
garbage collection decides about the entry.

The script builds entry.rs with `$RUSTC` and `$RUSTC_OLD` and shows the
section flags. The explicit form is still unstable on 1.99.1:

    $ readelf -SW main.o | grep -w my_set
      [ 7] my_set            PROGBITS        0000000000000000 000098 000008 00 WAR  0   0  8
    [...]
    $ rustc +1.99.1 --edition 2021 --crate-type lib 25-used-linker-retain/used-linker.rs -o x.rlib
    error[E0658]: `#[used(linker)]` is currently unstable
    [...]
    $ readelf -SW libentry-1.99.1.a | grep -w my_set
      [ 6] my_set            PROGBITS        0000000000000000 000048 000008 00 WAR  0   0  8
    [...]
    $ readelf -SW libentry-1.85.0.a | grep -w my_set
      [ 6] my_set            PROGBITS        0000000000000000 000058 000008 00  WA  0   0  8

Then it links with ld.bfd and ld.lld, each with the default,
`-z start-stop-gc` and `-z nostart-stop-gc`, and checks whether the
program still prints the Rust entry. lld reports that it removed the
section of the 1.85 entry:

    $ gcc -fuse-ld=lld -Wl,--gc-sections -Wl,--print-gc-sections main.o libentry-1.85.0.a -o t 2>&1 | grep my_set
    removing unused section libentry-1.85.0.a(libentry-1.85.entry.a108078b686d1999-cgu.0.rcgu.o):(my_set)
    [...]
    rustc    linker -z                Rust entry
    1.99.1   bfd    default           kept
    1.99.1   bfd    nostart-stop-gc   kept
    1.99.1   bfd    start-stop-gc     kept
    1.99.1   lld    default           kept
    1.99.1   lld    nostart-stop-gc   kept
    1.99.1   lld    start-stop-gc     kept
    1.85.0   bfd    default           kept
    1.85.0   bfd    nostart-stop-gc   kept
    1.85.0   bfd    start-stop-gc     DROPPED
    1.85.0   lld    default           DROPPED
    1.85.0   lld    nostart-stop-gc   kept
    1.85.0   lld    start-stop-gc     DROPPED

    RESULT: REPRODUCED: rustc 1.85.0, our MSRV, doesn't mark the #[used] section SHF_GNU_RETAIN and ld.lld drops the entry, rustc 1.99.1 keeps it

The C entry is kept in all twelve links. `man ld.lld` lists
`start-stop-gc` as the default, `man ld` documents ld.bfd's default as
keeping sections whose `__start_`/`__stop_` symbols are referenced.

## Upstream

rust-lang/rust#140872 "Make #[used(linker)] the default on ELF too"
(bjorn3) was merged on 2025-06-05 and is first in 1.89.0. At
846e51f66b1, compiler/rustc_codegen_ssa/src/codegen_attrs.rs:161-172
maps a plain `#[used]` to `USED_LINKER` on every target except
illumos. compiler/rustc_codegen_llvm/src/consts.rs:672-677 puts such
statics into `llvm.used`, which LLVM emits with SHF_GNU_RETAIN (LLVM
D97448, cited in consts.rs:659). Before 1.89, ELF targets used
`llvm.compiler.used`, which only keeps the symbol from being dropped by
the compiler.

The explicit `#[used(linker)]` and `#[used(compiler)]` are still
unstable. The feature is `used_with_arg`
(compiler/rustc_feature/src/unstable.rs:777), tracking issue
rust-lang/rust#93798 (open). With #140872 that only matters for code
that has to build with rustc older than 1.89.

## Workarounds

Raise the MSRV of code that registers section entries to 1.89. Nothing
else is needed.

At MSRV 1.85, link with `-Wl,-z,nostart-stop-gc`, which ld.lld and
ld.bfd both accept (rows `nostart-stop-gc`).
