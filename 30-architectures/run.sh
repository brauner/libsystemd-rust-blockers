#!/bin/bash
# Many of our architectures have no rustc target, or only a tier 3 one.
. "$(dirname "$0")/../common.sh"
versions

A=$SYSTEMD_SRC/src/basic/architecture.h
P=$RUST_SRC/src/doc/rustc/src/platform-support.md
M=$($RUSTC --print sysroot)/lib/rustlib/multirust-channel-manifest.toml

run "git -C $SYSTEMD_SRC log -1 --format='systemd %h %cs' && git -C $RUST_SRC log -1 --format='rust %h %cs'"
run "grep -n '^ *ARCHITECTURE_[A-Z0-9_]*,$' $A | tr -d ' ,' | paste -s -d ' '"
$RUSTC --print target-list > targets
run "wc -l < targets; grep -c -- '-linux' targets"

# rustc target CPUs per architecture, empty if rustc has no such CPU.
declare -A CPU=(
        [ALPHA]="" [ARC]="" [ARC_BE]="" [CRIS]="" [IA64]="" [NIOS2]=""
        [PARISC]="" [PARISC64]="" [PPC_LE]="" [S390]="" [SH]="" [SH64]=""
        [TILEGX]=""
        [ARM]="arm armv4t armv5te armv7 thumbv7neon" [ARM_BE]="armeb"
        [ARM64]="aarch64" [ARM64_BE]="aarch64_be"
        [LOONGARCH64]="loongarch64" [M68K]="m68k"
        [MIPS]="mips mipsisa32r6" [MIPS_LE]="mipsel mipsisa32r6el"
        [MIPS64]="mips64 mipsisa64r6" [MIPS64_LE]="mips64el mipsisa64r6el"
        [PPC]="powerpc" [PPC64]="powerpc64" [PPC64_LE]="powerpc64le"
        [RISCV32]="riscv32gc" [RISCV64]="riscv64gc riscv64a23"
        [S390X]="s390x" [SPARC]="sparc" [SPARC64]="sparc64"
        [X86]="i586 i686" [X86_64]="x86_64" [X32]="x86_64"
)

# Tier by section of platform-support.md, "h" is with host tools.
declare -A TIER LINE
while read -r t tier line; do
        TIER[$t]=$tier LINE[$t]=$line
done < <(awk '/^## Tier 1 with Host/ { s = "1h" } /^## Tier 1 without/ { s = "1" }
        /^## Tier 2 with Host/ { s = "2h" } /^## Tier 2 without/ { s = "2" } /^## Tier 3/ { s = "3" }
        s && match($0, /^\[?`[^`]+`/) { t = substr($0, RSTART, RLENGTH); gsub(/[\[`]/, "", t); print t, s, NR }' "$P")
rank() { case $1 in 1h) echo 1;; 1) echo 2;; 2h) echo 3;; 2) echo 4;; 3) echo 5;; *) echo 9;; esac; }

shipped() {
        [ -f "$M" ] || { echo "n/a"; return; }
        grep -A1 -F "[pkg.rust-std.target.$1]" "$M" | grep -q 'available = true' && echo yes || echo no
}

# X32 isn't in the enum, it's X86_64 with __ILP32__ (architecture.h:65).
archs="$(sed -n 's/^ *ARCHITECTURE_\([A-Z0-9_]*\),$/\1/p' "$A") X32"

# architecture.h has an #error for these, so systemd doesn't build there.
run "grep -n 'error \"Missing LIB_ARCH_TUPLE' $A"
declare -A NOBUILD
for x in $(sed -n 's/.*error "Missing LIB_ARCH_TUPLE for \([A-Z0-9]*\)".*/\1/p' "$A"); do
        case $x in PPCLE) x=PPC_LE;; HPPA64) x=PARISC64;; esac
        NOBUILD[$x]=1
done

printf '\n%-12s %-36s %-4s %-7s %-4s %-5s %s\n' ARCH "BEST RUSTC TARGET (of N)" TIER MD-LINE 1.99 LLVM "RUST-STD -> VERDICT"
missing= nobuild= tier3= ok=
for a in $archs; do
        best= bestrank=9 n=0
        for t in $(grep -- '-unknown-linux-' targets); do
                cpu=${t%%-*}
                case $a:$t in
                X32:*gnux32) ;;
                X32:*|X86_64:*gnux32) continue ;;
                esac
                [[ " ${CPU[$a]} " == *" $cpu "* ]] || continue
                n=$((n + 1))
                r=$(rank "${TIER[$t]}")
                if [ "$r" -lt "$bestrank" ] || { [ "$r" -eq "$bestrank" ] && [ "${LINE[$t]}" -lt "${LINE[$best]}" ]; }; then
                        best=$t bestrank=$r
                fi
        done
        if [ -z "$best" ] && [ -n "${NOBUILD[$a]}" ]; then
                verdict="MISSING, no systemd build either" nobuild="$nobuild $a"
        elif [ -z "$best" ]; then
                verdict=MISSING missing="$missing $a"
        fi
        if [ -z "$best" ]; then
                printf '%-12s %-36s %-4s %-7s %-4s %-5s %s\n' "$a" "-" "-" "-" "-" "-" "- -> $verdict"
                continue
        fi
        llvm=no
        $RUSTC --print target-cpus --target "$best" >/dev/null 2>&1 && llvm=yes
        meta=$(RUSTC_BOOTSTRAP=1 $RUSTC -Z unstable-options --print target-spec-json --target "$best" | sed -n 's/^ *"tier": \([0-9]*\).*/\1/p')
        if [ "${TIER[$best]}" = 3 ]; then verdict=TIER3 tier3="$tier3 $a"; else verdict=OK ok="$ok $a"; fi
        printf '%-12s %-36s %-4s %-7s %-4s %-5s %s\n' "$a" "$best ($n)" "${TIER[$best]}" "${LINE[$best]}" "$meta" "$llvm" "$(shipped "$best") -> $verdict"
