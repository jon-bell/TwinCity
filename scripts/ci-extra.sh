#!/bin/sh
# Agent-owned CI checks (CLAUDE.md, Guarded paths). ci.yml runs this as the last step of
# oracle-and-gates: as root in the swift:6.2-noble container, after every guarded step, with
# their build trees in oracle/build/. Add checks here (apt-get works); never weaken earlier ones.
set -eu
cd "$(dirname "$0")/.."

# P0.5 UB detector (oracle/build-detect.sh, run-detect.sh). Every fault mode first, each must go
# red for its own reason; then a clean build, which must be green. Writes only oracle/build/detect.
fault() {  # $1 = runner, $2 = its fault flag, then the lines its output must contain
  r=$1; f=$2; shift 2; o=/tmp/$(basename $r .sh)$f.out
  echo "== $r fault $f"
  if $r $f > $o 2>&1; then cat $o; echo "FAIL $r $f passed"; exit 1; fi
  for want in "$@"; do grep -q -- "$want" $o || { cat $o; echo "FAIL $r $f: no line matching: $want"; exit 1; }; grep -m1 -- "$want" $o; done
}
oracle/detect/code-of.sh --self-test
# report.py fails closed: a detector line it can't attribute becomes site "?" and exit 1.
d=$(mktemp -d); echo "rowcheck: Map[3][100] at s_sim.c:105" > $d/x.log
if oracle/detect/report.py $d > $d/out; then cat $d/out; echo "FAIL report.py accepted an unattributable line"; exit 1; fi
grep -q '^?  rowcheck' $d/out || { cat $d/out; echo "FAIL report.py: no ? site"; exit 1; }; echo "report.py fails closed: $(cat $d/out)"; rm -rf $d
fault oracle/run-detect.sh --fault-swap "FAIL compiled-out rewrite moved the smoke line" "FAIL compiled-out rewrite changed the code of s_sim.o"
fault oracle/run-detect.sh --fault-plant "^plant: all three planted sites reported; the Map row overrun by rowcheck only, at its original address" \
  "^+sim/s_sim.c:93  asan  global-buffer-overflow" "^FAIL detect sites differ from baselines/detect-sites.txt"
fault oracle/run-detect.sh --fault-steer "FAIL S1: the detector changed the outcome" "FAIL yokohama.cty: the detector changed the outcome"
fault oracle/run-detect.sh --fault-noresume "FAIL S1 simulated 46 ticks (< 1000)" "FAIL finnigan.cty simulated 0 ticks (< 1000)"
echo "== detector"
oracle/build-detect.sh > /dev/null
oracle/run-detect.sh

# P0.5, session oracle (oracle/build-detect-xvfb.sh, run-detect-xvfb.sh): the same, on the Xvfb app
# with only src/sim instrumented. Needs build-xvfb.sh's tree (an earlier step). The fault runs use
# two sessions (S1, and finnigan.cty, which reaches ledger/0003); the clean run uses all 32.
# Writes only oracle/build/detect-xvfb.
export SESSIONS="S1 finnigan.cty"
fault oracle/run-detect-xvfb.sh --fault-swap "FAIL compiled-out rewrite changed the code of s_sim.o" "FAIL compiled-out rewrite, smoke session: RNG draw values differ"
fault oracle/run-detect-xvfb.sh --fault-plant "^plant: all three planted sites reported; the Map row overrun by rowcheck only, at its original address" \
  "^+sim/s_sim.c:93  asan  global-buffer-overflow" "^FAIL detect sites differ from baselines/detect-xvfb-sites.txt (sites only"
fault oracle/run-detect-xvfb.sh --fault-steer "FAIL S1: the detector changed the outcome: RNG draw values differ" "FAIL finnigan.cty: the detector changed the outcome: t3000.xwd"
oracle/build-detect-xvfb.sh > /dev/null  # clean; --fault-short only shortens the runs
echo "== detector (session oracle, the fault runs' two sessions, clean: must pass)"
oracle/run-detect-xvfb.sh > /tmp/detect-xvfb-subset.out 2>&1 || { cat /tmp/detect-xvfb-subset.out; echo "FAIL clean two-session run"; exit 1; }
tail -1 /tmp/detect-xvfb-subset.out
fault oracle/run-detect-xvfb.sh --fault-short "FAIL S1: CityTime advanced 18 (< 150)" "FAIL finnigan.cty: CityTime advanced 17 (< 150)" "FAIL S1: trace has 300 of 3000 ticks"
unset SESSIONS
echo "== detector (session oracle)"
oracle/run-detect-xvfb.sh
