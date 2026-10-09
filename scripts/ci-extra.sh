#!/bin/sh
# Agent-owned CI checks (CLAUDE.md, Guarded paths). ci.yml runs this as the last step of
# oracle-and-gates: as root in the swift:6.2-noble container, after every guarded step, with
# their build trees in oracle/build/. Add checks here (apt-get works); never weaken earlier ones.
set -eu
cd "$(dirname "$0")/.."

# P0.5 UB detector (oracle/build-detect.sh, run-detect.sh). Both fault modes first, each must go
# red for its own reason; then a clean build, which must be green. Writes only oracle/build/detect.
echo "== detector fault: swap (a non-inert compiled-out rewrite must be caught)"
if oracle/run-detect.sh --fault-swap > /tmp/detect-swap.out 2>&1; then
  cat /tmp/detect-swap.out; echo "FAIL --fault-swap passed"; exit 1; fi
grep -q "FAIL compiled-out rewrite moved the smoke line" /tmp/detect-swap.out || { cat /tmp/detect-swap.out; echo "FAIL --fault-swap: wrong reason"; exit 1; }
grep "^FAIL" /tmp/detect-swap.out | head -3
echo "== detector fault: plant (three planted UB sites must be reported)"
if oracle/run-detect.sh --fault-plant > /tmp/detect-plant.out 2>&1; then
  cat /tmp/detect-plant.out; echo "FAIL --fault-plant passed"; exit 1; fi
grep -q "^plant: all three planted sites reported" /tmp/detect-plant.out || { cat /tmp/detect-plant.out; echo "FAIL --fault-plant: planted sites missed"; exit 1; }
grep "^plant:" /tmp/detect-plant.out
echo "== detector"
oracle/build-detect.sh > /dev/null
oracle/run-detect.sh
