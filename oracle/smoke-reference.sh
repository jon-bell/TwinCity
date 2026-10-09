#!/bin/sh
# Reference-layout smoke: San Francisco scenario, 3000 frames, frozen virtual clock, through
# twincity-reference (build-reference.sh). Checks determinism, the layout at ledger sites, and
# the outcome. On CI this runs natively on i386; locally it may run under qemu-i386, so a pass
# on both is the emulator cross-check. The expected lines are in oracle/baselines/
# (reference-layout.txt, reference.txt); changing them is guarded (CLAUDE.md).
. "$(dirname "$0")/common.sh"
B="$ORACLE/build/reference"; BIN="$B/twincity-reference"; RES="$B/tree/res/"
want_layout=$(cat "$ORACLE/baselines/reference-layout.txt")
want=$(cat "$ORACLE/baselines/reference.txt")
[ "$(cat "$B/LAYOUT")" = "$want_layout" ] || { printf 'FAIL layout moved:\n%s\n' "$(cat "$B/LAYOUT")"; exit 1; }
a=$("$BIN" "$RES" S2 3000 2>/dev/null | head -1); b=$("$BIN" "$RES" S2 3000 2>/dev/null | head -1)
[ "$a" = "$b" ] || { printf 'FAIL nondeterministic:\n %s\n %s\n' "$a" "$b"; exit 1; }
[ "$a" = "$want" ] || { printf 'FAIL baseline moved:\n got    %s\n expect %s\n' "$a" "$want"; exit 1; }
echo "ok  $a  ($(od -An -tx1 -j4 -N1 "$BIN" | tr -d ' ' | sed 's/01/32-bit/;s/02/64-bit/'), $(uname -m))"
