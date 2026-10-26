# 22. The `alloc` crate aborts on allocation failure, libsystemd returns `-ENOMEM`

libsystemd's API contract is to report a failed allocation to the caller
as `-ENOMEM`. Rust's `alloc` crate can't do that. When `Box::new()`,
`Vec::push()`, `collect()`, `format!()` or `String` growth fail to
allocate, they call `handle_alloc_error()`. In a `#![no_std]` program
that calls the panic handler, which can't return. With a handler that
aborts, like ours, the process that called into the library dies with
SIGABRT.

Apart from the raw `alloc::alloc::alloc()`, which returns a null
pointer, `try_reserve()` and `try_reserve_exact()` (since 1.57) are the
only stable fallible allocation APIs. `Box::try_new()` and
`Vec::push_within_capacity()` are unstable on 1.99.1, and
`Vec::try_push()` doesn't exist. The `Allocator` stabilization in 1.100
doesn't change any of this.

## Why it matters

In src/libsystemd (main e9795a90b7) there are 373 `return -ENOMEM` and
52 `log_oom()`-style calls, and `log_oom()` logs and returns `-ENOMEM`
too. 62 of the 177 man/sd*.xml pages list `-ENOMEM`, and others include
such a list. For example the Return Value section of
`sd_bus_message_append(3)` (man/sd_bus_message_append.xml:217-222)
includes the error list of man/sd_bus_message_append_basic.xml:239-241,
"Memory allocation failed."

The process that aborts is whatever program called into libsystemd.
PID 1 and the daemons carry libsystemd's code through libsystemd-shared,
see 23.

## Reproducer

    ./22-fallible-allocation/run.sh

