#!/bin/bash
# If libsystemd.a contained Rust code, no Rust program could link it.
. "$(dirname "$0")/../common.sh"
versions

run "grep -A3 \"option('static-libsystemd'\" $SYSTEMD_SRC/meson_options.txt"
run "$RUSTC --edition 2021 -C panic=abort -O --crate-type staticlib $HERE/sd.rs -o libsystemd.a" || exit 1
run "$RUSTC --edition 2021 -O $HERE/app.rs -L . -l static=systemd -o app" && \
        not_reproduced "the program linked"

# Same nightly fix as in 08 (rust-lang/rust#156950), unlocked with RUSTC_BOOTSTRAP=1.
run "RUSTC_BOOTSTRAP=1 $RUSTC --edition 2021 -C panic=abort -O --crate-type staticlib -Zstaticlib-rename-internal-symbols $HERE/sd.rs -o libsystemd.a" && \
run "$RUSTC --edition 2021 -O $HERE/app.rs -L . -l static=systemd -o app && ./app"
reproduced "a Rust program cannot link a libsystemd.a that contains Rust"
