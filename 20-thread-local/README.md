# 20. No thread-local statics in no_std Rust on stable

Stable Rust has no thread-local statics for `#![no_std]` code.
rustc 1.99.1 rejects the `#[thread_local]` attribute with E0658,
`std::thread_local!()` only exists in std and nothing in `core` offers
thread-local storage. So code that keeps per-thread state, like
libsystemd does, has to keep that state in C or write the TLS access in
assembly.

## Why it matters

src/libsystemd has 12 `static thread_local` variables (main e9795a90b7):

- sd-bus/sd-bus.c:74-76, the per-thread default system, user and
  starter bus (`sd_bus_default_system()` and friends)
- sd-event/sd-event.c:191, the per-thread default event loop
  (`sd_event_default()`)
- sd-resolve/sd-resolve.c:518, the per-thread default resolver
- sd-future/fiber.c:44, the currently running fiber
- sd-id128/sd-id128.c:131,189,302, the cached machine, boot and
  invocation IDs
- sd-journal/journal-file.c:317,334,381, cached settings

sd-event also stores the address of its slot in the event object
(sd-event.c:5141) and clears it when the loop is freed
(sd-event.c:391-392).

The per-thread defaults are documented API. "All threads have exactly
either zero or one default event loop" (man/sd_event_new.xml:80-93), and
the same goes for the default buses (man/sd_bus_default.xml:117-130).

Plus, libsystemd links libbasic (src/libsystemd/meson.build:157-158,
meson.build:2117-2118), which has another 24 `static thread_local`
variables in src/basic.

## Reproducer

    ./20-thread-local/run.sh

tls.rs keeps sd-event's default event in a `#[thread_local] static` and
is built as a no_std staticlib with `$RUSTC`. That has to fail with
E0658:

    # rustc 1.99.1 (58cf8f9c3 2026-10-13)
    # gcc (Debian 16.2.0-1) 16.2.0
    # x86_64 7.1.13+deb14-amd64

    $ rustc +1.99.1 --edition 2021 --crate-type staticlib -C panic=abort -O 20-thread-local/tls.rs -o libtls.a 2>&1 | tee tls.err
    error[E0658]: the `thread_local` attribute is an experimental feature, and does not currently handle destructors
     --> 20-thread-local/tls.rs:7:3
      |
    7 | #[thread_local]
      |   ^^^^^^^^^^^^
      |
      = note: see issue #29594 <https://github.com/rust-lang/rust/issues/29594> for more information
    [...]
    [exit status 1]

The feature itself exists and works. With `RUSTC_BOOTSTRAP=1` and
`-Zcrate-attr='feature(thread_local)'` the same file builds, and main.c
runs two threads which each set and read their own default event:

    $ ./tls
    thread 2: default event 0x2
    thread 1: default event 0x1
    main: default event (nil)

