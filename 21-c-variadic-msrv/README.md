# 21. No C-variadic definitions at the 1.85 MSRV, and no `long double` on 1.99

libsystemd's public API has 62 exported functions that are C-variadic or
take a `va_list`. Defining a C-variadic function in Rust, and using
`core::ffi::VaList`, has only been stable since Rust 1.99.0. Our MSRV is
1.85, which rejects both.

On 1.99.1 C-variadic definitions work, with mixed argument types, with
a `VaList` passed on to `vsnprintf()` and with `va_copy()` as
`VaList::clone()`. One part is still missing. None of the types
`VaList::next_arg()` accepts on stable is a C `long double`, except
where `long double` is just `double` (e.g. 32-bit arm). On x86_64 no
Rust release has one, nightly included, and `sd_journal_send()` needs it
to step over the argument of a `%Lf`.

## Why it matters

The 17 installed headers (src/systemd/meson.build:3-21, main e9795a90b7)
declare 46 C-variadic functions and 16 functions that take a `va_list`.
clang counts them from the AST, so macros are left out. Among them are:

- C-variadic: `sd_bus_message_append()`, `sd_bus_call_method()`,
  `sd_bus_error_setf()`, `sd_json_build()`, `sd_journal_print()`,
  `sd_journal_send()`, `sd_notifyf()` and the `sd_varlink_*b()` family
- `va_list`: `sd_bus_message_appendv()`, `sd_bus_message_readv()`,
  `sd_json_buildv()`, `sd_journal_printv()`, `sd_varlink_callb_ap()`

All 62 are exported by src/libsystemd/libsystemd.sym. Two more,
`sd_id128_in_set_sentinel()` and `sd_id128_in_setv()`, are static inline
in sd-id128.h, so the caller compiles them. That's just as well since
they read an `sd_id128_t` union by value (sd-id128.h:137) and
`VaArgSafe` admits no non-scalar types. The headers that aren't
installed add one more, `sd_future_group_add_many_internal()`
(sd-future.h).

`sd_journal_send()` and `sd_journal_send_with_location()` take
`printf()`-style format strings, each followed by its arguments and
terminated by NULL (src/libsystemd/sd-journal/journal-send.c:195,512).
`fill_iovec_sprintf()` formats each one from a `va_copy()`. To find the
next format string it then steps over the arguments of the current one
with `VA_FORMAT_ADVANCE()` (journal-send.c:180). That macro
(src/basic/stdio-util.h:26-72) reads one argument per conversion by its
type, a `long double` for `%Lf` (stdio-util.h:66).

## Reproducer

    ./21-c-variadic-msrv/run.sh

It needs `$CLANG` and jq, and network access for the last step. The log
was recorded with clang 21.1.8.

