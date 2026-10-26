# 10. meson can't put Rust code into a C static library

meson refuses to `link_whole` a Rust target into a C static library. An
installed static library has to contain the objects of everything it
links. So for an installed one meson promotes `link_with` to
`link_whole` and fails the same way.

`link_with` into an internal, not installed, static library works. meson
then hands both archives to the final link.

## Why it matters

libsystemd.a is an installed static library
(`install_libsystemd_static`, meson.build:2127, `-Dstatic-libsystemd=`).
It can't contain Rust code built by meson.

libsystemd_static (src/libsystemd/meson.build:151) is pulled into
libsystemd.so and libsystemd-shared with `link_whole`. It would have to
pick up its own Rust part through `link_with` rather than `link_whole`.

## Reproducer

    ./10-meson-static-library/run.sh

This sets up three minimal meson projects. Each of them builds rs.rs as
a Rust static library with `rust_abi : 'c'` and links it into a C static
library built from c.c:

- whole/ puts it into a libsystemd_static with `link_whole`.
- installed/ puts it into an installed library with `link_with`, like
  libsystemd.a.
- linkwith/ puts it into an internal library with `link_with`.

The first two fail at setup:

    $ meson --version
    1.11.1

    $ meson setup src/whole build-whole 2>&1 | grep -E 'ERROR|Build targets'
    src/whole/meson.build:4:20: ERROR: Cannot link_whole a custom or Rust target 'rs' into a static library 'systemd_static'. Instead, pass individual object files with the "objects:" keyword argument if possible.

    $ meson setup src/installed build-installed 2>&1 | grep -E 'ERROR|Build targets'
    src/installed/meson.build:4:0: ERROR: Cannot link_whole a custom or Rust target 'rs' into a static library 'systemd'. Instead, pass individual object files with the "objects:" keyword argument if possible. Meson had to promote link to link_whole because 'systemd' is installed but not 'rs', and thus has to include objects from 'rs' to be usable.

The internal library is fine:

    $ meson setup src/linkwith build-linkwith 2>&1 | grep -E 'ERROR|Build targets'
    Build targets in project: 2

## Upstream

The check is `_bundle_static_library()` in mesonbuild/build.py:2481-2497
(meson 1.11.1). Its comment points at the following, both open:

- mesonbuild/meson#10724, "objects files created by rustc with a crate
  type of staticlib cannot be used as objects", since 2022-08
- mesonbuild/meson#9218

mesonbuild/meson#11213, "rust: add new 'object' type crate", by Luca
Boccassi is meant for exactly this. It has been open since 2022-12.
mesonbuild/meson#8828 is open as well.

## Workarounds

Unpack the Rust archive by hand into a custom target and pass the
objects. Otherwise we'd have to drop `-Dstatic-libsystemd`.
