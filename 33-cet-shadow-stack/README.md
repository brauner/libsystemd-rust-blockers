# 33. Rust code drops the CET (IBT/SHSTK) marking of a shared library

On x86-64 the linker marks a shared object with IBT and SHSTK (the
`GNU_PROPERTY_X86_FEATURE_1_AND` note) only if every relocatable object
linked into it has the marking. Stable rustc emits no such note, and the
prebuilt `core` and `compiler_builtins` in the rustup sysroot don't have
it either. So a C library compiled with `-fcf-protection` loses the
marking as soon as one Rust function is linked into it.

`-Zcf-protection=full` marks the crate's own objects, but it's nightly
only, and the prebuilt core and compiler_builtins stay unmarked. Even on
nightly the marking only comes back with a rebuilt core (`-Zbuild-std`,
cargo only), or if no object of core ends up in the link. With our
`-C overflow-checks=yes` a single `a + b` already pulls core in, as the
reproducer shows.

## Why it matters

Distributions compile C with `-fcf-protection` on x86-64.
dpkg-buildflags on this Debian host prints `... -fcf-protection`
(Dpkg/Vendor/Debian.pm:632-656, the "branch" hardening feature, on by
default). For Fedora it's in redhat-rpm-config's macros:164 and
buildflags.md:618-619, for Arch in makepkg.conf:45-48.

The libsystemd.so.0 that distributions ship today carries the marking.
`readelf -n` prints `x86 feature: IBT, SHSTK` for Fedora 44
(systemd-libs-259.10-1.fc44), Ubuntu (libsystemd0 259.5-0ubuntu3.4 and
261.3-0ubuntu3) and Arch (systemd-libs 262.1-1), and for Fedora's and
Arch's libnss_systemd.so.2. Debian's has no marking. Debian builds glibc
without CET, so its crti.o and crtn.o are unmarked and nothing linked on
Debian is marked. dpkg says so itself in the comment at
Debian.pm:639-647. Fedora, Ubuntu and Arch mark their crt files.

libsystemd's code is linked into libsystemd.so, libudev.so, the NSS
modules and pam_systemd (meson.build:2108-2124, 2156-2168, 2335-2362).
glibc dlopen()s the NSS modules into every process that looks up users
or hosts, and libpam dlopen()s pam_systemd into login services.

At runtime only the SHSTK bit matters today. Linux supports user-space
shadow stacks but not user-space IBT ("only userspace shadow stack and
kernel IBT are supported", Documentation/arch/x86/shstk.rst:22-23 in
Linux 21a7f44fd076). By default glibc enables SHSTK only if the program
and all its dependencies are marked. "By default, when SHSTK is enabled,
dlopening a non-CET shared library returns an error. With `permissive`,
it turns off SHSTK instead" (manual/tunables.texi:566-576 at glibc
04e750e75b7). The error is "rebuild shared object with SHSTK support
enabled" (sysdeps/x86_64/dl-cet.c:221-242).

Fedora's accepted change "ShadowStack" (target Fedora 46,
https://fedoraproject.org/wiki/Changes/ShadowStack) turns SHSTK on by
default. Its page says "Processes that load any non-compliant shared
object will have Shadow Stack silently disabled at startup" and that a
dlopen() of one "will lead to a `dlopen` failure".

## Reproducer

    ./33-cet-shadow-stack/run.sh

It builds the same small library twice with `-fcf-protection=full`, once
with `rs_add()` written in C and once in Rust, using our rustc flags. It
then reads the notes with `readelf -n` and lets `ld -z cet-report=error`
name the unmarked inputs. The library is linked with `-nostartfiles`, so
that Debian's unmarked crt files don't mask the result. On this host
crti.o has no marking:

    # rustc 1.99.1 (58cf8f9c3 2026-10-13)
    # gcc (Debian 16.2.0-1) 16.2.0
    # x86_64 7.1.13+deb14-amd64

    $ readelf -n $(gcc -print-file-name=crti.o) | grep 'x86 feature' || echo 'no x86 feature property in crti.o'
    no x86 feature property in crti.o

The C-only library is marked, the one with Rust in it isn't:

    $ gcc -shared -nostartfiles -Wl,--gc-sections lib.o add.o -o libc-only.so
    $ readelf -n libc-only.so | grep 'x86 feature'
          Properties: x86 feature: IBT, SHSTK
    $ rustc +1.99.1 --edition 2021 -O -C panic=abort -C overflow-checks=yes --crate-type staticlib 33-cet-shadow-stack/rs.rs -o librs.a
    $ gcc -shared -nostartfiles -Wl,--gc-sections lib.o librs.a -o libwith-rust.so
    $ readelf -n libwith-rust.so | grep 'x86 feature'
    [exit status 1]

