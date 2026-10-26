#!/bin/bash
# A staticlib in libsystemd-shared exports its Rust internals and core.
. "$(dirname "$0")/../common.sh"
versions

run "cat $SYSTEMD_SRC/src/shared/libshared.sym"
run "grep -n -A6 '^libshared = shared_library' $SYSTEMD_SRC/src/shared/meson.build"

run "$RUSTC --edition 2021 -C panic=abort -O --crate-type staticlib $HERE/sd.rs -o libsd_rust.a" || exit 1
# Like libsystemd-shared, -fvisibility=default and global: *.
run "$CC -O2 -fPIC -shared -fvisibility=default $HERE/lib.c libsd_rust.a -Wl,--gc-sections -Wl,--version-script=$HERE/shared.sym -o libshared.so" || exit 1
# Like libsystemd.so, an explicit list and local: *.
run "$CC -O2 -fPIC -shared -fvisibility=hidden $HERE/lib.c libsd_rust.a -Wl,--gc-sections -Wl,--version-script=$HERE/public.sym -o libpublic.so" || exit 1

# Our workaround, hide Rust's mangled names in libshared.sym.
run "$CC -O2 -fPIC -shared -fvisibility=default $HERE/lib.c libsd_rust.a -Wl,--gc-sections -Wl,--version-script=$HERE/hidden.sym -o libshared-hidden.so" || exit 1

# The same function in plain C.
run "$CC -O2 -fPIC -shared -fvisibility=hidden $HERE/c-only.c -Wl,--gc-sections -Wl,--version-script=$HERE/public.sym -o libc-only.so" || exit 1

for f in libshared.so libpublic.so libshared-hidden.so libc-only.so; do
        strip -o $f.stripped $f
        printf '\n## %s: %s bytes stripped, exports %s symbols, %s of them Rust:\n' $f \
                "$(stat -c %s $f.stripped)" \
                "$(nm -D --defined-only $f | grep -vc ' A ')" "$(nm -D --defined-only $f | grep -c ' _R')"
        nm -C -D --defined-only $f | grep -vE ' A ' | sed 's/^[0-9a-f]* //' | sed -n '1,12p'
done

# Hiding them is a nightly option.
run "$RUSTC --edition 2021 -C panic=abort --crate-type staticlib -Zstaticlib-hide-internal-symbols $HERE/sd.rs -o x.a"

n=$(nm -D --defined-only libshared.so | grep -c ' _R')
[ "$n" -gt 0 ] || not_reproduced "no Rust symbols exported"
reproduced "$n Rust symbols exported from a global: * library"
