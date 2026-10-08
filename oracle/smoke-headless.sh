#!/bin/sh
# Determinism smoke test: San Francisco scenario, 3000 frames, frozen virtual clock.
# The expected line is part of the spec; if it changes, the oracle changed. Re-baseline
# only together with a recorder-identity change and a note in ledger/.
. "$(dirname "$0")/common.sh"
BIN="$ORACLE/build/headless/twincity-headless"; RES="$ORACLE/build/headless/tree/res/"
# VoteProblems' out-of-bounds read/write is pinned to the reference layout by
# patches/0003 (ledger/0001, ruled), so this line no longer depends on how ld orders commons.
# It equals smoke-reference.sh's line: the headless and reference oracles agree.
EXPECT="map=429a71a41f09285b pop=101840 funds=19051 time=336 score=318 valves=1831,1500,1500 sprites=5"
a=$("$BIN" "$RES" S2 3000 | head -1); b=$("$BIN" "$RES" S2 3000 | head -1)
[ "$a" = "$b" ] || { echo "FAIL nondeterministic:\n $a\n $b"; exit 1; }
[ "$a" = "$EXPECT" ] || { echo "FAIL baseline moved:\n got    $a\n expect $EXPECT"; exit 1; }
echo "ok  $a"