The linker names the crate's object, one of core's and three of
compiler_builtins'. None of core's objects has the note:

    $ gcc -shared -nostartfiles -Wl,--gc-sections lib.o librs.a -o x.so -Wl,-z,cet-report=error
    /usr/bin/x86_64-linux-gnu-ld.bfd: librs.a(librs.rs.97d8adf70766aad1-cgu.0.rcgu.o): error: missing IBT and SHSTK properties
    /usr/bin/x86_64-linux-gnu-ld.bfd: librs.a(core-1d288395a3394ed3.core.efd5e57aef94d71e-cgu.0.rcgu.o): error: missing IBT and SHSTK properties
    /usr/bin/x86_64-linux-gnu-ld.bfd: librs.a(compiler_builtins-2d9557d6e902a200.compiler_builtins.2ae8f9d4cd35b9b2-cgu.157.rcgu.o): error: missing IBT and SHSTK properties
    /usr/bin/x86_64-linux-gnu-ld.bfd: librs.a(compiler_builtins-2d9557d6e902a200.compiler_builtins.2ae8f9d4cd35b9b2-cgu.200.rcgu.o): error: missing IBT and SHSTK properties
    /usr/bin/x86_64-linux-gnu-ld.bfd: librs.a(compiler_builtins-2d9557d6e902a200.compiler_builtins.2ae8f9d4cd35b9b2-cgu.225.rcgu.o): error: missing IBT and SHSTK properties
    collect2: error: ld returned 1 exit status
    $ readelf -n core/*.o | grep -c 'x86 feature'
    0

`-Z cf-protection=full` needs nightly, so `RUSTC_BOOTSTRAP=1` stands in
to show what nightly does. The crate's object is no longer listed, but
core's and compiler_builtins' still are, and the library still isn't
marked:

    $ rustc +1.99.1 --edition 2021 -O -C panic=abort -C overflow-checks=yes --crate-type staticlib -Z cf-protection=full 33-cet-shadow-stack/rs.rs -o librs-cf.a
    error: the option `Z` is only accepted on the nightly compiler
    [...]
    $ RUSTC_BOOTSTRAP=1 rustc +1.99.1 --edition 2021 -O -C panic=abort -C overflow-checks=yes --crate-type staticlib -Z cf-protection=full 33-cet-shadow-stack/rs.rs -o librs-cf.a
    [exit status 0]
    $ gcc -shared -nostartfiles -Wl,--gc-sections lib.o librs-cf.a -o x.so -Wl,-z,cet-report=error
    /usr/bin/x86_64-linux-gnu-ld.bfd: librs-cf.a(core-1d288395a3394ed3.core.efd5e57aef94d71e-cgu.0.rcgu.o): error: missing IBT and SHSTK properties
    /usr/bin/x86_64-linux-gnu-ld.bfd: librs-cf.a(compiler_builtins-2d9557d6e902a200.compiler_builtins.2ae8f9d4cd35b9b2-cgu.157.rcgu.o): error: missing IBT and SHSTK properties
    /usr/bin/x86_64-linux-gnu-ld.bfd: librs-cf.a(compiler_builtins-2d9557d6e902a200.compiler_builtins.2ae8f9d4cd35b9b2-cgu.200.rcgu.o): error: missing IBT and SHSTK properties
    /usr/bin/x86_64-linux-gnu-ld.bfd: librs-cf.a(compiler_builtins-2d9557d6e902a200.compiler_builtins.2ae8f9d4cd35b9b2-cgu.225.rcgu.o): error: missing IBT and SHSTK properties
    collect2: error: ld returned 1 exit status
    $ readelf -n libwith-rust-cf.so | grep 'x86 feature'
    [exit status 1]

The stack protector is nightly only as well, and the prebuilt core has
no canaries:

    $ rustc +1.99.1 --edition 2021 -O -C panic=abort -C overflow-checks=yes --crate-type staticlib -Z stack-protector=strong 33-cet-shadow-stack/rs.rs -o librs-sp.a
    error: the option `Z` is only accepted on the nightly compiler
    [...]
    $ nm core/*.o | grep -c __stack_chk_fail
    0

    RESULT: REPRODUCED: IBT/SHSTK marking dropped by stable Rust code and by the prebuilt core

The distribution packages were checked by hand on 2026-10-26. Newer
builds replace these file names on the mirrors:

    curl -O https://dl.fedoraproject.org/pub/fedora/linux/updates/44/Everything/x86_64/Packages/s/systemd-libs-259.10-1.fc44.x86_64.rpm
    bsdtar -xf systemd-libs-259.10-1.fc44.x86_64.rpm && readelf -n usr/lib64/libsystemd.so.0.42.0 | grep 'x86 feature'
    curl -O http://archive.ubuntu.com/ubuntu/pool/main/s/systemd/libsystemd0_261.3-0ubuntu3_amd64.deb
    dpkg -x libsystemd0_261.3-0ubuntu3_amd64.deb u && readelf -n u/usr/lib/x86_64-linux-gnu/libsystemd.so.0.44.0 | grep 'x86 feature'
    curl -O https://geo.mirror.pkgbuild.com/core/os/x86_64/systemd-libs-262.1-1-x86_64.pkg.tar.zst
    bsdtar -xf systemd-libs-262.1-1-x86_64.pkg.tar.zst && readelf -n usr/lib/libsystemd.so.0.45.0 | grep 'x86 feature'
    curl -O https://dl.fedoraproject.org/pub/fedora/linux/updates/44/Everything/x86_64/Packages/r/rust-std-static-1.99.0-1.fc44.x86_64.rpm
    bsdtar -xf rust-std-static-1.99.0-1.fc44.x86_64.rpm && ar x usr/lib/rustlib/x86_64-unknown-linux-gnu/lib/libcore-*.rlib && readelf -n core-*.o | grep 'x86 feature'

## Upstream

`-Zcf-protection` is an unstable option
(compiler/rustc_session/src/options.rs:2440) with tracking issue
rust-lang/rust#93754, open. A search on 2026-10-26 found no
stabilization PR. The unstable book says the same thing the reproducer
shows, "all compiled modules linked together must have the flags set for
the compiled output to be CET-enabled. Currently, Rust's standard
library does not ship with CET enabled by default"
(src/doc/unstable-book/src/compiler-flags/cf-protection.md:17-25).

rust-lang/rust#156612 "Compile libraries with cf-protection=branch on
x64" is open (S-waiting-on-author). It covers IBT only, and its
description says "This doesn't do anything for shadow stack support".

Fedora patches its rustc instead. Patch8 in rust.spec (f43, f44, f45 and
rawhide, all 1.99.1) sets `cf_protection = CFProtection::Return` in the
x86_64-unknown-linux-gnu target spec. Fedora's own core is SHSTK-marked.
rust-std-static-1.99.0-1.fc44 has `x86 feature: SHSTK` on core's object.
So with Fedora's rustc the SHSTK bit should survive and only IBT be
dropped, which has no runtime effect on Linux today. That's untested
since Fedora's rustc wasn't run here. Debian's (debian/patches/series)
and Arch's (PKGBUILD) rustc have no such patch.

On arm64, which wasn't run here for lack of an aarch64 toolchain,
`-Zbranch-protection` (options.rs:2434, the parser at 2034-2071 accepts
`bti`, `pac-ret`, `leaf`, `b-key`, `pc` and `gcs`) is nightly only, with
tracking issue rust-lang/rust#113369, open. The unstable book says
"Rust's standard library does not ship with BTI or pointer
authentication enabled by default" (branch-protection.md:22). Debian and
Fedora compile C for arm64 with `-mbranch-protection=standard`
(Debian.pm:636-637, Fedora rpmrc:17). The BTI and GCS notes follow the
same AND rule. We link with `-Wl,-z,gcs-report-dynamic=none`
(meson.build:631, 310ab61139) because of the GCS transition.

For the stack protector, we compile C with
`-fstack-protector-strong --param=ssp-buffer-size=4`
(meson.build:575-583). `-Zstack-protector` is nightly only
(options.rs:2919, exploit-mitigations.md:65 "No, `-Z stack-protector` |
Nightly"). Its tracking issue rust-lang/rust#114903 is open, and so is
the stabilization PR rust-lang/rust#146369, in proposed FCP and marked
S-blocked. rust's own bootstrap.example.toml:784-789 says "`strong` and
`basic` options may be buggy and are not recommended". This is the
weaker point of the two. Safe Rust indexes with bounds checks, so the
linear stack overflows that canaries catch need `unsafe` code in Rust.

## Workarounds

`-Wl,-z,shstk` forces the SHSTK bit on. That's in effect what Fedora's
rustc patch does ("Shadow Stack doesn't change codegen -- this only
enables the SHSTK flag"), but it overrides the linker's check for every
object in the link, C included. `-Wl,-z,ibt` would claim IBT for code
without `endbr64`.

We could also use a rustc that marks SHSTK by default, as Fedora does.
That covers SHSTK only, and only with that distribution's rustc.

Or we rebuild core with `-Zcf-protection=full` (`-Zbuild-std`), which
needs nightly and cargo.
