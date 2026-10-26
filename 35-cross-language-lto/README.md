# 35. No LTO across the C/Rust boundary in the toolchains distros use

(a) Distros build systemd with GCC and LTO. GCC's LTO works on GIMPLE
and rustc emits machine code or LLVM bitcode, so neither side can inline
into the other. Every call from C into Rust and from Rust into C stays a
real call. A C `static inline` helper is only reachable from Rust
through an out-of-line trampoline, and Rust calls that trampoline at
every use.

(b) Cross-language LTO exists, but only with LLVM on both sides
(`-C linker-plugin-lto`) and only if the linker's LLVM is at least as
new as every compiler's. rustc 1.99.1 emits LLVM 23 bitcode, which
ld.lld 21 and the LLVMgold plugin from clang 21 reject. rustc's own
rust-lld (LLVM 23) links it and inlines across the boundary. Our MSRV
1.85 (LLVM 19) works with clang 21.

(c) Since 1.90, rustc links `x86_64-unknown-linux-gnu` programs with the
bundled rust-lld, which can't read GCC's LTO objects. A Rust program
linking a static C library built with `gcc -flto` fails with "undefined
symbol". 1.85 links it with cc and ld.bfd.

## Why it matters

The distros turn on LTO for systemd like this:

- Debian's and Ubuntu's systemd packaging sets
  `DEB_BUILD_MAINT_OPTIONS = optimize=+lto` (debian/rules:54 on salsa
  debian/master, :57 in Ubuntu 259.5-0ubuntu3.4). That makes
  dpkg-buildflags add `-flto=auto -ffat-lto-objects`.
- Fedora's systemd.spec enables `%bcond lto` (lines 31-32) and
  redhat-rpm-config passes `-flto=auto -ffat-lto-objects` (macros:428).
- Arch passes `LTOFLAGS="-flto=auto"` with `lto` in `OPTIONS`
  (makepkg.conf:52, 101).

libsystemd.so itself would be linked by gcc (meson.build:2108), so (a)
applies. Rust code in libsystemd that uses the 673 `static inline`
helpers of src/fundamental, src/basic, src/libsystemd and src/systemd
(see 36) calls a trampoline each time, and every C caller of Rust code
pays for a call.

Our Rust programs are linked by rustc (meson.build:2283-2303), so (c)
applies to any static C library they link. We already build our
trampoline archive with `-fno-lto` for this reason. The comment in
src/rust/systemd-shared/meson.build:115-120 says "The archive is
consumed by rustc's linker, which cannot read GCC LTO bytecode, hence
never build it with -flto".

For (b), clang's default triple (`x86_64-pc-linux-gnu` on Debian)
differs from rustc's (`x86_64-unknown-linux-gnu`). lld warns about that
and with our `-Wl,--fatal-warnings` (meson.build:628) the link fails.
Passing `--target=x86_64-unknown-linux-gnu` to clang avoids it.

## Reproducer

    ./35-cross-language-lto/run.sh

count.c and rs.rs count the empty strings of an array, in C and in
Rust. Both use `isempty()` from h.h, a copy of our helper, and lib.c
calls both. bindgen generates the Rust declarations and the C
trampoline for `isempty()` like our build does
(src/rust/systemd-shared/meson.build:54):

    # rustc 1.99.1 (58cf8f9c3 2026-10-13)
    # gcc (Debian 16.2.0-1) 16.2.0
    [...]
    $ clang --version | head -1
    Debian clang version 21.1.8 (10)
    [exit status 0]

    $ $BINDGEN --version
    bindgen 0.72.1
    [exit status 0]

    $ $BINDGEN --use-core --ctypes-prefix core::ffi --wrap-static-fns --wrap-static-fns-path wrap --allowlist-function isempty 35-cross-language-lto/h.h -o h.rs
    [exit status 0]

    $ tail -1 wrap.c
    bool isempty__extern(const char *a) { return isempty(a); }
    [exit status 0]

(a) builds the library with gcc and `-flto=auto -ffat-lto-objects`.
`c_count_empty()` from the other C file and its `isempty()` calls are
inlined into `count_both()`. The Rust function is called, and it calls
the 6 instruction trampoline once per element:

    $ gcc -O2 -fPIC -fvisibility=hidden -flto=auto -ffat-lto-objects [...] lib.o count.o wrap.o librs.a -o libgcc.so
    [exit status 0]

    $ disas libgcc.so count_both | grep call
        1167:	call   11c0 <rs_count_empty>
        1180:	call   11c0 <rs_count_empty>
    [exit status 0]

    $ disas libgcc.so rs_count_empty | grep -E 'call|isempty'
        11d6:	lea    -0x4d(%rip),%r12        # 1190 <isempty__extern>
        11e4:	call   *%r12
    [exit status 0]

    $ disas libgcc.so isempty__extern
    0000000000001190 <isempty__extern>:
        1190:	mov    $0x1,%eax
        1195:	test   %rdi,%rdi
        1198:	je     11a0 <isempty__extern+0x10>
        119a:	cmpb   $0x0,(%rdi)
        119d:	sete   %al
        11a0:	ret
    [...]

(b) builds the C files with clang ThinLTO and rs.rs with
`-C linker-plugin-lto` and links them with ld.lld and with gold:

    $ clang --target=x86_64-unknown-linux-gnu [...] librs-lto.a -fuse-ld=lld -o x.so
    ld.lld: error: Invalid summary version 14. Version should be in the range [1-12].
    clang: error: linker command failed with exit code 1 (use -v to see invocation)
    [exit status 1]

    $ clang --target=x86_64-unknown-linux-gnu [...] librs-lto.a -fuse-ld=gold -o x.so
    /usr/bin/ld.gold: fatal error: Failed to link module librs-lto.a.llvm.104984.rs.97d8adf70766aad1-cgu.0: Invalid summary version 14. Version should be in the range [1-12].
    clang: error: linker command failed with exit code 1 (use -v to see invocation)
    [exit status 1]

