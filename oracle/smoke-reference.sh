#!/bin/sh
# Reference-layout smoke: San Francisco scenario, 3000 frames, frozen virtual clock, through
# twincity-reference (build-reference.sh). Checks determinism, the layout at ledger sites, and
# the outcome. On CI this runs natively on i386; locally it may run under qemu-i386, so a pass
# on both is the emulator cross-check. The expected lines change only with ledger/0001's ruling.
. "$(dirname "$0")/common.sh"
B="$ORACLE/build/reference"; BIN="$B/twincity-reference"; RES="$B/tree/res/"
EXPECT_LAYOUT="ProblemTable[10] -> CityPop+0
ProblemVotes[10] -> EvalValid+0"
EXPECT="map=429a71a41f09285b pop=101840 funds=19051 time=336 score=318 valves=1831,1500,1500 sprites=5"
[ "$(cat "$B/LAYOUT")" = "$EXPECT_LAYOUT" ] || { printf 'FAIL layout moved:\n%s\n' "$(cat "$B/LAYOUT")"; exit 1; }
a=$("$BIN" "$RES" S2 3000 2>/dev/null | head -1); b=$("$BIN" "$RES" S2 3000 2>/dev/null | head -1)
[ "$a" = "$b" ] || { printf 'FAIL nondeterministic:\n %s\n %s\n' "$a" "$b"; exit 1; }
[ "$a" = "$EXPECT" ] || { printf 'FAIL baseline moved:\n got    %s\n expect %s\n' "$a" "$EXPECT"; exit 1; }
echo "ok  $a  ($(od -An -tx1 -j4 -N1 "$BIN" | tr -d ' ' | sed 's/01/32-bit/;s/02/64-bit/'), $(uname -m))"
