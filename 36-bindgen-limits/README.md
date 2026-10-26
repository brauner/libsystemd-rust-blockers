# 36. bindgen leaves out our macros and needs trampolines for static inline functions

bindgen 0.72.1 emits nothing for function-like macros. There are 1124
of them in the headers of src/fundamental, src/basic, src/libsystemd and
src/systemd. It also skips `static inline` functions, 673 defined
outside of macro bodies plus 11 defined by macros like
`DEFINE_TRIVIAL_CLEANUP_FUNC()`. They're only reachable through
`--wrap-static-fns`, which writes C trampolines that have to be compiled
and linked. For `close_pairp()` the generated C doesn't compile.

Bitfields turn into opaque `__BindgenBitfieldUnit` storage plus accessor
methods. There are 54 bitfields in libsystemd's internal headers (49 of
them `bool x:1`, 2 in a test header) and 2 in the public
sd-bus-vtable.h. The generated constructor isn't a `const fn`, so a Rust
`const` or `static` sd-bus vtable can't use it.

This is mostly friction, and our own Rust code already works around
it. Its log macros are reimplemented in
src/rust/systemd-shared/log.rs:120-203, meson generates the trampolines
(src/rust/systemd-shared/meson.build:54) and `close_pairp` is
blocklisted (meson.build:103-105 there).

## Why it matters

libsystemd's C code is written in these macros and helpers. The .c files
in src/libsystemd have 2012 `assert_return()` calls for 873 `_public_`
functions, and `log_*_errno()`, `TAKE_PTR()`, `IN_SET()`, `streq()` and
`HASHMAP_FOREACH()` are everywhere. sd-bus objects are described by
static `sd_bus_vtable` arrays built with `SD_BUS_METHOD()` and friends.
Those are macros as well, and the struct has the `type:8`/`flags:56`
bitfield (src/systemd/sd-bus-vtable.h:70-71). Rust code inside
libsystemd would use the same internal headers.

## Reproducer

    ./36-bindgen-limits/run.sh

count.awk counts over `$SYSTEMD_SRC` by text. Its columns are
`#define NAME(` lines (macros), `static inline` and `static __inline__`
definitions outside and inside of macro bodies (inline and minline, the
latter once per macro and not per use) and `type name:N;` members
(bitf):

    $ $BINDGEN --version
    bindgen 0.72.1
    [exit status 0]

    $ git -C $SYSTEMD_SRC log -1 --format='%h %cs'
    e9795a90b7 2026-10-25
    [exit status 0]

    $ (cd $SYSTEMD_SRC && find src/fundamental src/basic src/libsystemd src/systemd -name '*.h' | sort | xargs awk -f 36-bindgen-limits/count.awk)
    dir           macros  inline  minline   bitf
    fundamental      192      51        4      0
    basic            558     547        6      0
    libsystemd       161      69        0     54
    systemd          213       6        1      2
    total           1124     673       11     56
    [exit status 0]

    $ (cd $SYSTEMD_SRC && grep -rho -w -E 'assert_return|_public_' src/libsystemd --include='*.c' | sort | uniq -c)
       2012 assert_return
        873 _public_
    [exit status 0]

bindgen then runs over real headers (macros.h, fd.h, vt.h) with the
include paths and defines of our build. config.h stands in for the one
meson generates and passes with `-include`. Only the functions behind
some of the macros make it into the bindings. `--clang-macro-fallback`
only evaluates macros that expand to constants and doesn't change that:

    $ $BINDGEN --use-core --ctypes-prefix core::ffi --allowlist-file '.*/src/(fundamental|basic|systemd)/.*' 36-bindgen-limits/macros.h -o macros.rs -- [...]
    [exit status 0]

    $ for m in assert_return log_debug_errno TAKE_PTR streq IN_SET HASHMAP_FOREACH CMSG_FOREACH strjoina; do echo "$m $(grep -c -w $m macros.rs)"; done
    assert_return 0
    log_debug_errno 0
    TAKE_PTR 0
    streq 0
    IN_SET 0
    HASHMAP_FOREACH 0
    CMSG_FOREACH 0
    strjoina 0
    [exit status 0]

    $ grep -c -w -E 'assert_return|log_debug_errno|TAKE_PTR|streq|IN_SET|HASHMAP_FOREACH|CMSG_FOREACH|strjoina' macros.rs
    0
    [exit status 1]

    $ grep -o -w -E 'pub fn (log_assert_failed_return|log_internal|_hashmap_iterate)' macros.rs
    pub fn log_assert_failed_return
    pub fn _hashmap_iterate
    pub fn log_internal
    [exit status 0]

    $ $BINDGEN [...] --clang-macro-fallback 36-bindgen-limits/macros.h -o macros-fallback.rs -- [...]
    [exit status 0]

    $ grep -c -w -E 'assert_return|log_debug_errno|TAKE_PTR|streq|IN_SET|HASHMAP_FOREACH|CMSG_FOREACH|strjoina' macros-fallback.rs
    0
    [exit status 1]

