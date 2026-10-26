# 34. MemorySanitizer reports false positives for memory written by Rust code

MemorySanitizer only considers a byte initialized if instrumented code
wrote it. Stable rustc can't instrument Rust code because
`-Zsanitizer=memory` is nightly only. So a C program built with
`-fsanitize=memory` that branches on a buffer filled by a Rust function
reports `use-of-uninitialized-value`, although every byte was written.

Instrumenting only the crate doesn't help either. Nightly rustc refuses
to build an instrumented crate against the uninstrumented prebuilt core
("mixing `-Zsanitizer` will cause an ABI mismatch"). With that check
overridden the bytes the crate writes itself are fine, but the bytes
core writes, here the digits from `core::fmt`, still trip MSan. core has
to be rebuilt with the sanitizer and only cargo's nightly `-Zbuild-std`
does that.

## Why it matters

Our fuzzers run under MSan. CIFuzz for systemd/systemd
(.github/workflows/cifuzz.yml:33) and ClusterFuzzLite for forks
(.github/workflows/cflite-pr.yml:24) run with
`sanitizer: [address, undefined, memory]` on pull requests, CIFuzz on
those that touch the sources. Both build with
tools/oss-fuzz.sh (.clusterfuzzlite/Dockerfile:5). OSS-Fuzz itself
fuzzes systemd with `sanitizers: address, undefined, memory`
(projects/systemd/project.yaml in google/oss-fuzz at ec788d43a2d).

The fuzzers link libsystemd-shared (tools/oss-fuzz.sh:114-116), which
contains libsystemd's code. So Rust code in libsystemd would end up in
every MSan fuzzer. Currently, `--auto-features=disabled`
(tools/oss-fuzz.sh:41) also turns off the `rust` feature
(meson_options.txt:545), so the fuzzers have no Rust code.

This has happened before. In 2021 uninstrumented Rust code produced MSan
false positives on our CIFuzz, in the thread of systemd/systemd#19598.

## Reproducer

    ./34-msan-false-positive/run.sh

rs.rs has two functions. `rs_hex64()` writes 16 hex digits with plain
stores. `rs_fmt_u64()` formats a number with `write!`, so core's
`<u64 as Display>::fmt` produces the digits. main.c is built with
`clang -fsanitize=memory` and branches on the first byte of the result.
`dirty_stack()` leaves poisoned shadow below `main()`'s frame, as any
earlier call in a real program would.

First with the crate built by stable rustc, without and with MSan:

    # rustc 1.99.1 (58cf8f9c3 2026-10-13)
    [...]
    $ clang --version | head -1
    Debian clang version 21.1.8 (10)
    [exit status 0]

    $ ./main-nosan hex
    00000000deadbeef
    [exit status 0]

    $ ./main hex
    ==36007==WARNING: MemorySanitizer: use-of-uninitialized-value
        #0 0x55692403a278 in main 34-msan-false-positive/main.c:27:20
    [...]
      Uninitialized value was created by an allocation of 'buf' in the stack frame
        #0 0x55692403a1d8 in main 34-msan-false-positive/main.c:16:9
    [...]

Then the crate with `-Z sanitizer=memory`, on stable and on nightly,
faked here with `RUSTC_BOOTSTRAP=1`. The same error follows for
`compiler_builtins`:

    $ rustc +1.99.1 [...] -Z sanitizer=memory 34-msan-false-positive/rs.rs -o librs-msan.a
    error: the option `Z` is only accepted on the nightly compiler
    [...]
    $ RUSTC_BOOTSTRAP=1 rustc +1.99.1 [...] -Z sanitizer=memory -Z sanitizer-memory-track-origins 34-msan-false-positive/rs.rs -o librs-msan.a
    error: mixing `-Zsanitizer` will cause an ABI mismatch in crate `rs`
      |
      = help: the `-Zsanitizer` flag modifies the ABI so Rust crates compiled with different values of this flag cannot be used together safely
      = note: `-Zsanitizer=memory` in this crate is incompatible with `-Zsanitizer` being unset in dependency `core`
      = help: unset `-Zsanitizer` in this crate or set `-Zsanitizer=memory` in `core`
      = help: if you are sure this will not cause problems, you may use `-Cunsafe-allow-abi-mismatch=sanitizer` to silence this error
    [...]

And with the check overridden:

    $ RUSTC_BOOTSTRAP=1 rustc +1.99.1 [...] -C unsafe-allow-abi-mismatch=sanitizer 34-msan-false-positive/rs.rs -o librs-msan.a
    [exit status 0]
    [...]
    $ ./main-msan hex
    00000000deadbeef
    [exit status 0]

    $ ./main-msan fmt
    ==36067==WARNING: MemorySanitizer: use-of-uninitialized-value
        #0 0x55f517455278 in main 34-msan-false-positive/main.c:27:20
    [...]
      Uninitialized value was stored to memory at
        #0 0x55f5173ec34e in __msan_memcpy ($W/main-msan+0x6a34e) (BuildId: 1798c428896e085faf1be6f1d7d7f4b56de9640c)
        #1 0x55f5174553e7 in <rs::Buf as core::fmt::Write>::write_str rs.97d8adf70766aad1-cgu.0

      Uninitialized value was created by an allocation of 'junk' in the stack frame
        #0 0x55f5174552d1 in dirty_stack 34-msan-false-positive/main.c:11:9
    [...]

So the digits that core wrote onto its own stack still carried the
shadow of an earlier frame. The instrumented crate object calls the
uninstrumented `<u64 as core::fmt::Display>::fmt` and `core::fmt::write`
(`nm -u`). Without `dirty_stack()` the fmt case happens to pass, so in a
real fuzzer this kind of report comes and goes with the call history.
These two were checked by hand and aren't part of run.sh.

## Upstream

`-Zsanitizer` is unstable (compiler/rustc_session/src/options.rs:2845)
and a target modifier (`{ TARGET_MODIFIER: Sanitizer }`), which is where
the mixing error comes from. Its tracking issue rust-lang/rust#39699 is
open. The stabilization PR rust-lang/rust#123617 only covers
AddressSanitizer and LeakSanitizer and is open as well
(S-waiting-on-author).

The unstable book says "MemorySanitizer requires all program code to be
instrumented. C/C++ dependencies need to be recompiled using Clang with
`-fsanitize=memory` option. Failing to achieve that will result in false
positive reports"
(src/doc/unstable-book/src/compiler-flags/sanitizer.md:744-746). It also
says that the `-Zbuild-std` flag "rebuilds and instruments the standard
library, and is strictly necessary for the correct operation of the
tool" (752-754) and repeats this at 974-981.

`-Zbuild-std` is a cargo flag and nightly only. The build-std RFCs
merged between 2025-12 and 2026-05 (rust-lang/rfcs#3873, #3874, #3875)
are cargo features as well. Outside of cargo, rebuilding core needs the
rust-src sources and a nightly compiler because library/core/src/lib.rs
has 89 `#![feature(...)]` lines.

OSS-Fuzz's Rust guide says "The only supported fuzzing engine and
sanitizer are `libfuzzer` and `address`, respectively."

## Workarounds

We can keep Rust out of the MSan builds, which is what
`--auto-features=disabled` does for the leaf programs today. Code in
libsystemd itself can't be left out like that unless a C version of it
exists, and then the MSan job tests the C version and not the one we
ship.

Or we unpoison by hand and call `__msan_unpoison()` on everything a Rust
function writes before C reads it. Every call site needs that, including
memory reached through pointers, and it also hides real uninitialized
reads in the Rust code.
