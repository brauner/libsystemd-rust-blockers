#!/bin/bash
# At our 1.85 MSRV, ld.lld drops a Rust #[used] section entry under --gc-sections.
. "$(dirname "$0")/../common.sh"
versions

# codegen-units=1 keeps the entry in the object that defines rust_init().
R="--edition 2021 -O -C panic=abort -C codegen-units=1 --crate-type staticlib"

run "$CC -O2 -c $HERE/main.c" || exit 1
# The C entry has the R (SHF_GNU_RETAIN) flag.
run "readelf -SW main.o | grep -w my_set"

# The explicit form is unstable.
run "$RUSTC --edition 2021 --crate-type lib $HERE/used-linker.rs -o x.rlib"

declare -A result
for rc in "$RUSTC" "$RUSTC_OLD"; do
        v=$($rc --version | cut -d' ' -f2)
        printf '\n######## rustc %s\n' "$v"
        run "$rc $R $HERE/entry.rs -o libentry-$v.a" || exit 1
        run "readelf -SW libentry-$v.a | grep -w my_set"
        for ld in bfd lld; do
                for z in "" start-stop-gc nostart-stop-gc; do
                        run "$CC -fuse-ld=$ld -Wl,--gc-sections${z:+ -Wl,-z,$z} main.o libentry-$v.a -o t" || exit 1
                        o=$(./t)
                        printf '$ ./t\n%s\n' "$o"
                        [[ $o == *"entry: rust"* ]] && result[$v $ld ${z:-default}]=kept || result[$v $ld ${z:-default}]=DROPPED
                done
        done
done

# What lld says about the MSRV build's entry.
v=$($RUSTC_OLD --version | cut -d' ' -f2)
run "$CC -fuse-ld=lld -Wl,--gc-sections -Wl,--print-gc-sections main.o libentry-$v.a -o t 2>&1 | grep my_set"

printf '\n%-8s %-6s %-17s %s\n' rustc linker "-z" "Rust entry"
for k in "${!result[@]}"; do
        printf '%-8s %-6s %-17s %s\n' $k "${result[$k]}"
done | sort -k1,1r -k2,2 -k3,3

old=$($RUSTC_OLD --version | cut -d' ' -f2)
new=$($RUSTC --version | cut -d' ' -f2)
[ "${result[$old lld default]}" = DROPPED ] || not_reproduced "ld.lld keeps the #[used] entry of rustc $old"
reproduced "rustc $old, our MSRV, doesn't mark the #[used] section SHF_GNU_RETAIN and ld.lld drops the entry, rustc $new keeps it"