Then it counts the sites in libsystemd and libbasic and looks for
anything thread-local in core. core only links to std's macro in its
documentation:

    $ git -C $SYSTEMD_SRC grep 'static thread_local' -- src/libsystemd | wc -l
    12
    $ git -C $SYSTEMD_SRC grep 'static thread_local' -- src/basic | wc -l
    24
    $ grep -rn 'thread_local' $RUST_SRC/library/core/src
    $RUST_SRC/library/core/src/alloc/global.rs:176:///  - [`std::thread_local`],
    $RUST_SRC/library/core/src/alloc/global.rs:183:/// [`std::thread_local`]: ../../std/macro.thread_local.html
    $RUST_SRC/library/core/src/alloc/mod.rs:515:///  - [`std::thread_local`],
    $RUST_SRC/library/core/src/alloc/mod.rs:522:/// [`std::thread_local`]: ../../std/macro.thread_local.html
    $ grep -rn 'macro_rules! thread_local' $RUST_SRC/library
    $RUST_SRC/library/std/src/thread/local.rs:356:macro_rules! thread_local {

The first workaround keeps the variable in C. shim.c has the
`static thread_local` variable and two accessors, and shim.rs calls
them. That works, and the Rust function is just a jump into the C
accessor:

    $ ./shim
    thread 2: default event 0x2
    thread 1: default event 0x1
    main: default event (nil)
    $ objdump -dr --no-show-raw-insn --disassemble=rust_default_event_get libshim.a | sed -n '/<rust_default_event_get>:/,/^$/p'
    0000000000000000 <rust_default_event_get>:
       0:	jmp    *0x0(%rip)        # 6 <rust_default_event_get+0x6>
    			2: R_X86_64_GOTPCREL	default_event_get-0x4

Built into a shared library, the C variable gets the dynamic TLS model:

    $ readelf -dr libshim.so | grep -E 'TPOFF|DTPMOD|STATIC_TLS'
    000000003fb8  000000000010 R_X86_64_DTPMOD64                    0

The second workaround is x86_64 only. asm.rs defines the variable in
`.tbss` with `global_asm!()` and reads it with `asm!()`. That builds
with `$RUSTC_OLD`, our MSRV, and works too. But a shared library built
from it needs static TLS:

    $ rustc +1.85.0 --edition 2021 --crate-type staticlib -C panic=abort -O 20-thread-local/asm.rs -o libasm.a
    [exit status 0]
    $ ./asm
    thread 2: default event 0x2
    thread 1: default event 0x1
    main: default event (nil)
    $ readelf -dr libasm.so | grep -E 'TPOFF|DTPMOD|STATIC_TLS'
     0x000000000000001e (FLAGS)              STATIC_TLS
    000000056ca8  000000000012 R_X86_64_TPOFF64                     0

## Upstream

`#[thread_local]` is the unstable feature `thread_local`
(compiler/rustc_feature/src/unstable.rs:747) with the tracking issue
rust-lang/rust#29594, which was still open on 2026-10-26.
`cfg(target_thread_local)` is unstable under the same issue
(unstable.rs:431). At 846e51f66b1 (1.101.0-dev) `thread_local` is still
listed in unstable.rs.

`thread_local!()` has been stable since 1.0, but it's defined in std
(library/std/src/thread/local.rs:356). std itself builds with
`#![feature(thread_local)]` (library/std/src/lib.rs:311) and uses
`#[thread_local]` internally, or OS TLS keys where the target has no
native TLS (library/std/src/sys/thread_local/mod.rs:36-57).

core only mentions thread-local storage in documentation links to std
(library/core/src/alloc/global.rs:176,183 and alloc/mod.rs:515,522).

## Workarounds

Keep each thread-local variable in C with get/set accessors and call
them from Rust through `extern "C"` (shim.c, shim.rs). That works with
any rustc. Each access is an `unsafe` call into C that can't be inlined
without cross-language LTO, and where C takes the address of the slot
(sd-event.c:5141) we'd need accessors that return the address. For
libsystemd that means keeping the 12 variables, and the 24 in libbasic,
in C. In a shared library the C access itself already goes through
`__tls_get_addr()` (dynamic TLS model), so the extra call doesn't cost
much at runtime. Most of the cost is the glue code.

Write the TLS access by hand with `global_asm!()` and `asm!()` (asm.rs).
That's stable since 1.59 and works on 1.85.0 for x86_64. But it has to
be written for every architecture we support and for a TLS model, and
the compiler doesn't know about the variable. The initial-exec model
used here marks the library `STATIC_TLS`, which can make `dlopen()` of
it fail when the static TLS reserve is used up. The dynamic model that C
gets for `-fPIC` code would need a call to `__tls_get_addr()` from the
assembly.

Use `pthread_key_create()` and `pthread_getspecific()` through libc,
which isn't shown here. The per-thread value has to be allocated on
first use, which can fail, and freed by the destructor passed to
`pthread_key_create()`, and every access is a libc call. This is what
std's `thread_local!()` falls back to on targets without native TLS.