With the bitcode of our MSRV, or with rustc's own rust-lld, the link
works and no call is left in `count_both()`:

    $ rustc +1.85.0 --edition 2021 -O -C panic=abort --crate-type staticlib -C linker-plugin-lto rs.rs -o librs-old.a
    [exit status 0]

    $ clang --target=x86_64-unknown-linux-gnu [...] librs-old.a -fuse-ld=lld -o libclang-old.so
    [exit status 0]

    $ disas libclang-old.so count_both | grep -c call
    0
    [exit status 1]

    $ clang --target=x86_64-unknown-linux-gnu [...] librs-lto.a -fuse-ld=lld -B ~/.rustup/toolchains/1.99.1-x86_64-unknown-linux-gnu/lib/rustlib/x86_64-unknown-linux-gnu/bin/gcc-ld -o libclang.so
    [exit status 0]

    $ disas libclang.so count_both | grep -c call
    0
    [exit status 1]

And with lib.c built for clang's default triple:

    $ clang -O2 -fPIC -fvisibility=hidden -flto=thin -I35-cross-language-lto -c 35-cross-language-lto/lib.c -o lib-pc.lto.o
    [exit status 0]

    $ clang --target=x86_64-unknown-linux-gnu [...] lib-pc.lto.o [...] -Wl,--fatal-warnings -o x.so
    rust-lld: error: Linking two modules of different target triples: 'count.lto.o' is 'x86_64-unknown-linux-gnu' whereas 'lib-pc.lto.o' is 'x86_64-pc-linux-gnu'
    [...]

(c) builds c.c with `gcc -flto` into a static archive and links it into
main.rs, a `#![no_std]` `#![no_main]` program like ours:

    $ gcc -O2 -fPIC -flto=auto -c 35-cross-language-lto/c.c -o c.o && ar rcs libc-lto.a c.o
    [exit status 0]

    $ rustc +1.99.1 [...] 35-cross-language-lto/main.rs -L . -l c -l static=c-lto -o main
    error: linking with `cc` failed: exit status: 1
      |
      = note:  "cc" "-m64" [...] "-B<sysroot>/lib/rustlib/x86_64-unknown-linux-gnu/bin/gcc-ld" "-fuse-ld=lld" [...]
      = note: some arguments are omitted. use `--verbose` to show all linker arguments
      = note: rust-lld: error: undefined symbol: c_add1
              >>> referenced by main.ba8e141620705c7f-cgu.0
              >>>               main.main.ba8e141620705c7f-cgu.0.rcgu.o:(main)
              collect2: error: ld returned 1 exit status
    [...]
    $ rustc +1.85.0 [...] 35-cross-language-lto/main.rs -L . -l c -l static=c-lto -o main-old && ./main-old
    [exit status 0]

    $ rustc +1.99.1 [...] 35-cross-language-lto/main.rs -L . -l c -l static=c-lto -C linker-features=-lld -o main && ./main
    [exit status 0]

And with `-ffat-lto-objects`:

    $ gcc -O2 -fPIC -flto=auto -ffat-lto-objects -c 35-cross-language-lto/c.c -o cfat.o && ar rcs libc-fat.a cfat.o
    [exit status 0]

    $ rustc +1.99.1 [...] 35-cross-language-lto/main.rs -L . -l c -l static=c-fat -o main-fat && ./main-fat && readelf -p .comment main-fat | grep -o 'Linker: LLD [0-9.]*'
    Linker: LLD 23.1.1
    [exit status 0]

## Upstream

The rustc book promises cross-language optimization only "if all the
object files being linked were created by LLVM-based toolchains"
(src/doc/rustc/src/linker-plugin-lto.md:1-9). Only a GCC-based Rust
compiler could produce GIMPLE, see 31.

The same page says to "use an LLVM linker plugin whose version is at
least as new as the newest compiler involved" (:231-234). Its table of
known good pairs (:244-259) ends with rustc 1.91 to 1.94 and clang 21.
1.99 isn't listed, and our MSRV 1.85 pairs with clang 19. Distro builds
of rustc can use a system LLVM instead of the bundled one. Fedora's
rust.spec does (`%bcond_with bundled_llvm` at :53,
`BuildRequires: %{llvm}-devel` at :326).

rust-lld has been the default linker on `x86_64-unknown-linux-gnu`
since 1.90.0 (RELEASES.md:1169 and :1263-1264, rust-lang/rust#140525).
The rustc book says that "only the `-lld` opt-out is stable on the
`x86_64-unknown-linux-gnu` target"
(src/doc/rustc/src/codegen-options/index.md:296-316).

`--wrap-static-fns` has been stable in bindgen since 0.71.0, see 36.

## Workarounds

For (a) there are none with GCC. Hot static inline helpers can be
rewritten in Rust, which duplicates them, or the Rust code stays out of
hot paths.

For (b) we'd have to build systemd with clang, pass
`--target=x86_64-unknown-linux-gnu` and link with an LLVM at least as
new as rustc's, or with rust-lld. That's not how any of the distros
above build systemd.

For (c) every Rust target needs the stable opt-out
`-C linker-features=-lld`, or every C archive that rustc links needs
`-fno-lto`. We do the latter. Fat LTO objects (`-ffat-lto-objects`) work
too since rust-lld links them from their machine code, without LTO.
