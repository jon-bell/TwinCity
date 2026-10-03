#!/bin/sh
# Determinism smoke test: San Francisco scenario, 3000 frames, frozen virtual clock.
# The expected line is part of the spec; if it changes, the oracle changed. Re-baseline
# only together with a recorder-identity change and a note in ledger/.
. "$(dirname "$0")/common.sh"
BIN="$ORACLE/build/headless/twincity-headless"; RES="$ORACLE/build/headless/tree/res/"
# 322, not 318: -fcommon puts CityScore right after ProblemVotes, and VoteProblems writes
# ProblemVotes[10] (s_eval.c:217). See ledger/0001-voteproblems-oob.md.
EXPECT="map=98af6a0ddc02df38 pop=97840 funds=19089 time=336 score=322 valves=1890,1500,1500 sprites=7"
a=$("$BIN" "$RES" S2 3000 | head -1); b=$("$BIN" "$RES" S2 3000 | head -1)
[ "$a" = "$b" ] || { echo "FAIL nondeterministic:\n $a\n $b"; exit 1; }
[ "$a" = "$EXPECT" ] || { echo "FAIL baseline moved:\n got    $a\n expect $EXPECT"; exit 1; }
echo "ok  $a"
