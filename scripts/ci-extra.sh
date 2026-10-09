#!/bin/sh
# Agent-owned CI checks (CLAUDE.md, Guarded paths). ci.yml runs this as the last step of
# oracle-and-gates: as root in the swift:6.2-noble container, after every guarded step, with
# their build trees in oracle/build/. Add checks here (apt-get works); never weaken earlier ones.
set -eu
echo "ci-extra: no extra checks yet"
