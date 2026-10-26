# 03. A Rust-ABI shared library can't be built with LTO on stable

`-C lto`, fat or thin, is rejected for crate type `dylib`. The way
around it is `-Zdylib-lto`, a nightly option. The `staticlib` and
`cdylib` crate types take `-C lto` just fine.

## Why it matters

Distributions build libraries with LTO. Fedora has done so by default
since Fedora 33 (https://fedoraproject.org/wiki/LTOByDefault). The small
size of our Rust programs also comes from LTO (`-Db_lto=true`). A
Rust-ABI libsystemd-shared would be the one big piece that can't get it.

## Reproducer

    ./03-dylib-lto/run.sh

This builds sdshared.rs as a `dylib`, first without LTO and then with
`-C lto=fat` and `-C lto=thin`. Both LTO builds fail:

    $ rustc +1.99.1 ... --crate-type dylib -C lto=fat 03-dylib-lto/sdshared.rs -o lto-fat.so
    error: lto cannot be used for `dylib` crate type without `-Zdylib-lto`
    [...]
    [exit status 1]

    $ rustc +1.99.1 ... --crate-type dylib -C lto=thin 03-dylib-lto/sdshared.rs -o lto-thin.so
    error: lto cannot be used for `dylib` crate type without `-Zdylib-lto`
    [...]
    [exit status 1]

The same source as a `staticlib` and as a `cdylib` builds with LTO:

    $ rustc +1.99.1 ... --crate-type staticlib -C lto=fat 03-dylib-lto/sdshared.rs
    [exit status 0]

    $ rustc +1.99.1 ... --crate-type cdylib -C lto=fat 03-dylib-lto/sdshared.rs -o cdylib.so
    [exit status 0]

And `-Zdylib-lto` needs a nightly compiler:

    $ rustc +1.99.1 ... --crate-type dylib -C lto=fat -Zdylib-lto 03-dylib-lto/sdshared.rs -o lto-z.so
    error: the option `Z` is only accepted on the nightly compiler
    [...]
    [exit status 1]

## Upstream

The check is in compiler/rustc_codegen_ssa/src/back/lto.rs:150 and :158,
with the message at compiler/rustc_codegen_ssa/src/diagnostics.rs:1338.
`dylib_lto` is in the `-Z` block,
compiler/rustc_session/src/options.rs:2514.

## Workarounds

Use a `staticlib` or `cdylib`, which means a C ABI (see 06).
