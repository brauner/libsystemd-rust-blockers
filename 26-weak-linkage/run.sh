#!/bin/bash
# Stable Rust can't make the weak, NULL-checked references libsystemd uses.
. "$(dirname "$0")/../common.sh"
versions
ulimit -c 0     # one test program crashes on purpose

# meson builds shared libraries with --no-undefined, systemd adds --gc-sections.
L="-shared -Wl,--no-undefined -Wl,--gc-sections"
R="--edition 2021 -O -C panic=abort --crate-type staticlib"

# C, without the provider (libsystemd.so) and with it (libsystemd-shared).
run "$CC -O2 -fPIC -c $HERE/hook.c $HERE/provider.c $HERE/main.c" || exit 1
run "$CC $L hook.o -o libc-without.so" || exit 1
run "$CC $L hook.o provider.o -o libc-with.so" || exit 1
run "nm -D libc-without.so | grep optional_hook"
run "$CC main.o ./libc-without.so -o c-without && ./c-without" || exit 1
run "$CC main.o ./libc-with.so -o c-with && ./c-with" || exit 1

# Rust: the attribute for a weak reference is unstable.
run "$RUSTC $R $HERE/weak.rs -o x.a" && not_reproduced "#[linkage] is stable"

# A plain extern declaration is a strong reference. -u pulls in the object.
run "$RUSTC $R $HERE/hook.rs -o libhook.a" || exit 1
run "$CC $L -Wl,-u,report libhook.a -o librust-without.so" && not_reproduced "links without the provider"
run "$CC $L -Wl,-u,report libhook.a provider.o -o librust-with.so" || exit 1
run "$CC main.o ./librust-with.so -o rust-with && ./rust-with" || exit 1

# Weakening it afterwards doesn't help since rustc removed the NULL check.
run "objcopy --weaken-symbol=optional_hook libhook.a libhook-weak.a" || exit 1
run "$CC $L -Wl,-u,report libhook-weak.a -o librust-weak.so" || exit 1
run "objdump -d --no-show-raw-insn -M intel --disassemble=report librust-weak.so | grep -A3 '<report>:'"
run "$CC main.o ./librust-weak.so -o rust-weak && ./rust-weak"

# The unstable attribute does work. RUSTC_BOOTSTRAP=1 is used only to show that.
run "RUSTC_BOOTSTRAP=1 $RUSTC $R -Zcrate-attr='feature(linkage)' $HERE/weak.rs -o libweak.a" || exit 1
run "$CC $L -Wl,-u,report libweak.a -o librust-nightly.so" || exit 1
run "$CC main.o ./librust-nightly.so -o rust-nightly && ./rust-nightly" || exit 1

reproduced "C links the weak reference with --no-undefined and sees NULL; stable Rust rejects #[linkage = \"extern_weak\"] (E0658), and a plain extern reference is undefined at link time"
