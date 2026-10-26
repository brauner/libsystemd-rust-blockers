# 24. A foreign unwind through a Rust frame skips Drop or aborts

A C++ exception thrown in a callback, or a forced unwind started in one
(`pthread_exit()`, `pthread_cancel()`), passes through the library call
that ran the callback. A C frame built with `-fexceptions` runs its
`__attribute__((cleanup))` handlers and passes the unwind on.

On rustc 1.99.1 a Rust frame built the way our policy allows
(`#![no_std]`, `-C panic=abort`) either skips its `Drop` or aborts. If
the callback is declared `extern "C"`, the frame is unwound without
running its `Drop`, which the Rust reference makes undefined behavior.
With rustc 1.85, our MSRV, the frame has no unwind table and a C++
exception ends in `std::terminate()`. If the callback is declared
`extern "C-unwind"`, the process aborts, for the C++ exception and for
`pthread_exit()` and `pthread_cancel()` alike.

## Why it matters

Fedora builds libsystemd with `-fexceptions`. systemd.spec (rawhide at
867d0744af) builds with `%meson` (systemd.spec:1040) and the
distribution's flags. redhat-rpm-config (rawhide at ba749272b7) sets
them in macros:449:

    %_general_options -O2 %{?_lto_cflags} -fexceptions -g -grecord-gcc-switches -pipe

Its buildflags.md:529-538 gives the reason: "It also makes it possible
to unwind the stack (using C++ `throw` or Rust panics) from C callback
functions if a C library supports non-local exits from them (e.g., via
`longjmp`)." Debian's `dpkg-buildflags --get CFLAGS` has no
`-fexceptions`. There the exception still crosses the C frames, minus
the cleanups (row `c` below).

