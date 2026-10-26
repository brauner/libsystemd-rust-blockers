#!/bin/bash
# What bindgen does with our macros, static inline functions and bitfields.
. "$(dirname "$0")/../common.sh"
versions
run "$BINDGEN --version"
run "git -C $SYSTEMD_SRC log -1 --format='%h %cs'"

# 1. How much of it there is.
run "(cd $SYSTEMD_SRC && find src/fundamental src/basic src/libsystemd src/systemd -name '*.h' | sort | xargs awk -f $HERE/count.awk)"
run "(cd $SYSTEMD_SRC && grep -rho -w -E 'assert_return|_public_' src/libsystemd --include='*.c' | sort | uniq -c)"

# Flags as in src/rust/systemd-shared/meson.build:39-43 and 51-80.
S=$SYSTEMD_SRC/src
F="-include $HERE/config.h -D_GNU_SOURCE -D_FILE_OFFSET_BITS=64"
F="$F -isystem $S/include/glibc -isystem $S/include/override -isystem $S/include/uapi"
F="$F -I$S/fundamental -I$S/basic -I$S/systemd"
B="--use-core --ctypes-prefix core::ffi --allowlist-file '.*/src/(fundamental|basic|systemd)/.*'"

# 2. Function-like macros produce nothing, only the functions behind some of them.
run "$BINDGEN $B $HERE/macros.h -o macros.rs -- $F" || exit 1
run "for m in assert_return log_debug_errno TAKE_PTR streq IN_SET HASHMAP_FOREACH CMSG_FOREACH strjoina; do echo \"\$m \$(grep -c -w \$m macros.rs)\"; done"
run "grep -c -w -E 'assert_return|log_debug_errno|TAKE_PTR|streq|IN_SET|HASHMAP_FOREACH|CMSG_FOREACH|strjoina' macros.rs" && not_reproduced "a macro made it into the bindings"
run "grep -o -w -E 'pub fn (log_assert_failed_return|log_internal|_hashmap_iterate)' macros.rs"
# --clang-macro-fallback evaluates macros that expand to constants, not these.
run "$BINDGEN $B --clang-macro-fallback $HERE/macros.h -o macros-fallback.rs -- $F" || exit 1
run "grep -c -w -E 'assert_return|log_debug_errno|TAKE_PTR|streq|IN_SET|HASHMAP_FOREACH|CMSG_FOREACH|strjoina' macros-fallback.rs"

# 3. Static inline functions are skipped, --wrap-static-fns writes C trampolines.
run "grep -c -w -E 'pub fn (isempty|streq_ptr)' macros.rs"
run "$BINDGEN $B --wrap-static-fns --wrap-static-fns-path wrap $HERE/macros.h -o macros-wrap.rs -- $F" || exit 1
run "grep -c '__extern(' wrap.c"
run "grep -E '^bool (isempty|streq_ptr)__extern' wrap.c"
# The trampolines are C that has to compile, and for close_pairp() it does not.
run "$BINDGEN $B --wrap-static-fns --wrap-static-fns-path fdwrap $HERE/fd.h -o fd.rs -- $F" || exit 1
run "grep close_pairp fdwrap.c"
run "$CC $F -c fdwrap.c -o fdwrap.o 2>&1 | grep error:"

# 4. Bitfields: sd_bus_vtable has uint8_t type:8 and uint64_t flags:56.
run "$BINDGEN --use-core --ctypes-prefix core::ffi --allowlist-type sd_bus_vtable $HERE/vt.h -o vt.rs -- -I$S" || exit 1
run "sed -n '/^pub struct sd_bus_vtable {/,/^}/p' vt.rs"
run "grep -E 'pub (const )?fn (type_|set_type|flags|set_flags|new_bitfield_1)\(' vt.rs"
# sd-bus vtables are static data in C, but new_bitfield_1() isn't a const fn.
cp "$HERE/vtuse.rs" .
run "$RUSTC --edition 2021 --crate-type lib --emit=metadata vtuse.rs -o vtuse.rmeta" && not_reproduced "new_bitfield_1() is const"

reproduced "function-like macros dropped, static inline functions only via C trampolines, bitfields as storage plus non-const accessors"
