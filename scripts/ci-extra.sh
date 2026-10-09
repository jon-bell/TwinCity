#!/bin/sh
# Agent-owned CI checks (CLAUDE.md, Guarded paths). ci.yml runs this as the last step of
# oracle-and-gates: as root in the swift:6.2-noble container, after every guarded step, with
# their build trees in oracle/build/. Add checks here (apt-get works); never weaken earlier ones.
set -eu
cd "$(dirname "$0")/.."

# P0.5 UB detector (oracle/build-detect.sh, run-detect.sh). Every fault mode first, each must go
# red for its own reason; then a clean build, which must be green. Writes only oracle/build/detect.
fault() {  # $1 = run-detect.sh flag, then the lines its output must contain
  f=$1; shift; o=/tmp/detect$f.out
  echo "== detector fault $f"
  if oracle/run-detect.sh $f > $o 2>&1; then cat $o; echo "FAIL $f passed"; exit 1; fi
  for want in "$@"; do grep -q -- "$want" $o || { cat $o; echo "FAIL $f: no line matching: $want"; exit 1; }; grep -m1 -- "$want" $o; done
}
oracle/detect/code-of.sh --self-test
fault --fault-swap "FAIL compiled-out rewrite moved the smoke line" "FAIL compiled-out rewrite changed the code of s_sim.o"
fault --fault-plant "^plant: all three planted sites reported; the Map row overrun by rowcheck only, at its original address"
fault --fault-steer "FAIL S1: the detector changed the outcome" "FAIL yokohama.cty: the detector changed the outcome"
fault --fault-noresume "FAIL S1 simulated 46 ticks (< 1000)" "FAIL finnigan.cty simulated 0 ticks (< 1000)"
echo "== detector"
oracle/build-detect.sh > /dev/null
oracle/run-detect.sh
