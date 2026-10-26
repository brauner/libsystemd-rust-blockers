#!/bin/bash
# A Rust-ABI shared library exports all of core, and two of them don't mix.
. "$(dirname "$0")/../common.sh"
versions

R="--edition 2021 -C panic=abort -O"
run "$RUSTC $R --crate-type dylib $HERE/sdshared.rs -o libsdshared.so" || exit 1
run "$RUSTC $R --crate-type cdylib $HERE/sdshared.rs -o libsdshared-c.so" || exit 1

for f in libsdshared.so libsdshared-c.so; do
        strip -o $f.stripped $f
        printf '\n## %s\n' $f
        printf '   stripped size:        %s bytes\n' "$(stat -c %s $f.stripped)"
        printf '   exported symbols:     %s\n' "$(nm -D --defined-only $f | wc -l)"
        printf '   ... of which core::   %s\n' "$(nm -C -D --defined-only $f | grep -c ' core::')"
        printf '   .rustc after strip:   %s\n' "$(readelf -S -W $f.stripped | awk '$2==".rustc"{print strtonum("0x"$6)" bytes"}')"
done
printf '\n## a few of the exports of libsdshared.so\n'
nm -C -D --defined-only libsdshared.so | grep ' core::' | sed 's/^[0-9a-f]* //' | sed -n '1~60p'

# Each dylib brings its own core and panic handler.
run "$RUSTC $R --crate-type dylib $HERE/other.rs -o libother.so" || exit 1
run "$RUSTC $R $HERE/user.rs -L . --extern sdshared=libsdshared.so --extern other=libother.so -o user" && \
        not_reproduced "a program linked two independent dylibs"

d=$(nm -C -D --defined-only libsdshared.so | grep -c ' core::')
[ "$d" -gt 100 ] || not_reproduced "the dylib does not export core"
reproduced "a 17 line no_std dylib exports $d core symbols"
