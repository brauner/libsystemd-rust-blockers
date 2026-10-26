#!/bin/bash
# meson can't put Rust code into a C static library.
. "$(dirname "$0")/../common.sh"
versions
run "meson --version"

export RUSTC
ok=1
for p in whole installed; do
        cp -r "$HERE" src
        run "meson setup src/$p build-$p 2>&1 | grep -E 'ERROR|Build targets'"
        [ -e build-$p/build.ninja ] && ok=0
        rm -rf src
done

cp -r "$HERE" src
run "meson setup src/linkwith build-linkwith 2>&1 | grep -E 'ERROR|Build targets'"
rm -rf src

[ $ok -eq 1 ] || not_reproduced "meson configured one of them"
reproduced "meson refuses Rust code in a C static library"