done

# No target for these CPUs on any other OS either.
run "grep -E '^(alpha|hppa|parisc|sh[0-9]?-|ia64|nios2|cris|tile|arc)' targets || echo 'no target for alpha, hppa/parisc, sh, ia64, nios2, cris, tile or arc'"

# Only a custom target can probe rustc's LLVM for a CPU, and it's unstable.
$RUSTC -vV > vv
RUSTC_BOOTSTRAP=1 $RUSTC -Z unstable-options --print target-spec-json --target x86_64-unknown-linux-gnu > base.json
run "$RUSTC --target ./base.json --print target-cpus 2>&1 | head -1"
for cpu in alpha hppa sh4 ia64 nios2 arc s390 tilegx m68k; do
        sed -e "s/\"llvm-target\": \"[^\"]*\"/\"llvm-target\": \"$cpu-unknown-linux-gnu\"/" \
            -e "s/\"arch\": \"[^\"]*\"/\"arch\": \"$cpu\"/" \
            -e "s/\"cpu\": \"[^\"]*\"/\"cpu\": \"generic\"/" base.json > $cpu.json
        run "RUSTC_BOOTSTRAP=1 $RUSTC -Z unstable-options --target ./$cpu.json --print target-cpus 2>&1 | head -1"
done

# m68k has an LLVM backend, but stable ships no core for it.
printf '#![no_std]\npub fn f(a: u32, b: u32) -> u32 { core::cmp::max(a, b) }\n' > lib.rs
run "$RUSTC --edition 2021 --crate-type rlib --target m68k-unknown-linux-gnu lib.rs 2>&1 | head -3"

# Building core from this rustc's own sources needs RUSTC_BOOTSTRAP.
hash=$(sed -n 's/^commit-hash: //p' vv)
if git -C "$RUST_SRC" archive "$hash" library/core library/stdarch library/portable-simd 2>/dev/null | tar -x; then
        run "$RUSTC --edition 2024 --crate-type rlib --crate-name core --target m68k-unknown-linux-gnu -O -Cpanic=abort library/core/src/lib.rs -o libcore.rlib 2>&1 | grep -m1 E0554"
        run "RUSTC_BOOTSTRAP=1 $RUSTC --edition 2024 --crate-type rlib --crate-name core --target m68k-unknown-linux-gnu -O -Cpanic=abort library/core/src/lib.rs -o libcore.rlib && ls libcore.rlib"
        # GCC 16 gets 2, 2, 10, 10 from layout.c, see README.md.
        cat > layout.rs <<'EOF'
#![no_std]
#[repr(C)] pub struct S { pub a: u8, pub b: u64 }
#[repr(C)] pub struct D { pub a: u8, pub b: f64 }
const _: [(); 0] = [(); core::mem::align_of::<u64>()];
const _: [(); 0] = [(); core::mem::align_of::<f64>()];
const _: [(); 0] = [(); core::mem::size_of::<S>()];
const _: [(); 0] = [(); core::mem::size_of::<D>()];
EOF
        run "RUSTC_BOOTSTRAP=1 $RUSTC --edition 2021 --crate-type rlib --target m68k-unknown-linux-gnu --extern core=libcore.rlib --emit=metadata layout.rs 2>&1 | grep -E '^[0-9]+ \| const|found one with' | sed 's/^ *|  *-* *\^* //'"
else
        echo "rustc commit $hash is not in $RUST_SRC, skipping the m68k core build"
fi

printf '\nMISSING:%s\nMISSING, systemd does not build there either:%s\nTIER3:%s\nOK:%s\n' "$missing" "$nobuild" "$tier3" "$ok"
[ -n "$missing" ] || not_reproduced "every architecture systemd builds on has a rustc target"
reproduced "$(echo $missing | wc -w) architectures systemd builds on have no rustc target ($(echo $missing | tr ' ' ,)), $(echo $tier3 | wc -w) only tier 3 ones"
