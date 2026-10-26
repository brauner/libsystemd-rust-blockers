# 02. Generic code of a Rust shared library ends up in every program

Rust APIs are generic. They use containers, iterators, closures,
`Option`/`Result` helpers and trait-bound functions. A shared library
can't contain instantiations for types it doesn't know, so that code is
compiled into every program that calls it.

At `-C opt-level=2` and `3` rustc mostly doesn't even reuse the
instantiations the library does contain. It only reuses them for
functions marked `#[inline(never)]`. Sharing all of them takes
`-Zshare-generics`, which is a nightly option and only on by default at
opt-level 0, 1, s and z.

That's just how generics work and C++ templates are no different. But it
means that a Rust API in a shared library doesn't keep code out of the
programs like a C API does.

## Why it matters

libsystemd-shared, our private library, exists so that more than 150
programs carry the shared code only once. In C all of it stays in the
library because nothing is generic. A Rust-native API would move the
generic part back into each program.

## Reproducer

    ./02-dylib-generics/run.sh

sdshared.rs has a generic `sort_unique<T: Ord + Copy>()` and a plain
`unique_u32()` which uses the `u32` instantiation itself. user.rs calls
the plain function (`plain`), the generic one with `u32` (`generic`) or
the generic one with `Uid`, a type of its own (`own_type`). The library
and the three programs are built at opt-level 2, 3 and s.

At opt-level 2 `plain` gets the sort from the library. `generic` has
`sort_unique::<u32>` compiled into `main()`. The only part of the sort
it imports is `ipnsort()`, since that one is `#[inline(never)]`.
`own_type` gets the whole sort compiled in:

    ######## -C opt-level=2
    [...]
    ## plain: .text 337 bytes
       Rust code imported from libsdshared.so:
         sdshared::unique_u32
       Rust code compiled into the program:

    ## generic: .text 568 bytes
       Rust code imported from libsdshared.so:
         core::slice::sort::unstable::ipnsort::<u32, <u32 as core::cmp::PartialOrd>::lt>
         core::panicking::panic_bounds_check
       Rust code compiled into the program:

    ## own_type: .text 3723 bytes
       Rust code imported from libsdshared.so:
         core::panicking::panic_bounds_check
         core::slice::sort::shared::smallsort::panic_on_ord_violation
       Rust code compiled into the program:
           339     core::slice::sort::unstable::ipnsort::<user::Uid, <user::Uid as core::cmp::PartialOrd>::lt>
           169     core::slice::sort::shared::pivot::median3_rec::<user::Uid, <user::Uid as core::cmp::PartialOrd>::lt>
           152     core::slice::sort::unstable::heapsort::heapsort::<user::Uid, <user::Uid as core::cmp::PartialOrd>::lt>
          2469     core::slice::sort::unstable::quicksort::quicksort::<user::Uid, <user::Uid as core::cmp::PartialOrd>::lt>

Opt-level 3 looks the same, only `own_type` is a bit bigger with 3787
bytes.

At opt-level s share-generics is on by default. So `generic` imports
`sort_unique::<u32>` from the library, but `own_type` still gets the
sort compiled in:

    ######## -C opt-level=s
    [...]
    ## generic: .text 312 bytes
       Rust code imported from libsdshared.so:
         sdshared::sort_unique::<u32>
       Rust code compiled into the program:

    ## own_type: .text 3303 bytes
       Rust code imported from libsdshared.so:
         core::panicking::panic_bounds_check
         core::slice::sort::shared::smallsort::panic_on_ord_violation
       Rust code compiled into the program:
           137     core::slice::sort::unstable::ipnsort::<user::Uid, <user::Uid as core::cmp::PartialOrd>::lt>
           176     core::slice::sort::shared::pivot::median3_rec::<user::Uid, <user::Uid as core::cmp::PartialOrd>::lt>
           131     core::slice::sort::unstable::heapsort::heapsort::<user::Uid, <user::Uid as core::cmp::PartialOrd>::lt>
          2336     core::slice::sort::unstable::quicksort::quicksort::<user::Uid, <user::Uid as core::cmp::PartialOrd>::lt>

Turning it on by hand needs a nightly compiler:

    $ rustc +1.99.1 --edition 2021 -Zshare-generics=yes 02-dylib-generics/user.rs -L o2 --extern sdshared=o2/libsdshared.so -o x
    error: the option `Z` is only accepted on the nightly compiler
    [...]
    [exit status 1]

## Upstream

There's no fix to wait for. The relevant bits in rustc are:

- compiler/rustc_session/src/config.rs:1568, `share_generics()` defaults
  to true only for `OptLevel::No | Less | Size | SizeMin`.
- compiler/rustc_session/src/options.rs:2887, the option itself is in
  the `-Z` block.
- compiler/rustc_middle/src/ty/instance.rs:228-237, without it upstream
  instances are only used for `#[inline(never)]` functions.

## Workarounds

Keep a shared library's API non-generic, which in practice means a
C-shaped API.
