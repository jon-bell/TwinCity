#!/bin/sh
# Determinism smoke test: San Francisco scenario, 3000 frames, frozen virtual clock.
# The expected line (oracle/baselines/headless.txt) is part of the spec; if it changes, the
# oracle changed. Changing it is guarded (CLAUDE.md): a ruled ledger entry or a jon-ruled issue.
. "$(dirname "$0")/common.sh"
BIN="$ORACLE/build/headless/twincity-headless"; RES="$ORACLE/build/headless/tree/res/"
# VoteProblems' out-of-bounds read/write is pinned to the reference layout by
# patches/0003 (ledger/0001, ruled), so this line no longer depends on how ld orders commons.
# It equals baselines/reference.txt: the headless and reference oracles agree.
want=$(cat "$ORACLE/baselines/headless.txt")
a=$("$BIN" "$RES" S2 3000 | head -1); b=$("$BIN" "$RES" S2 3000 | head -1)
[ "$a" = "$b" ] || { echo "FAIL nondeterministic:\n $a\n $b"; exit 1; }
[ "$a" = "$want" ] || { echo "FAIL baseline moved:\n got    $a\n expect $want"; exit 1; }
echo "ok  $a"