First it builds a translation unit from the installed headers and one
from all of src/systemd/*.h and dumps clang's AST as JSON. count.jq
picks every `sd_*()` function declaration that is variadic or has a
`va_list` parameter. The `va_list` type comes from a probe declaration
because `va_list` decays to an architecture-specific pointer type. The
extern functions are then checked against libsystemd.sym:

    # rustc 1.99.1 (58cf8f9c3 2026-10-13)
    # gcc (Debian 16.2.0-1) 16.2.0
    # x86_64 7.1.13+deb14-amd64

    $ wc -l < public.h.list
    17
    $ clang -fsyntax-only -Xclang -ast-dump=json -I$SYSTEMD_SRC/src/systemd public.c | jq -r -f 21-c-variadic-msrv/count.jq | sort -u > public.txt
    [exit status 0]
    $ cut -d' ' -f2,3 public.txt | sort | uniq -c
         16 va_list extern
          1 va_list inline
         46 variadic extern
          1 variadic inline
    $ grep ' extern$' public.txt | cut -d' ' -f1 | sort | comm -12 - exported.txt | wc -l
    62

all.c includes the private _sd-common.h directly, which clang reports as
an error. It still dumps the AST, and the headers that aren't installed
add one function:

    $ clang -fsyntax-only -Xclang -ast-dump=json all.c | jq -r -f 21-c-variadic-msrv/count.jq | sort -u > all.txt
    In file included from all.c:1:
    $SYSTEMD_SRC/src/systemd/_sd-common.h:30:4: error: "Do not include _sd-common.h directly; it is a private header."
    [...]
    $ comm -13 public.txt all.txt
    sd_future_group_add_many_internal variadic extern

variadic.rs defines three functions. `rust_append()` takes one argument
per type character, like `sd_bus_message_append()` with `"ysbtdi"`.
`rust_printv()` takes a `va_list` from C and passes it to `vsnprintf()`
twice, the first time as a copy. `rust_print()` is C-variadic and passes
its arguments on to `vsnprintf()`. Our MSRV rejects all of it:

    $ rustc +1.85.0 --edition 2021 --crate-type staticlib -C panic=abort -O 21-c-variadic-msrv/variadic.rs -o libvariadic.a 2>&1 | tee old.err
    error[E0658]: C-variadic functions are unstable
      --> 21-c-variadic-msrv/variadic.rs:13:1
    [...]
       = note: see issue #44930 <https://github.com/rust-lang/rust/issues/44930> for more information
    [...]
    error[E0658]: use of unstable library feature `c_variadic`: the `c_variadic` feature has not been properly tested on all supported platforms
     --> 21-c-variadic-msrv/variadic.rs:4:42
      |
    4 | use core::ffi::{c_char, c_double, c_int, VaList};
      |                                          ^^^^^^
    [...]
    error[E0107]: struct takes 2 lifetime arguments but 1 lifetime argument was supplied
    [...]
    error[E0599]: no method named `next_arg` found for struct `VaListImpl` in the current scope
    [...]
    error: aborting due to 11 previous errors
    [...]
    [exit status 1]

The E0107 and E0599 errors show that 1.85 had a different unstable API
(`VaListImpl`, `VaList<'a, 'f>`, `arg()`). So code written against it
wouldn't build unchanged on 1.99 either.

1.99.1 builds it, and the output of main.c matches expected.txt:

    $ rustc +1.99.1 --edition 2021 --crate-type staticlib -C panic=abort -O 21-c-variadic-msrv/variadic.rs -o libvariadic.a
    [exit status 0]
    $ ./variadic | tee out.txt
    rust_append: 7 foo 1 18446744073709551615 2.5 -42
    rust_printv: bar=-1 0.5 1099511627776 | bar=-1 0.5 1099511627776
    rust_print:  baz=3 1.5 2199023255552
    $ diff -u 21-c-variadic-msrv/expected.txt out.txt
    [exit status 0]

long-double.rs tries to read an `f128` from a `VaList`, which 1.99.1
rejects:

    $ rustc +1.99.1 --edition 2021 --crate-type lib --emit=metadata -o long-double.rmeta 21-c-variadic-msrv/long-double.rs
    error[E0658]: the type `f128` is unstable
     --> 21-c-variadic-msrv/long-double.rs:7:36
    [...]
      = note: see issue #116909 <https://github.com/rust-lang/rust/issues/116909> for more information

    error[E0277]: the trait bound `f128: VaArgSafe` is not satisfied
    [...]
        = help: the following other types implement trait `VaArgSafe`:
                  f64
                  i128
                  i32
                  i64
                  isize
                  u128
                  u32
                  u64
                  usize
    [...]
    $ grep -rn 'long double' $RUST_SRC/library/core/src/ffi
    $RUST_SRC/library/core/src/ffi/va_list.rs:422:// - `long double` is IEEE f128 on the platform.

`*const T` and `*mut T` implement `VaArgSafe` as well, but the list
leaves out generic impls. None of these types is a C `long double`, and
`core::ffi` has no `c_longdouble`.

send.rs and send.c, x86_64 only, run the loop of `sd_journal_send()` in
C and in Rust with `"A=%Lf", 1.0L, "B=%Lf", 2.0L, "C=%Lf", 3.0L, NULL`.
The Rust version steps over each `long double` in one of three ways:

- as an `f64`
- as two `u64`, 16 bytes like a `long double` on x86_64
- with a C helper that does `va_arg(*ap, long double)`

The first two break `next_arg()`'s safety contract on purpose, because
no `VaArgSafe` type is a `long double`. This is what happens when a
`long double` comes from C anyway:

    $ ./send | tee send.out
    C:              A=1.000000 B=2.000000 C=3.000000
    Rust, f64:      A=1.000000 B=1.000000 C=1.000000
    Rust, 2 x u64:  A=1.000000
    Rust, C helper: A=1.000000 B=2.000000 C=3.000000

On x86_64 a `long double` is passed in memory. An `f64` is read from the
SSE register save area, so the copy for the next field still points at
the first `long double`. Two `u64` are read from the general purpose
registers and consume the pointers to the next format strings.

Last, where our MSRV comes from, the release that made C-variadic
definitions stable, and which rustc Debian ships according to madison
on 2026-10-26:

    $ grep -n -B2 "^rust_msrv = " $SYSTEMD_SRC/meson.build
    378-# The oldest rustc we support. Also handed to bindgen, so that the generated bindings never require a
    379-# newer compiler than the hand-written code does.
    380:rust_msrv = '1.85'
    $ git -C $SYSTEMD_SRC log -1 --format='%h %s%n%n%b' -S"rust_msrv = '1.85'" -- meson.build | grep -B1 -A1 'Debian 13'
    The option is a feature and defaults to auto. We need rustc >= 1.85 and
    bindgen >= 0.71.1 which is exactly what Debian 13 ships. 1.85 is the
    minimum supported Rust version and we hand it to bindgen as well so the
    $ grep -n 'Debian 13' $SYSTEMD_SRC/docs/HACKING.md
    109:apt install rustc bindgen rustfmt rust-clippy   # Debian 13
    258:  with the oldest supported one (on Debian 13).
    $ grep -n 'c_variadic' $RUST_SRC/compiler/rustc_feature/src/accepted.rs
    100:    (accepted, c_variadic, "1.99.0", Some(44930)),
    103:    (accepted, c_variadic_naked_functions, "1.99.0", Some(148767)),
    $ curl -s -m 30 'https://qa.debian.org/madison.php?package=rustc&text=on'
     rustc | 1.48.0+dfsg1-2         | bullseye         | source, amd64, arm64, armhf, i386
     rustc | 1.63.0+dfsg1-2         | bookworm         | source, amd64, arm64, armel, armhf, i386, mips64el, mipsel, ppc64el, s390x
     rustc | 1.85.1+dfsg1-1+deb13u1 | trixie           | source, amd64, arm64, armel, armhf, i386, ppc64el, riscv64, s390x
     rustc | 1.93.1+dfsg1-2~bpo13+1 | trixie-backports | source
     rustc | 1.94.1+dfsg1-1~bpo13+3 | trixie-backports | source
     rustc | 1.95.0+dfsg1-2~bpo13+1 | trixie-backports | source, armel
     rustc | 1.96.1+dfsg1-2~bpo13+1 | trixie-backports | source, amd64, arm64, armhf, i386, ppc64el, riscv64, s390x
     rustc | 1.97.1+dfsg1-1         | forky            | source, amd64, arm64, armhf, i386, loong64, ppc64el, riscv64, s390x
     rustc | 1.97.1+dfsg1-1         | sid              | source, amd64, arm64, armhf, i386, loong64, ppc64el, riscv64, s390x
     rustc | 1.98.1+dfsg1-1~exp1    | experimental     | source, amd64, arm64, armhf, i386, loong64, ppc64el, s390x

So the MSRV is the rustc of Debian 13 (trixie), and our CI builds the
Rust code with that oldest supported toolchain (docs/HACKING.md:257-258,
commit 770c05374e). On 2026-10-26 no Debian suite, not even unstable or
experimental, ships a rustc on which C-variadic definitions are stable.

## Upstream

C-variadic definitions (`c_variadic`, RFC 2137, rust-lang/rust#44930,
closed) were stabilized by rust-lang/rust#155697, merged on 2026-07-22
with milestone 1.99.0:

- compiler/rustc_feature/src/accepted.rs:100
- `VaList` is `#[stable(feature = "c_variadic", since = "1.99.0")]` in
  library/core/src/ffi/va_list.rs:221
- `next_arg()` is at va_list.rs:538, `Clone` (`va_copy`) at
  va_list.rs:242-256

Definitions are stable on x86, x86_64, aarch64, arm, powerpc, powerpc64,
riscv32/64, s390x, loongarch, mips and sparc64, among others. m68k and
32-bit sparc still need the unstable `c_variadic_experimental_arch`
(rust-lang/rust#155973, open), see
compiler/rustc_target/src/spec/mod.rs:2086-2137.

`VaArgSafe` is sealed (`pub impl(self) unsafe trait`, va_list.rs:313).
va_list.rs:307-309 says the `va_arg` implementations "don't support
types with a non-scalar layout" and that "Inline assembly can be used to
accept unsupported types in the meantime". It's implemented for `c_int`,
`c_long`, `c_longlong`, their unsigned versions, `c_double` and raw
pointers. `i128`/`u128` are gated by `c_variadic_int128`
(rust-lang/rust#155752, open). Naming the trait in bounds is unstable
(`c_variadic_va_arg_safe`, rust-lang/rust#162911, open).

`f128` is only implemented where clang has `__float128` or `long double`
is IEEE binary128 (va_list.rs:419-466). That impl and the `f128` type
itself are unstable (rust-lang/rust#116909, open). On x86_64 and i386
`long double` is the 80-bit x87 type, for which Rust has no type at all.
On x86_64 `f128` is `__float128`, which is a different type from
`long double` and is passed in a different way. On powerpc
`long double` is IBM double-double, and `ppcf128` is unstable
(rust-lang/rust#163323, open).

## Workarounds

Keep the C-variadic entry points in C and have them call Rust with
ordinary arguments. A `va_list` can't be handed to Rust on 1.85 either
since `core::ffi::VaList` fails with the same E0658 (variadic.rs:4:42
above). So all argument parsing would have to stay in C.

Raise the MSRV to 1.99. No Debian release can build that with its own
rustc today. trixie-backports has 1.96.1 and unstable has 1.97.1.

For `long double`, call a C helper that steps over one argument with
`&mut VaList`, like send.c does for "Rust, C helper" above:

    void skip_long_double(va_list *ap) {
            (void) va_arg(*ap, long double);
    }

Keeping `VA_FORMAT_ADVANCE()` in C works the same way. Upstream's own
suggestion is inline assembly, which has to be written per architecture.
