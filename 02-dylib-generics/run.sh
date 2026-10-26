#!/bin/bash
# Generic code of a Rust shared library ends up in every program.
. "$(dirname "$0")/../common.sh"
versions

fail=0
for O in 2 3 s; do
        R="-C panic=abort -C opt-level=$O"
        mkdir o$O && cd o$O || exit 1
        printf '\n######## -C opt-level=%s\n' $O
        run "$RUSTC --edition 2021 --crate-type dylib $R $HERE/sdshared.rs" || exit 1
        # The library has sort_unique::<u32> but can't have sort_unique::<Uid>.
        for v in plain generic own_type; do
                run "$RUSTC --edition 2021 $R --cfg $v -A unused $HERE/user.rs -L . --extern sdshared=libsdshared.so -o $v" || exit 1
                run "LD_LIBRARY_PATH=. ./$v"
        done
        for v in plain generic own_type; do
                printf '\n## %s: .text %s bytes\n' $v "$(size -A $v | awk '$1==".text"{print $2}')"
                echo "   Rust code imported from libsdshared.so:"
                nm -C -D --undefined-only $v | grep -E '(sdshared|core)::' | sed 's/^ *U /     /'
                echo "   Rust code compiled into the program:"
                nm -C -S --defined-only $v | awk '$3 ~ /[tT]/' | grep -E '(sdshared|core)::' | \
                        awk '{printf "     %5d  ", strtonum("0x"$2); $1=$2=$3=""; print}'
        done
        nm -C --defined-only own_type | grep -q 'quicksort::<user::Uid' || fail=1
        cd ..
done

# Sharing instantiations across crates is -Zshare-generics, a nightly option.
run "$RUSTC --edition 2021 -Zshare-generics=yes $HERE/user.rs -L o2 --extern sdshared=o2/libsdshared.so -o x"

[ $fail -eq 0 ] || not_reproduced "a program used the library's code for its own type"
reproduced "generic library code for the program's own types is compiled into every program"