libsystemd doesn't document whether callbacks may throw or end the
thread, but at least one consumer let exceptions through. sdbus-c++ up
to 1.4.0 caught only its own `sdbus::Error` in the trampolines it
registers with sd-bus (src/Proxy.cpp:333-340 and
src/Object.cpp:350-357 at v1.4.0). So any other exception from a signal
or method handler propagated through `sd_bus_process()`. 1.5.0 catches
everything (Kistler-Group/sdbus-cpp#375, "Catch and process all
exceptions (not just `sdbus::Error`) from callback handlers"). Ubuntu
24.04 ships 1.4.0, Debian 12 ships 1.2.0.

Cancellation needs no callback at all. `sd_bus_wait()` blocks in
`ppoll()` (src/libsystemd/sd-bus/sd-bus.c:3415 via
src/basic/fiber-ops.c:23), which is a cancellation point. A Rust frame
calling `ppoll()` through the `libc` crate, which declares everything
`extern "C"`, is in the position of row `rust-C`.

Our Rust programs already define `rust_eh_personality` to abort
(src/rust/systemd-shared/panic.rs:61-72, see 11-eh-personality). Its
comment says "should a foreign exception ever reach a Rust frame,
abort". That only holds for frames with a landing pad, i.e.
`extern "C-unwind"` calls. An `extern "C"` call gets no landing pad,
the personality routine is never asked, and the exception passes (row
`rust-C`).

meson.build:480 justifies `-Cpanic=abort` with "Unwinding could not
cross the C frames of an event loop anyway". On x86_64 an unwind does
cross C frames, with or without `-fexceptions` (rows `c` and
`c-fexceptions`).

## Reproducer

    ./24-foreign-unwind/run.sh

lib.c and lib.rs are the same library call. Both run a callback while a
cleanup is pending, `__attribute__((cleanup))` in C and a `Drop` guard
in Rust. In main.cpp the callback throws a `std::runtime_error` and
main catches it. In thread.c it calls `pthread_exit(42)`, or blocks in
`ppoll()` and gets cancelled.

lib.c is built without and with `-fexceptions`. lib.rs is built with
our Rust flags, with an `extern "C"` and an `extern "C-unwind"`
callback, and once more with `$RUSTC_OLD`. Like systemd-shared it
defines `rust_eh_personality` to call `abort()`. For comparison, the
`std-` rows build lib.rs with std, which is outside the policy, with
`panic=abort` and `panic=unwind`. In the table, "cleanup" is the C
cleanup handler or the Rust `Drop`, whichever the frame has:

    # rustc 1.99.1 (58cf8f9c3 2026-10-13)
    # gcc (Debian 16.2.0-1) 16.2.0
    [...]
                         C++ throw                   pthread_exit()              pthread_cancel()
    c                    cleanup skipped, passed on  cleanup skipped, passed on  cleanup skipped, passed on
    c-fexceptions        cleanup ran, passed on      cleanup ran, passed on      cleanup ran, passed on
    rust-C               cleanup skipped, passed on  cleanup skipped, passed on  cleanup skipped, passed on
    rust-1.85-C          std::terminate()            cleanup skipped, passed on  cleanup skipped, passed on
    rust-C-unwind        abort()                     abort()                     abort()
    std-abort-C-unwind   cleanup ran, abort()        cleanup ran, abort()        cleanup ran, abort()
    std-unwind-C         cleanup skipped, passed on  cleanup skipped, passed on  cleanup skipped, passed on
    std-unwind-C-unwind  cleanup ran, passed on      cleanup ran, passed on      cleanup ran, passed on

Row `c` passes the unwind on because gcc emits unwind tables by
default:

    $ gcc -Q --help=common | grep -e -fasynchronous-unwind-tables
      -fasynchronous-unwind-tables 		[enabled]

Two builds fail, no_std with `panic=unwind`, and `extern "C-unwind"`
without a personality routine (`--cfg no_personality`):

    $ rustc +1.99.1 ... 24-foreign-unwind/lib.rs -C panic=unwind -o x.a
    error: unwinding panics are not supported without std
    [...]
    $ g++ -Wl,--gc-sections main.o x.a -o x
    /usr/bin/x86_64-linux-gnu-ld.bfd: x.a(x.lib.9b1d2436265349b7-cgu.0.rcgu.o):(.data.DW.ref.rust_eh_personality[DW.ref.rust_eh_personality]+0x0): undefined reference to `rust_eh_personality'

The Rust rows differ because of what rustc emits for the call. With
`extern "C"` the call is `nounwind` and has no landing pad. 1.99.1
gives the function an unwind table (`uwtable`), 1.85 doesn't:

    $ rustc +1.99.1 ... -C panic=abort --emit=llvm-ir -o - | grep ...
    define void @lib_call(ptr nofree noundef nonnull readonly captures(none) %cb) unnamed_addr #1 !guid !7 {
      tail call void %cb() #4
    [...]
    attributes #1 = { nounwind nonlazybind uwtable "probe-stack"="inline-asm" "target-cpu"="x86-64" }
    [...]
    attributes #4 = { nounwind }
    [...]
    $ rustc +1.85.0 ... -C panic=abort --emit=llvm-ir -o - | grep ...
    define void @lib_call(ptr nocapture noundef nonnull readonly %cb) unnamed_addr #1 {
    [...]
    attributes #1 = { nounwind nonlazybind "probe-stack"="inline-asm" "target-cpu"="x86-64" }

With `extern "C-unwind"` the call gets a landing pad that runs the
`Drop` and then calls `panic_cannot_unwind()`. The personality routine
is asked first, and our stub aborts right there:

    $ rustc +1.99.1 ... -C panic=abort --cfg c_unwind --emit=llvm-ir -o - | sed -n '/^define.*@lib_call/,/^}/p' | grep ...
    define void @lib_call(ptr nofree noundef nonnull readonly captures(none) %cb) unnamed_addr #2 personality ptr @rust_eh_personality !guid !8 {
      invoke void %cb()
      %0 = landingpad { ptr, i32 }
              cleanup
    ; call core::ptr::drop_glue::<lib::Guard>
    ; call core::panicking::panic_cannot_unwind

With std's personality routine the landing pad runs, even for a forced
unwind:

    $ ./thread-std-abort-C-unwind cancel
    lib: drop ran

    thread '<unnamed>' (25362) panicked at /rustc/58cf8f9c35b355199727627d07ae34a4e2846d67/library/core/src/panicking.rs:225:5:
    panic in a function that cannot unwind
    [...]
    [exit status 134]

## Upstream

The Rust reference, at rust-lang/reference 2dafab96d919 which
846e51f66b1 pins:

- items/functions.md, `r[items.fn.extern.unwind.behavior]`: for
  `panic=abort`, a native (unforced) unwind reaching an "unwinding" ABI
  boundary is "abort", and reaching a "non-unwinding" one (`"C"`) is
  "undefined behavior". "Forced unwinding is explicitly excluded from
  the "Native unwind" column in the table."
- panic.md, `r[panic.unwind.ffi.undefined]`: "Causing an unwind into
  Rust code from a foreign function that was called via a function
  declaration or pointer declared with a non-unwinding ABI, such as
  `"C"`, ..." is undefined behavior.
- behavior-considered-undefined.md, `r[undefined.runtime]`: "The runtime
  assumes that a Rust stack frame is not deallocated without executing
  destructors for local variables owned by the stack frame."

RFC 2945 (C-unwind ABI), "Frame deallocation and forced unwinding",
makes forced unwinding undefined behavior "When deallocating Rust
non-POFs", i.e. frames with a live `Drop` value. For frames without one
"for now, this is not specified, and must be considered undefined
behavior". It also says "`panic=abort` will have no impact on the
behavior of forced unwinding". The reference still points to the RFC
for forced unwinding (items/functions.md:326).

In rustc at 846e51f66b1:

- compiler/rustc_middle/src/ty/layout.rs:1317-1323: with `panic=abort`
  a function defined in Rust never unwinds, "a `extern "C-unwind"`
  function defined in Rust is also required to abort".
- compiler/rustc_mir_transform/src/abort_unwinding_calls.rs:117-123
  removes the landing pad of a call that can't unwind, which includes
  every `extern "C"` call. So a pending `Drop` has no cleanup for it.
  Lines 78-82 and 124-134 end the unwind edge of an `extern "C-unwind"`
  call in a function that can't unwind with `UnwindTerminate(Abi)`,
  after the cleanup.
- library/std/src/sys/personality/gcc.rs:266-269: std's personality
  routine lets forced unwinds pass terminate-only landing pads. The
  frame above has a `Drop`, so its landing pad is a cleanup and std
  aborts anyway (row `std-abort-C-unwind`).
- compiler/rustc_passes/src/weak_lang_items.rs:54-55 and
  diagnostics.rs:187-193: "unwinding panics are not supported without
  std".
- compiler/rustc_target/src/spec/base/linux.rs:15-17: unwind tables
  with `panic=abort` are emitted by default on Linux since
  rust-lang/rust#143613 (merged 2025-10-03, Rust 1.92). According to
  that commit they had been left out since 1.23, which is why 1.85
  terminates.

## Workarounds

Keep the frames that run application callbacks or block in
cancellation points in C. Rust then only works in helpers that neither
call back nor block, which rules out most of sd-bus, sd-event and
sd-journal's wait functions.

Declare callbacks `extern "C-unwind"`. That replaces the undefined
behavior with an abort. A program that throws through a callback or
cancels a thread inside libsystemd dies, where with C frames the
exception reaches its catch and the thread ends.

Keep `extern "C"`. On rustc 1.92 and later this behaves like C without
`-fexceptions` and skips the cleanups, but it's undefined behavior. On
1.85 to 1.91 a C++ exception terminates the program.

Use std with `-C panic=unwind` and `extern "C-unwind"`. Of the Rust
settings tested, it's the only one that runs `Drop` and passes the
unwind on, like `-fexceptions` does (row `std-unwind-C-unwind`). But
`-C panic=unwind` doesn't build without std, our policy excludes std,
and RFC 2945 still makes the forced-unwind columns of that row
undefined behavior.
