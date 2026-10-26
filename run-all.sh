#!/bin/bash
# Run every reproducer, or the ones whose name starts with $1, and keep the
# output in logs/ with local paths replaced by the variable they come from.
cd "$(dirname "$0")" || exit 1
CONFIG_ONLY=1 . ./common.sh

bre() { printf '%s\n' "$1" | sed 's/[][\.*^$]/\\&/g'; }

S="s|$(bre "${TMPDIR:-/tmp}")/repro\.[A-Za-z0-9]\{6\}|\$W|g"
S+=$'\n'"s|$(bre "$COMMON_DIR")/||g"
for v in SYSTEMD_SRC RUST_SRC BINDGEN GCCRS GCCRS_B; do
        [[ ${!v} == /* ]] && S+=$'\n'"s|$(bre "${!v}")|\$$v|g"
done
S+=$'\n'"s|$(bre "$HOME")|~|g"

mkdir -p logs
for d in [0-9][0-9]-*/; do
        d=${d%/}
        [ -n "$1" ] && [[ $d != $1* ]] && continue
        bash "$d/run.sh" 2>&1 | sed -e "$S" > "logs/$d.log"
        printf '%-40s %s\n' "$d" "$(grep -h '^RESULT:' "logs/$d.log" | tail -1)"
done
