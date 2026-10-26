# 04. A Rust-ABI shared library exports all of core, and two of them don't mix

A `dylib` re-exports everything it links statically so that Rust code
downstream can use it. For a `#![no_std]` library that's all of `core`.
17 lines of library code come out as 272 KB stripped with 550 exported
symbols, 426 of them from `core`. Note that the crate metadata
(`.rustc`) survives `strip`. The same source as a `cdylib` is 4 KB with
2 exports.

Each such library also carries its own panic handler. So a program can't
link two of them that don't depend on each other.

## Why it matters

A Rust-ABI libsystemd-shared would ship and export a private copy of
core. Every other Rust shared library a program wants to use would have
to be built on top of that one, because two independent ones conflict.

## Reproducer

    ./04-dylib-exports/run.sh

This builds sdshared.rs once as a `dylib` and once as a `cdylib`, strips
both and counts their exports:

    ## libsdshared.so
       stripped size:        272232 bytes
       exported symbols:     550
       ... of which core::   426
       .rustc after strip:   3006 bytes

    ## libsdshared-c.so
       stripped size:        3984 bytes
       exported symbols:     2
       ... of which core::   0

It also prints every 60th of the `core` exports of the `dylib`:

    ## a few of the exports of libsdshared.so
    T core::panicking::assert_failed::<core::option::Option<usize>, core::option::Option<usize>>
    T core::panicking::panic_const::panic_const_async_gen_fn_resumed_drop
    T <core::ffi::va_list::VaList as core::fmt::Debug>::fmt
    T <core::num::niche_types::U32NotAllOnes as core::fmt::Debug>::fmt
    T <i64 as core::pat::RangePattern>::sub_one
    T <core::char::ToTitlecase as core::iter::traits::iterator::Iterator>::advance_by
    T <i128 as core::fmt::Display>::fmt
    T <u32 as core::fmt::UpperExp>::fmt

Then it builds other.rs, an unrelated second `dylib`, and user.rs, which
uses both:

    $ rustc +1.99.1 ... 04-dylib-exports/user.rs -L . --extern sdshared=libsdshared.so --extern other=libother.so -o user
    error[E0152]: duplicate lang item in crate `other` (which `user` depends on): `panic_impl`
      |
      = note: the lang item is first defined in crate `sdshared` (which `user` depends on)
      = note: first definition in `sdshared` loaded from $W/libsdshared.so
      = note: second definition in `other` loaded from $W/libother.so
    [...]
    [exit status 1]

## Upstream

This is how the `dylib` crate type is designed. Changing it would need a
stable ABI (rust-lang/rfcs#3470, open) and a shared core, which doesn't
exist (see 07).

## Workarounds

Use a `cdylib` or `staticlib`, which means a C ABI.