Then the static inline functions, with `--wrap-static-fns` and without
`--experimental`:

    $ grep -c -w -E 'pub fn (isempty|streq_ptr)' macros.rs
    0
    [exit status 1]

    $ $BINDGEN [...] --wrap-static-fns --wrap-static-fns-path wrap 36-bindgen-limits/macros.h -o macros-wrap.rs -- [...]
    [exit status 0]

    $ grep -c '__extern(' wrap.c
    115
    [exit status 0]

    $ grep -E '^bool (isempty|streq_ptr)__extern' wrap.c
    bool streq_ptr__extern(const sd_char *a, const sd_char *b) { return streq_ptr(a, b); }
    bool isempty__extern(const sd_char *a) { return isempty(a); }
    [exit status 0]

    $ $BINDGEN [...] --wrap-static-fns --wrap-static-fns-path fdwrap 36-bindgen-limits/fd.h -o fd.rs -- [...]
    [exit status 0]

    $ grep close_pairp fdwrap.c
    void close_pairp__extern(int *p [2]) { close_pairp(p); }
    [exit status 0]

    $ gcc [...] -c fdwrap.c -o fdwrap.o 2>&1 | grep error:
    fdwrap.c:15:52: error: passing argument 1 of [...] from incompatible pointer type [-Wincompatible-pointer-types]
    [exit status 0]

And the bitfields of `sd_bus_vtable`. vtuse.rs tries to build
`SD_BUS_VTABLE_END` as a `const`:

    $ sed -n '/^pub struct sd_bus_vtable {/,/^}/p' vt.rs
    pub struct sd_bus_vtable {
        pub _bitfield_align_1: [u64; 0],
        pub _bitfield_1: __BindgenBitfieldUnit<[u8; 8usize]>,
        pub x: sd_bus_vtable__bindgen_ty_1,
    }
    [exit status 0]

    $ grep -E 'pub (const )?fn (type_|set_type|flags|set_flags|new_bitfield_1)\(' vt.rs
        pub fn type_(&self) -> u8 {
        pub fn set_type(&mut self, val: u8) {
        pub fn flags(&self) -> u64 {
        pub fn set_flags(&mut self, val: u64) {
        pub fn new_bitfield_1(type_: u8, flags: u64) -> __BindgenBitfieldUnit<[u8; 8usize]> {
    [exit status 0]

    $ rustc +1.99.1 --edition 2021 --crate-type lib --emit=metadata vtuse.rs -o vtuse.rmeta
    error[E0015]: cannot call non-const associated function `sd_bus_vtable::new_bitfield_1` in constants
     --> vtuse.rs:9:18
      |
    9 |     _bitfield_1: sd_bus_vtable::new_bitfield_1(b'>', 0),
      |                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
      |
      = note: calls in constants are limited to constant functions, tuple structs and tuple variants
    [...]

## Upstream

Function-like macros are rust-lang/rust-bindgen#753 "Functional C macros
are not expanded.", open since 2017.

bindgen's CHANGELOG for 0.71.0 (2024-12-06) says "The
`--wrap-static-fns` related options no longer require the experimental
feature or flag (#2928)". In v0.72.1, bindgen/options/cli.rs:501-503 is
a plain `#[arg(long)]`. Up to 0.70.x, bindgen-cli/options.rs had
`requires = "experimental"`. We require bindgen >= 0.71.1
(meson.build:381). meson 1.11.1 still passes `--experimental` along
(mesonbuild/modules/rust.py:993-996), which does no harm.

Pointer-to-array parameters like the one of `close_pairp()` are
rust-lang/rust-bindgen#3403, open.

Bitfields in const context are rust-lang/rust-bindgen#3125 ("Trying to
use `new_bitfield_N` in static"), open. PR rust-lang/rust-bindgen#3522
("codegen: make bitfield constructors usable from const context") was
opened on 2026-10-14 and is still open.

## Workarounds

Each macro gets reimplemented in Rust, as `macro_rules!` or as a
function, and kept in sync with the C version by hand.

Static inline helpers go through generated trampolines, compiled without
LTO (see 35), with a real call per use. Some signatures need a blocklist
entry and a hand-written binding.

Bitfields go through the accessors at run time. For `const` or `static`
data the bits can be packed into `__BindgenBitfieldUnit::new([u8; 8])`
by hand, which is a `const fn`. Then we have to follow the ABI's
bitfield allocation ourselves, which differs between little-endian and
big-endian targets.
