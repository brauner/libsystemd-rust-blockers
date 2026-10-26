# Sourced by every reproducer. Override any of these from the environment or
# from an env.local file next to this one.
#
# RUSTC       the current stable rustc (1.99.1 when the logs were recorded)
# RUSTC_OLD   our Rust MSRV (meson.build: rust_msrv = '1.85')
# CARGO       cargo of the same release as RUSTC, only used to show -Zbuild-std
# BINDGEN     bindgen-cli (0.72.1 when recorded)
# GCCRS       the gccrs driver, GCCRS_B its -B directory if not installed
# SYSTEMD_SRC a systemd checkout (main e9795a90b7 when recorded)
# RUST_SRC    a rust-lang/rust checkout (846e51f66b1 when recorded)

COMMON_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[ -f "$COMMON_DIR/env.local" ] && . "$COMMON_DIR/env.local"

: "${RUSTC:=rustc}"
: "${RUSTC_OLD:=rustc +1.85.0}"
: "${CARGO:=cargo}"
: "${CC:=gcc}"
: "${CXX:=g++}"
: "${CLANG:=clang}"
: "${BINDGEN:=bindgen}"
: "${GCCRS:=gccrs-16}"
: "${GCCRS_B:=}"
: "${SYSTEMD_SRC:=$HOME/src/git/systemd}"
: "${RUST_SRC:=$HOME/src/git/rust}"

# run-all.sh only wants the settings.
[ -n "$CONFIG_ONLY" ] && return 0

# Work in a fresh directory per run, never in the source directory.
W=$(mktemp -d "${TMPDIR:-/tmp}/repro.XXXXXX")
trap 'rm -rf "$W"' EXIT
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$W" || exit 1

# Print a command, then run it. Output and exit status are shown verbatim.
run() {
        printf '\n$ %s\n' "$*"
        eval "$@"
        local rc=$?
        printf '[exit status %d]\n' "$rc"
        return $rc
}

versions() {
        printf '# %s\n' "$($RUSTC --version)" "$($CC --version | head -1)" "$(uname -m) $(uname -r)"
}

reproduced()     { printf '\nRESULT: REPRODUCED: %s\n' "$*"; exit 0; }
not_reproduced() { printf '\nRESULT: NOT REPRODUCED: %s\n' "$*"; exit 1; }
