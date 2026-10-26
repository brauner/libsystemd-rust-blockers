# 23. A panic in no_std Rust library code kills the process that called it

In `#![no_std]` Rust built with `-C panic=abort`, which is how we build
Rust code, any implicit panic in a function called from C aborts the
calling process. Examples are an out-of-bounds index,
`copy_from_slice()` with mismatched lengths, `unwrap()` on `None`, and
an arithmetic overflow under `-C overflow-checks=yes`. On stable there's
no way to turn the panic into an error return. The panic handler must
return `!`. `-C panic=unwind` is rejected without std, so abort is the
only panic strategy. `catch_unwind()` only exists in std, and core's
`catch_unwind` intrinsic is unstable.

libsystemd's C code instead checks its arguments with `assert_return()`,
which logs at debug level and returns an error such as `-EINVAL` to the
caller.

To be fair to Rust, an out-of-bounds access that C doesn't check is
undefined behavior, which is worse. But the defined outcome in Rust is
the death of the host process, and the host process is whatever program
uses libsystemd.

## Why it matters

We build all Rust code with both `-Coverflow-checks=yes` and
`-Cpanic=abort` (meson.build:477-482, main e9795a90b7). libsystemd's
code runs in all of these:

- libsystemd.so.0, in every program that links it. See
  meson.build:2108-2125, `link_whole : [libsystemd_static]` at 2119.
- libsystemd-shared, src/shared/meson.build:466-481, with `link_whole`
  of `libsystemd_static` at 474-477. Every program built from
  `executable_template` links it (`'link_with' : [libshared]`,
  meson.build:2252-2254). The generator, libexec, test and fuzz
  templates are built on top of it (meson.build:2260, 2264, 2272, 2313).
  PID 1 links `libcore` and `libshared` (src/core/meson.build:234-241).
  On Debian's systemd 261.2, all 82 ELF executables under
  /usr/lib/systemd, generators included, and systemctl, journalctl,
  busctl, loginctl and udevadm link libsystemd-shared-261.so. That was
  checked by hand and isn't part of run.sh.
- The `.standalone` variants, which link `libsystemd_static` directly
  (meson.build:2687-2694).
- The NSS modules (`nss_template`, meson.build:2335-2345) and PAM
  modules (`pam_template`, meson.build:2351-2357), which link
  `libsystemd_static`. These are loaded into whatever process resolves
  a user or host name, or runs a PAM stack.

In PID 1 an abort doesn't end the process. The crash handler catches
SIGABRT (`SIGNALS_CRASH_HANDLER`, src/basic/constants.h:31,
src/core/crash-handler.c:198-205) and then freezes, reboots or powers
off according to `CrashAction=`, freeze by default
(crash-handler.c:36-57).

`assert_return()` (src/basic/assert-util.h:12-21) calls
`log_assert_failed_return()` (src/basic/assert-util.c:49-57) when the
check fails and then returns the error. `log_assert_failed_return()`
logs at `LOG_DEBUG` and returns, unless the weak
`log_get_assert_return_is_critical()` exists and returns true. Only
libsystemd-shared defines that function. There it defaults to
`BUILD_MODE_DEVELOPER`, and NSS modules can set it with
`$SYSTEMD_ASSERT_RETURN_IS_CRITICAL`
(src/shared/log-assert-critical.c:7,18). So in libsystemd.so a failed
`assert_return()` always returns the error. In libsystemd-shared,
`-Dmode=developer` builds abort and `-Dmode=release` builds return it.
Either way it's the C code's decision. The man pages document the
result, e.g. `-EINVAL` "Specified parameter is invalid." in
man/sd_bus_message_append_basic.xml.

## Reproducer

    ./23-panic-aborts-host/run.sh

It first greps how we build Rust code:

    # rustc 1.99.1 (58cf8f9c3 2026-10-13)
    # gcc (Debian 16.2.0-1) 16.2.0
    # x86_64 7.1.13+deb14-amd64

    $ grep -n -B2 -E "'-C(overflow-checks=yes|panic=abort)'" $SYSTEMD_SRC/meson.build
    477-                # rustc's default depends on the optimization level. C code in systemd checks its arithmetic
    478-                # where it matters, Rust code does not get to wrap silently either.
    479:                '-Coverflow-checks=yes',
    480-                # Unwinding could not cross the C frames of an event loop anyway, and without std there is no
    481-                # unwinder.
    482:                '-Cpanic=abort',

