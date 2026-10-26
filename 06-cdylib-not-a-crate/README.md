# 06. A C-ABI Rust shared library can't be used from Rust as a crate

A `cdylib` has no Rust metadata, so rustc refuses it as a crate (E0786).
Rust programs have to declare its functions as `extern "C"`, by hand or
with bindgen. That gives up slices, `Option`/`Result`, lifetimes and
ownership at the boundary.

## Why it matters

The `cdylib` is the Rust-built shared library without a compiler lock-in
(01) and with LTO (03). But a Rust program in systemd would then talk to
Rust code in libsystemd through unsafe C declarations and would have to
wrap again what the library just unwrapped. Plus, it doesn't solve the
symbol versioning problem (05).

## Reproducer

    ./06-cdylib-not-a-crate/run.sh

This builds sdshared.rs as a `cdylib`. It has no `.rustc` section:

    $ readelf -S -W libsdshared.so | grep '\.rustc' || echo 'no .rustc section'
    no .rustc section
    [exit status 0]

So user.rs, which uses `sdshared::first_word()` from the crate, fails to
build:

    $ rustc +1.99.1 ... 06-cdylib-not-a-crate/user.rs -L . --extern sdshared=libsdshared.so -o user
    error[E0786]: found invalid metadata files for crate `sdshared`
     --> 06-cdylib-not-a-crate/user.rs:9:11
      |
    9 |     match sdshared::first_word(b"hello world") {
      |           ^^^^^^^^
      |
      = note: no `.rustc` section in '$W/libsdshared.so'
    [...]
    [exit status 1]

user-ffi.rs declares `sd_first_word_len()` as `extern "C"` instead. That
one builds and runs:

    $ rustc +1.99.1 ... 06-cdylib-not-a-crate/user-ffi.rs -L . -o user-ffi
    [exit status 0]

    $ LD_LIBRARY_PATH=. ./user-ffi
    [exit status 5]

## Upstream

crABI, rust-lang/rfcs#3470, is open. It would allow a richer but still
C-like stable ABI.

## Workarounds

bindgen or hand-written declarations plus a safe wrapper crate on the
consumer side. That's what our Rust programs already do today for the C
code in libsystemd-shared.
