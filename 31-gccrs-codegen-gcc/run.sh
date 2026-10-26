#!/bin/bash
# The GCC based Rust compilers can't fill the gap from 30 yet.
. "$(dirname "$0")/../common.sh"
versions

G="$GCCRS ${GCCRS_B:+-B$GCCRS_B}"
X=-frust-incomplete-and-experimental-compiler-do-not-use
count() { awk '/error:/ { n++ } END { print n + 0, "errors" }'; }

run "$G --version | head -1"

printf '#![no_std]\npub fn f(a: u32, b: u32) -> u32 { core::cmp::max(a, b) }\n' > lib.rs
printf '#![no_std]\npub fn f(a: u32, b: u32) -> u32 { if a > b { a } else { b } }\n' > nocore.rs
run "$G -c lib.rs -o lib.o 2>&1 | head -1"
run "$G $X -c lib.rs -o lib.o 2>&1 | head -4"
# Even a crate that uses nothing from core needs it.
run "$G $X -c nocore.rs -o nocore.o 2>&1 | head -2"

# The stdarch submodule isn't in $RUST_SRC, so stub out core::arch.
if git -C "$RUST_SRC" archive 1.49.0 library/core 2>/dev/null | tar -x; then
        mkdir -p library/stdarch/crates/core_arch/src
        echo 'pub mod arch {}' > library/stdarch/crates/core_arch/src/mod.rs
        cd library/core/src || exit 1
        # GCC 16's own testsuite stops at attributecheck.
        for stage in attributecheck expansion astvalidation typecheck; do
                run "$G $X -frust-edition=2018 -frust-crate=core -frust-compile-until=$stage -w -c lib.rs -o core.o 2>&1 | count"
        done
        run "$G $X -frust-edition=2018 -frust-crate=core -frust-compile-until=astvalidation -w -c lib.rs -o core.o 2>&1 | grep 'error:' | sed 's/:[0-9]*:[0-9]*: error:/: error:/' | sort | uniq -c | sort -rn | head -5"
        rm -f core.o
        run "$G $X -frust-edition=2018 -frust-crate=core -w -c lib.rs -o core.o 2>&1 | count; ls core.o"
        cd "$W" || exit 1
else
        echo "no 1.49.0 tag in $RUST_SRC, skipping the core build"
fi

# Stable rustc can't select rustc_codegen_gcc.
run "$RUSTC -Zcodegen-backend=gcc --crate-type lib lib.rs 2>&1 | head -1"
# The stable manifest has none of its components, for any target.
M=$($RUSTC --print sysroot)/lib/rustlib/multirust-channel-manifest.toml
run "awk '/^\[pkg\.(rustc-codegen-gcc-preview|gcc-[a-z0-9_]+-[a-z]+-[a-z]+-[a-z]+-preview)\.target\./ { n++; t = 1; next } t && /available = true/ { a++ } { t = 0 } END { print n + 0, \"target entries,\", a + 0, \"available\" }' $M"

# What the rust tree says about it.
CG=$RUST_SRC/compiler/rustc_codegen_gcc
run "grep -n -E '^# WIP|primary goal|requires a patched libgccjit' $CG/Readme.md"
run "grep -n 'must be supported by the rust compiler' $CG/doc/tips.md"
run "ls $CG/target_specs"
run "grep -n -A6 'commands: \[' $CG/.github/workflows/m68k.yml"
run "grep -n -B1 -A2 'This prevents rustc_codegen_gcc from being built' $RUST_SRC/src/bootstrap/src/core/build_steps/dist.rs"
run "grep -n -B3 'not supported by rustc_codegen_gcc' $RUST_SRC/src/bootstrap/src/core/build_steps/dist.rs"
run "sed -n '/pub enum Arch {/,/^    }/p' $RUST_SRC/compiler/rustc_target/src/spec/mod.rs | grep -o '\"[a-z0-9_]*\"' | paste -s -d ' '"
run "grep -n -B1 'no lowering implemented' $RUST_SRC/compiler/rustc_target/src/callconv/mod.rs"

[ -e "$W/library/core/src/core.o" ] && not_reproduced "gccrs compiled core 1.49.0"
reproduced "gccrs cannot compile core 1.49.0, rustc_codegen_gcc is nightly and x86_64 only, and rustc has no C ABI for alpha, hppa or sh"
