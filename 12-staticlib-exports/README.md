# 12. A staticlib leaks core through libsystemd-shared's export-all version script

rustc gives the symbols in a Rust static library default visibility
(rust-lang/rust#104707). libsystemd-shared is compiled with
`-fvisibility=default` and exports everything with
`SD_SHARED { global: *; };` in src/shared/libshared.sym
(src/shared/meson.build:466-474).

Put 25 lines of Rust into it and it exports 545 Rust symbols. The
library grows from 18 KB to 277 KB stripped. Every exported symbol is a
`--gc-sections` root, and 1.99.1's libcore.rlib is a single object
file, so all of core is kept.

libsystemd.so isn't affected since it has an explicit list and
`local: *;`. Its cost is the `core::fmt` code, 4 KB more than the same
function in C.

## Why it matters

libsystemd's code ends up in libsystemd-shared too, through `link_whole`
of libsystemd_static (src/shared/meson.build:474-477). In a default
build it also goes into 13 other artifacts:

- libsystemd.so and libudev.so
- four NSS modules
- three PAM modules
- four `.standalone` programs

Each one gets its own copy of the core code it uses.

## Reproducer

    ./12-staticlib-exports/run.sh

This builds sd.rs, which formats an id into a C buffer, as a static
library. It links that with lib.c into three shared libraries, and the
same function in plain C, c-only.c, into a fourth one for comparison:

- libshared.so like libsystemd-shared, with `-fvisibility=default` and
  `global: *;` (shared.sym)
- libpublic.so like libsystemd.so, with `-fvisibility=hidden` and an
  explicit list with `local: *;` (public.sym)
- libshared-hidden.so like libshared.so, but with Rust's mangled names
  hidden (hidden.sym)
- libc-only.so from c-only.c, linked like libpublic.so

The settings it copies from libsystemd-shared:

    $ cat $SYSTEMD_SRC/src/shared/libshared.sym
    SD_SHARED {
            global: *;
    };

    $ grep -n -A6 '^libshared = shared_library' $SYSTEMD_SRC/src/shared/meson.build
    466:libshared = shared_library(
    [...]
    470-        c_args : ['-fvisibility=default'],
    471-        link_args : ['-shared',
    472-                     '-Wl,--version-script=' + libshared_sym_path],

The sizes and exports of the four libraries:

    ## libshared.so: 276672 bytes stripped, exports 548 symbols, 545 of them Rust:
    T core::panicking::assert_failed::<core::option::Option<usize>, core::option::Option<usize>>@@SD_SHARED
    T core::panicking::assert_failed::<usize, usize>@@SD_SHARED
    T core::panicking::assert_failed::<u64, u64>@@SD_SHARED
    T <str>::escape_debug@@SD_SHARED
    [...]

    ## libpublic.so: 18440 bytes stripped, exports 1 symbols, 0 of them Rust:
    T sd_demo_format_id@@LIBDEMO_1

    ## libshared-hidden.so: 18520 bytes stripped, exports 2 symbols, 0 of them Rust:
    T rs_format_id@@SD_SHARED
    T sd_demo_format_id@@SD_SHARED

    ## libc-only.so: 14304 bytes stripped, exports 1 symbols, 0 of them Rust:
    T sd_demo_format_id@@LIBDEMO_1

The nightly option that hides them is rejected on stable:

    $ rustc +1.99.1 --edition 2021 -C panic=abort --crate-type staticlib -Zstaticlib-hide-internal-symbols 12-staticlib-exports/sd.rs -o x.a
    error: the option `Z` is only accepted on the nightly compiler

## Upstream

rust-lang/rust#104707 "Don't leak non-exported symbols from staticlibs"
is open. `-Zstaticlib-hide-internal-symbols` came with
rust-lang/rust#155338, merged on 2026-06-08, and is nightly only
(compiler/rustc_session/src/options.rs:2923).

## Workarounds

This one we can fix on our side. Add `local: _R*; rust_eh_personality;`
to libshared.sym, see hidden.sym in the reproducer. That works as long
as rustc keeps using v0 mangling.