lib.rs is a no_std staticlib built with these flags. It has four
`extern "C"` functions, none of which panics explicitly:

- `rust_get_byte()` indexes a slice.
- `rust_set_id()` uses `copy_from_slice()`.
- `rust_find()` calls `position().unwrap()`.
- `rust_usec_add()` adds two `u64`.

Its panic handler logs and aborts, like
src/rust/systemd-shared/panic.rs. main.c calls each function with one
bad argument and prints "caller still running" afterwards, which it
never gets to:

    $ ./main index
    rust: panicked at 23-panic-aborts-host/lib.rs:16: index out of bounds: the len is 4 but the index is 4
    23-panic-aborts-host/../common.sh: line 39: 48982 Aborted                    (core dumped) ./main index
    [exit status 134]
    caller killed by SIGABRT

    $ ./main copy
    rust: panicked at 23-panic-aborts-host/lib.rs:22: copy_from_slice: source slice length (4) does not match destination slice length (16)
    23-panic-aborts-host/../common.sh: line 39: 48989 Aborted                    (core dumped) ./main copy
    [exit status 134]
    caller killed by SIGABRT

    $ ./main unwrap
    rust: panicked at 23-panic-aborts-host/lib.rs:29: called `Option::unwrap()` on a `None` value
    23-panic-aborts-host/../common.sh: line 39: 48998 Aborted                    (core dumped) ./main unwrap
    [exit status 134]
    caller killed by SIGABRT

    $ ./main overflow
    rust: panicked at 23-panic-aborts-host/lib.rs:35: attempt to add with overflow
    23-panic-aborts-host/../common.sh: line 39: 49011 Aborted                    (core dumped) ./main overflow
    [exit status 134]
    caller killed by SIGABRT

