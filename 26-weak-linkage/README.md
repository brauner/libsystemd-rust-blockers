# 26. Stable Rust can't reference an optional (weak) symbol

libsystemd's C code declares two functions weak and checks their
address for NULL before calling them. So the same object works in a
linking unit that defines them and in one that doesn't. Stable Rust
(rustc 1.99.1) can't express that. `#[linkage = "extern_weak"]` is
rejected with E0658. A plain `extern` declaration is a strong
reference, and a shared library built with `-Wl,--no-undefined`, as
meson builds them, fails to link when nothing defines the symbol.

Plus, Rust assumes function pointers are never NULL. The NULL check
can't be written on a plain declaration. rustc warns that it is always
false and removes it, so weakening the symbol after compilation
(objcopy) crashes.

## Why it matters

The weak references and their providers, at main e9795a90b7:

- `log_get_assert_return_is_critical()`, declared `_weak_` in
  src/basic/assert-util.h:8 and checked in
  src/basic/assert-util.c:50-51 on every failed `assert_return()`. The
  only definition is src/shared/log-assert-critical.c:29-31. It came
  with 0bb0316f5e "Do not use "critical assert_return" in libsystemd or
  libudev", so that "libsystemd and libudev always have
  assert_return_is_critical==false, and our binaries and modules enable
  it conditionally" instead of aborting the calling program.
- `mempool_enabled()`, declared `_weak_` in src/basic/mempool.h:25 and
  checked in src/basic/hashmap.c:810 for every new hashmap. The only
  definition is src/shared/enable-mempool.c:7-17. It came with
  b01f31954f "Turn mempool_enabled() into a weak symbol": "If it's not
  found, we assume false. So it only needs to be provided for
  libsystemd-shared". The split itself goes back to a5d8835c78
  "mempool: only enable mempool use when linked to
  libsystemd-shared.so", which was to "fix assert crashes in external
  programs".

Both providers are in libshared. Which binary gets them follows from
how it links that library:

- libsystemd-shared links libshared with `link_whole`
  (src/shared/meson.build:474) and defines both.
- libsystemd.so links only libc-wrapper, libbasic and
  libsystemd_static (meson.build:2108-2125) and defines neither.
- NSS and PAM modules link libshared as an ordinary static library
  (meson.build:2335-2362). "The link editor does not extract archive
  members to resolve undefined weak symbols" (System V gABI, Symbol
  Table, STB_WEAK). NSS modules call
  `log_set_assert_return_is_critical_from_env()`
  (src/shared/nss-util.c:18), a strong reference that pulls in
  log-assert-critical.o and with it the assert hook. Nothing pulls in
  enable-mempool.o, and PAM modules pull in neither.

An older local build of v261 shows exactly that. Both are weak undefined
(`w` in `nm -D`) in libsystemd.so.0 and pam_systemd.so, and both are
defined (`W ...@@SD_SHARED`) in libsystemd-shared-261.so.
libnss_systemd.so.2 has the assert hook as a local definition and
`w mempool_enabled`.

static-destruct uses the same mechanism for section bounds.
`__start_SYSTEMD_STATIC_DESTRUCT` and `__stop_SYSTEMD_STATIC_DESTRUCT`
are `_weak_` (src/basic/static-destruct.h:80-83) "as we want this to
work even if no destructors are defined and the section is missing",
and `static_destruct_impl()` returns early when the start is NULL
(src/basic/static-destruct.c:5-7). `__start_SYSTEMD_OPTIONS` and
`__stop_SYSTEMD_OPTIONS` are weak for the same reason
(src/shared/options.h:192-199). Both are used by programs, and
libsystemd.so has no SYSTEMD_STATIC_DESTRUCT section. A Rust port would
have the same problem there, since a plain `extern static __start_X`
doesn't link when no object contributes to section X.

## Reproducer

    ./26-weak-linkage/run.sh

hook.c is the C pattern, a weak `optional_hook()` and a `report()` that
checks it for NULL. It's linked into a shared library with
`-Wl,--no-undefined` once without provider.c, like libsystemd.so, and
once with it, like libsystemd-shared. Both link, and without the
provider `optional_hook` stays weak undefined and is NULL:

    $ gcc -shared -Wl,--no-undefined -Wl,--gc-sections hook.o -o libc-without.so
    [exit status 0]
    [...]
    $ nm -D libc-without.so | grep optional_hook
                     w optional_hook
    [...]
    $ gcc main.o ./libc-without.so -o c-without && ./c-without
    C: optional_hook() not linked in
    [...]
    $ gcc main.o ./libc-with.so -o c-with && ./c-with
    C: optional_hook() linked in, returns 1

