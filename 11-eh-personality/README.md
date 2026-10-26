# 11. A no_std static library needs an unstable lang item to link

The prebuilt core is compiled with `panic=unwind`. One function in it,
`core::panicking::panic_nounwind_fmt`, has a landing pad and that
references `rust_eh_personality`.

meson passes `-C debug-assertions=yes` unless `b_ndebug=true`. With
that, the UB checks in functions like `slice::from_raw_parts` call into
`panic_nounwind_fmt` and the reference survives `--gc-sections`. A
13-line `#![no_std]` static library then fails to link into a shared
library with `--no-undefined`, which meson passes by default.

core documents that users provide this function through the
`eh_personality` lang item (library/core/src/lib.rs:41-44). That item is
internal to the compiler and stable rejects it.
`-C panic=immediate-abort` requires nightly too.

## Why it matters

We link with `-Wl,--gc-sections` (meson.build:632) and meson adds
`--no-undefined`. meson 1.11.1 maps `b_ndebug=false` to
`-C debug-assertions=yes -C overflow-checks=no`
(mesonbuild/compilers/rust.py:524-526).

Our Rust programs already define the symbol by hand today
(src/rust/systemd-shared/panic.rs:65). That relies on a name the
compiler doesn't promise to keep.

## Reproducer

    ./11-eh-personality/run.sh

This builds sum.rs, a `#![no_std]` helper that sums a buffer, as a
static library with `-C debug-assertions=yes` and links it into a shared
library together with lib.c, using our flags:

    $ gcc -fPIC -shared -fvisibility=hidden -Wl,--no-undefined -Wl,--gc-sections 11-eh-personality/lib.c libsum.a -o libdemo.so
    /usr/bin/x86_64-linux-gnu-ld.bfd: libsum.a(core-1d288395a3394ed3.core.efd5e57aef94d71e-cgu.0.rcgu.o):(.data.DW.ref.rust_eh_personality[DW.ref.rust_eh_personality]+0x0): undefined reference to `rust_eh_personality'
    collect2: error: ld returned 1 exit status

The reference comes from the one landing pad in the prebuilt core:

    $ for o in core/*.o; do readelf -S -W $o | grep -o '\.gcc_except_table\.[^ ]*'; done | sed 's/^\.gcc_except_table\.//' | c++filt
    core[efd5e57aef94d71e]::panicking::panic_nounwind_fmt

lang.rs uses the documented way to provide the personality and stable
rejects it:

    $ rustc +1.99.1 --edition 2021 --crate-type lib -C panic=abort 11-eh-personality/lang.rs -o /dev/null
    error[E0554]: `#![feature]` may not be used on the stable release channel
     --> 11-eh-personality/lang.rs:3:1
    [...]
    warning: the feature `lang_items` is internal to the compiler or standard library

Stable also rejects the flag that would keep core from needing the
personality:

    $ rustc +1.99.1 --edition 2021 -C panic=immediate-abort --crate-type staticlib 11-eh-personality/sum.rs -o x.a
    error: `-Cpanic=immediate-abort` requires `-Zunstable-options` and a nightly compiler

With `rust_eh_personality` defined by hand, which sum.rs does under
`--cfg stub`, the library links:

    $ rustc +1.99.1 --edition 2021 -C panic=abort -O -C debug-assertions=yes --crate-type staticlib --cfg stub 11-eh-personality/sum.rs -o libsum-stub.a
    [exit status 0]

    $ gcc -fPIC -shared -fvisibility=hidden -Wl,--no-undefined -Wl,--gc-sections 11-eh-personality/lib.c libsum-stub.a -o libdemo.so
    [exit status 0]

## Upstream

`EhPersonality` is a weak lang item named `rust_eh_personality`
(compiler/rustc_attr_ir/src/weak_lang_items.rs:28).
`-Cpanic=immediate-abort` is gated in
compiler/rustc_session/src/config.rs:2970. Building core without
unwinding needs `-Zbuild-std`, a cargo option that is nightly only, see
13.

## Workarounds

Define `#[unsafe(no_mangle)] extern "C" fn rust_eh_personality()` by
hand. It works, but it depends on an implementation detail.