handler.rs has a panic handler that returns, so that the `extern "C"`
function could go on and return `-EINVAL`. rustc doesn't accept it:

    $ rustc +1.99.1 --edition 2021 --crate-type staticlib -C panic=abort -C overflow-checks=yes -O 23-panic-aborts-host/handler.rs -o libhandler.a
    error[E0308]: `#[panic_handler]` function has wrong type
     --> 23-panic-aborts-host/handler.rs:5:41
      |
    5 | fn panic(_: &core::panic::PanicInfo<'_>) {}
      |                                         ^ expected `!`, found `()`
      |
      = note: expected signature `for<'a, 'b> fn(&'a PanicInfo<'b>) -> !`
                 found signature `for<'a, 'b> fn(&'a PanicInfo<'b>) -> ()`
    [...]
    [exit status 1]

Building lib.rs with `-C panic=unwind` fails because there's no
unwinding without std:

    $ rustc +1.99.1 --edition 2021 --crate-type staticlib -C panic=unwind -O 23-panic-aborts-host/lib.rs -o libunwind.a
    error: unwinding panics are not supported without std
      |
      = help: using nightly cargo, use -Zbuild-std with panic="abort" to avoid unwinding
      = note: since the core library is usually precompiled with panic="unwind", rebuilding your crate with panic="abort" may not be enough to fix the problem
    [...]
    [exit status 1]

And `catch_unwind()` is std's. The intrinsic in core belongs to the
unstable `core_intrinsics`:

    $ grep -n -B1 'pub fn catch_unwind' $RUST_SRC/library/std/src/panic.rs
    357-#[stable(feature = "catch_unwind", since = "1.9.0")]
    358:pub fn catch_unwind<F: FnOnce() -> R + UnwindSafe, R>(f: F) -> Result<R> {
    $ grep -n -B2 'pub unsafe fn catch_unwind' $RUST_SRC/library/core/src/intrinsics/mod.rs
    2343-#[rustc_intrinsic]
    2344-#[rustc_nounwind]
    2345:pub unsafe fn catch_unwind<Data: ptr::Thin>(
    $ grep -n -A1 '^#!\[unstable' $RUST_SRC/library/core/src/intrinsics/mod.rs
    73:#![unstable(
    74-    feature = "core_intrinsics",

Then the C side. This is `assert_return()` and what it calls:

    $ grep -n -A17 '^#define assert_log' $SYSTEMD_SRC/src/basic/assert-util.h
    12:#define assert_log(expr)                                                \
    13-        (_likely_(expr) ?                                               \
    14-         true :                                                         \
    15-         (log_assert_failed_return(#expr, PROJECT_FILE, __LINE__, __func__), false))
    16-
    17-#define assert_return(expr, r)                                          \
    18-        do {                                                            \
    19-                if (!assert_log(expr))                                  \
    20-                        return (r);                                     \
    21-        } while (false)
    [...]
    $ grep -n -A8 '^void log_assert_failed_return' $SYSTEMD_SRC/src/basic/assert-util.c
    49:void log_assert_failed_return(const char *text, const char *file, int line, const char *func) {
    50-        /* log_get_assert_return_is_critical is a weak symbol. It may be NULL. */
    51-        if (log_get_assert_return_is_critical && log_get_assert_return_is_critical())
    52-                log_assert_failed(text, file, line, func);
    53-
    54-        PROTECT_ERRNO;
    55-        log_assert(LOG_DEBUG, text, file, line, func,
    56-                   "Assertion '%s' failed at %s:%u, function %s(), ignoring.");
    57-}

einval.c makes the same kind of mistake against the real libsystemd. It
calls `sd_bus_message_append()` from the installed libsystemd.so.0 with
a NULL message, so linking it needs libsystemd.so.0:

    $ grep -n -A13 '^_public_ int sd_bus_message_appendv(' $SYSTEMD_SRC/src/libsystemd/sd-bus/bus-message.c | grep assert_return
    1879-        assert_return(m, -EINVAL);
    1880-        assert_return(types, -EINVAL);
    1881-        assert_return(!m->sealed, -EPERM);
    1882-        assert_return(!m->poisoned, -ESTALE);
    $ gcc -O2 -Wall 23-panic-aborts-host/einval.c -l:libsystemd.so.0 -o einval
    [exit status 0]
    $ ./einval
    sd_bus_message_append(NULL, "s", "foo") = -22 (Invalid argument)
    caller still running
    [exit status 0]
    $ nm -D /usr/lib/x86_64-linux-gnu/libsystemd.so.0 | grep assert_return_is_critical
                     w log_get_assert_return_is_critical
    $ grep -n -E 'BUILD_MODE_DEVELOPER|SYSTEMD_ASSERT_RETURN_IS_CRITICAL' $SYSTEMD_SRC/src/shared/log-assert-critical.c
    7:static bool assert_return_is_critical = BUILD_MODE_DEVELOPER;
    18:                r = secure_getenv_bool("SYSTEMD_ASSERT_RETURN_IS_CRITICAL");
    20:                        log_debug_errno(r, "Failed to parse $SYSTEMD_ASSERT_RETURN_IS_CRITICAL, ignoring: %m");

The rest of the log is the meson.build lines listed under "Why it
matters".

## Upstream

A `#[panic_handler]` must have the type `fn(&PanicInfo) -> !`, see the
E0308 above. It can't return to the `extern "C"` function that
panicked.

Without std there's no unwinding. The `eh_personality` lang item is
missing and rustc stops with "unwinding panics are not supported
without std" (compiler/rustc_passes/src/weak_lang_items.rs:54-55,
compiler/rustc_passes/src/diagnostics.rs:188). Defining that lang item
takes the unstable `lang_items` feature.

`catch_unwind()` is std's (library/std/src/panic.rs:357-358). The
intrinsic under it (library/core/src/intrinsics/mod.rs:2343-2349)
belongs to `core_intrinsics`, which is unstable with "intrinsics are
unlikely to ever be stabilized" (intrinsics/mod.rs:73-79).

Since 1.81 a panic that tries to unwind out of an `extern "C"` function
aborts (`c_unwind`, compiler/rustc_feature/src/accepted.rs:98). So even
std code with panic=unwind needs an explicit `catch_unwind()` at every
entry point.

## Workarounds

Never panic. Use `get()`, `checked_add()`, `?` on `Option` and friends
everywhere, and check lengths before `copy_from_slice()`. clippy's
restriction lints help. With `-W clippy::indexing_slicing`,
`-W clippy::unwrap_used` and `-W clippy::arithmetic_side_effects`,
clippy 1.85 flags the index, the `unwrap()` and the addition in lib.rs,
but not the `copy_from_slice()`. That was checked by hand with
`clippy-driver` from 1.85.0 and isn't part of run.sh. Not every
panicking core function has a lint.

Check at link time that no panic path is left, e.g. with a panic
handler that calls an undefined symbol. This depends on the optimizer
removing every panic path and doesn't change what happens if one
remains. Not shown here.