weak.rs is the same in Rust with `#[linkage = "extern_weak"]`. Stable
rustc rejects it:

    $ rustc +1.99.1 ... 26-weak-linkage/weak.rs -o x.a
    error[E0658]: the `linkage` attribute is experimental and not portable across platforms
     --> 26-weak-linkage/weak.rs:7:7
    [...]
      = note: see issue #29603 <https://github.com/rust-lang/rust/issues/29603> for more information

hook.rs uses a plain `extern` declaration. rustc warns about its NULL
check, and the library only links with provider.o:

    $ rustc +1.99.1 ... 26-weak-linkage/hook.rs -o libhook.a
    warning: function pointers are not nullable, so checking them for null will always return false
      --> 26-weak-linkage/hook.rs:14:8
    [...]
    $ gcc -shared -Wl,--no-undefined -Wl,--gc-sections -Wl,-u,report libhook.a -o librust-without.so
    /usr/bin/x86_64-linux-gnu-ld.bfd: libhook.a(libhook.hook.bb33a161961ae370-cgu.0.rcgu.o): in function `report':
    hook.bb33a161961ae370-cgu.0:(.text.report+0x3): undefined reference to `optional_hook'
    collect2: error: ld returned 1 exit status
    [exit status 1]

Weakening the reference with objcopy makes it link, and crash.
`report()` calls `optional_hook` without checking it first:

    $ objcopy --weaken-symbol=optional_hook libhook.a libhook-weak.a
    [...]
    $ objdump -d --no-show-raw-insn -M intel --disassemble=report librust-weak.so | grep -A3 '<report>:'
    0000000000001100 <report>:
        1100:	push   rax
        1101:	call   QWORD PTR [rip+0x2ec9]        # 3fd0 <optional_hook>
        1107:	movzx  esi,al
    [...]
    $ gcc main.o ./librust-weak.so -o rust-weak && ./rust-weak
    26-weak-linkage/../common.sh: line 39: 25889 Segmentation fault         (core dumped) ./rust-weak
    [exit status 139]

Built with `RUSTC_BOOTSTRAP=1`, only to show that the feature exists,
weak.rs behaves like the C version:

    $ RUSTC_BOOTSTRAP=1 rustc +1.99.1 ... -Zcrate-attr='feature(linkage)' 26-weak-linkage/weak.rs -o libweak.a
    [exit status 0]
    [...]
    $ gcc main.o ./librust-nightly.so -o rust-nightly && ./rust-nightly
    Rust: optional_hook() not linked in

## Upstream

The attribute is behind feature `linkage`
(compiler/rustc_feature/src/unstable.rs:315-316), tracking issue
rust-lang/rust#29603, open since 2015-11-05. As of 2026-09-28 people on
the tracking issue are preparing an RFC, and bjorn3 lists platforms
where weak symbols don't work well (MSVC and MinGW Windows, Apple).
rust-lang/rust#163405 (merged 2026-10-02) removed some `#[linkage]`
values. `extern_weak` remains
(compiler/rustc_attr_parsing/src/attributes/link_attrs.rs:688).
rust-lang/rust#137627 (open) is a bug in how `extern_weak` is checked.

std relies on the attribute itself on Linux, in
library/std/src/sys/pal/unix/weak/weak_linkage.rs:9 and
library/std/src/sys/thread_local/destructors/linux_like.rs:28-30.

Nothing stable replaces it. Defining a weak symbol,
`#[linkage = "weak"]`, is behind the same feature.

## Workarounds

Keep the weak reference in C and let Rust call a C helper that returns
the hook's result, or false if it is NULL. That costs a C file per hook
and a call that doesn't inline without cross-language LTO.

Replace "linked in or not" with explicit registration. Then
libsystemd-shared would call a setter at startup that turns the mempool
or critical assert_return on. That changes how the defaults come about,
and every program and module has to make that call before its first
hashmap.

For section bounds, make sure each linking unit has at least one entry,
so that `__start_`/`__stop_` always exist and can be strong references.
The walker then has to skip the dummy entry.