It starts with the numbers above:

    # rustc 1.99.1 (58cf8f9c3 2026-10-13)
    # gcc (Debian 16.2.0-1) 16.2.0
    # x86_64 7.1.13+deb14-amd64

    $ git -C $SYSTEMD_SRC grep -o 'return -ENOMEM' -- src/libsystemd | wc -l
    373
    $ git -C $SYSTEMD_SRC grep -o -E '[a-z_]*log_oom[a-z_]*\(' -- src/libsystemd | sed 's/.*://' | sort | uniq -c
          8 json_log_oom(
         17 log_oom(
         27 log_oom_debug(
    $ git -C $SYSTEMD_SRC grep -l -e '-ENOMEM' -- 'man/sd*.xml' | wc -l
    62
    $ grep -n 'xpointer="errors"' $SYSTEMD_SRC/man/sd_bus_message_append.xml
    222:    <xi:include href="sd_bus_message_append_basic.xml" xpointer="errors" />
    $ grep -n -A2 '<constant>-ENOMEM</constant>' $SYSTEMD_SRC/man/sd_bus_message_append_basic.xml
    239:          <term><constant>-ENOMEM</constant></term>
    240-
    241-          <listitem><para>Memory allocation failed.</para></listitem>

join.rs is a no_std staticlib with `extern crate alloc`. Its
`#[global_allocator]` is `malloc()`/`free()`, and its panic handler logs
and calls `abort()` like ours does (src/rust/systemd-shared/panic.rs).
It has two functions that build `"systemd0 systemd1 ..."` and return
its length or a negative errno. `rust_join()` uses `format!()`,
`collect()` and `join()`. `rust_join_try_reserve()` calls
`String::try_reserve()` before every write. main.c has the same
function in C, `c_join()`, which grows its buffer with `realloc()` and
returns `-ENOMEM` on failure.

main.c calls one of the three, first with n=3 and then with n=10000000
under `ulimit -v 102400` (100 MiB of address space) so that `malloc()`
returns NULL. With enough memory all three agree:

    $ ./join c_join 3
    c_join(n=3) = 26
    caller still running
    $ ./join rust_join 3
    rust_join(n=3) = 26
    caller still running
    $ ./join rust_join_try_reserve 3
    rust_join_try_reserve(n=3) = 26
    caller still running

When `malloc()` fails, `c_join()` and `rust_join_try_reserve()` return
`-ENOMEM` and `rust_join()` takes its caller down:

    $ (ulimit -v 102400; ./join c_join 10000000)
    c_join(n=10000000) = -12 (Cannot allocate memory)
    caller still running
    [exit status 0]

    $ (ulimit -v 102400; ./join rust_join_try_reserve 10000000)
    rust_join_try_reserve(n=10000000) = -12 (Cannot allocate memory)
    caller still running
    [exit status 0]

    $ (ulimit -v 102400; ./join rust_join 10000000)
    rust: memory allocation of 240000000 bytes failed
    22-fallible-allocation/../common.sh: line 39: 24436 Aborted                    (core dumped) ( ulimit -v 102400; ./join rust_join 10000000 )
    [exit status 134]
    rust_join() caller killed by SIGABRT

try.rs uses `Box::try_new()`, `Vec::push_within_capacity()` and
`Vec::try_push()`:

    $ rustc +1.99.1 --edition 2021 --crate-type lib --emit=metadata -o try.rmeta 22-fallible-allocation/try.rs 2>&1 | tee try.err
    error[E0658]: use of unstable library feature `allocator_api`
      --> 22-fallible-allocation/try.rs:10:13
    [...]
       = note: see issue #32838 <https://github.com/rust-lang/rust/issues/32838> for more information

    error[E0658]: use of unstable library feature `vec_push_within_capacity`
      --> 22-fallible-allocation/try.rs:11:15
    [...]
       = note: see issue #100486 <https://github.com/rust-lang/rust/issues/100486> for more information

    error[E0599]: no method named `try_push` found for mutable reference `&mut Vec<u64>` in the current scope
      --> 22-fallible-allocation/try.rs:12:15
    [...]
    [exit status 1]

Then it greps where an allocation failure goes in alloc and what 1.100
stabilizes, at rust-lang/rust 846e51f66b1:

    $ grep -n -A3 '^const fn handle_error' $RUST_SRC/library/alloc/src/raw_vec/mod.rs
    926:const fn handle_error(e: TryReserveError) -> ! {
    927-    match e.kind() {
    928-        CapacityOverflow => capacity_overflow(),
    929-        AllocError { layout, .. } => handle_alloc_error(layout),
    $ grep -n -A6 'pub unsafe fn __rdl_alloc_error_handler' $RUST_SRC/library/alloc/src/alloc.rs
    698:    pub unsafe fn __rdl_alloc_error_handler(size: usize, _align: usize) -> ! {
    699-        core::panicking::panic_nounwind_fmt(
    700-            format_args!("memory allocation of {size} bytes failed"),
    [...]
    $ grep -n -B4 -E 'pub fn (try_new|new_in)\(x: T' $RUST_SRC/library/alloc/src/boxed.rs
    [...]
    460-    #[unstable(feature = "allocator_ext", issue = "163177", implied_by = "allocator_api")]
    461-    #[inline]
    462:    pub fn try_new(x: T) -> Result<Self, AllocError> {
    --
    529-    #[cfg(not(no_global_oom_handling))]
    530-    #[stable(feature = "allocator_api", since = "1.100.0")]
    531-    #[must_use]
    532-    #[inline]
    533:    pub fn new_in(x: T, alloc: A) -> Self {

Last, it tries `-Zoom=panic` on 1.85.0 and 1.99.1. `RUSTC_BOOTSTRAP=1`
is only there to show that the unstable flag existed and is gone now.
Then it finds the merge that removed it:

    $ RUSTC_BOOTSTRAP=1 rustc +1.85.0 -Zoom=panic --crate-type lib --emit=metadata -o empty.rmeta empty.rs
    [exit status 0]
    $ RUSTC_BOOTSTRAP=1 rustc +1.99.1 -Zoom=panic --crate-type lib --emit=metadata -o empty.rmeta empty.rs
    error: unknown unstable option: `oom`

    [exit status 1]
    $ git -C $RUST_SRC show -s --date=short --format='%h %cd %s%n%b' 377656d3dd3 | grep -E 'Auto merge|Zoom'
    377656d3dd3 2025-12-10 Auto merge of #149836 - matthiaskrgr:rollup-1ypvt7r, r=matthiaskrgr
     - rust-lang/rust#147725 (Remove -Zoom=panic)
    $ git -C $RUST_SRC show 377656d3dd3:src/version
    1.94.0

## Upstream

`handle_alloc_error()` (library/alloc/src/alloc.rs:639-689) is
documented to call `panic!` when the program doesn't link std
(alloc.rs:656-658). A failed `Vec` growth ends up there too
(raw_vec/mod.rs:926-931). The default handler panics with
`panic_nounwind_fmt()` (alloc.rs:694-704), so it doesn't unwind even
under panic=unwind. A panic handler must return `!`.
`#[alloc_error_handler]` is unstable (rust-lang/rust#51540, open,
compiler/rustc_feature/src/unstable.rs:374), and it would have to
diverge too.

On 1.99.1 `Box::try_new()` is unstable under `allocator_api`
(rust-lang/rust#32838). That issue was closed on 2026-09-23, when
rust-lang/rust#156882 stabilized `Allocator` for 1.100.0. That PR moved
`try_new()`, `try_new_in()` and the other fallible constructors to the
new unstable feature `allocator_ext` (rust-lang/rust#163177, open,
library/alloc/src/boxed.rs:460-462, 558-560, and
`Vec::try_with_capacity_in()` at vec/mod.rs:1043-1045). What 1.100
makes stable is the `Allocator` trait and infallible constructors like
`Box::new_in()` (boxed.rs:529-533). Those are still compiled out under
`no_global_oom_handling` and abort on failure. A custom `Allocator` that
returns `Err` still ends up in `handle_alloc_error()` through `push()`.

`Vec::push_within_capacity()` is unstable (rust-lang/rust#100486, open,
vec/mod.rs:2792-2793). So are `Vec::try_with_capacity()`,
`String::try_with_capacity()` and `VecDeque::try_with_capacity()`
(rust-lang/rust#91913, open, vec/mod.rs:545-546). `Vec::try_push()`
doesn't exist. `try_reserve()` and `try_reserve_exact()` on `Vec`,
`String` and `VecDeque` have been stable since 1.57
(vec/mod.rs:1443-1444, string.rs:1347-1348). `push()`, `extend()`,
`insert()`, `collect()`, `format!()`, `to_string()`, `clone()`,
`Box::new()`, `Rc::new()` and `Arc::new()` have no stable fallible
variants.

`-Zoom=panic` was a nightly-only flag (RFC 2116, tracking issue
rust-lang/rust#43596, closed). rust-lang/rust#147725 ("Remove
-Zoom=panic") removed it. It was merged in 377656d3dd3 on 2025-12-10,
whose src/version is 1.94.0. RELEASES.md has no entry because the flag
was never stable. With panic=abort it would only have turned the abort
into a panic, which aborts as well.

alloc has a `no_global_oom_handling` cfg that removes the infallible
APIs (e.g. boxed.rs:529). It only takes effect when alloc itself is
compiled with it, i.e. built from source, which a stable toolchain
doesn't support.

## Workarounds

Call `try_reserve()` before every growth, like
`rust_join_try_reserve()` above. That works on stable and returns
`-ENOMEM`, but only for growing a `Vec`, `String` or `VecDeque`. Every
other allocation in alloc (`Box::new()`, `format!()`, `collect()`,
`join()`, `to_string()`, `clone()`, `Rc`, `Arc`, `BTreeMap` inserts)
still aborts. Nothing checks that every growth is preceded by a
reservation, and the abort paths stay in the binary.

Or don't use alloc at all, which is what our own Rust code does.
src/rust/systemd-shared/alloc.rs (619 lines) has its own `Box` and `Vec`
on top of `malloc()`. Everything that allocates returns a `Result` with
an `AllocError` that converts into `-ENOMEM` (alloc.rs:3-10). It also
has its own copy of the 1.100 `Allocator` trait, "spelled out because
the tree's floor is 1.85" (alloc.rs:54-57). The cost is reimplementing
every container and the string formatting (`cstr::try_format()`)
instead of using alloc's, and no crate built on alloc can be used.
