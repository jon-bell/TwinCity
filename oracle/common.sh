# Shared by the oracle build scripts. Sourced, not executed.
set -eu
ORACLE="$(cd "$(dirname "$0")" && pwd)"
UPSTREAM="$ORACLE/upstream/micropolis-activity"
[ -f "$UPSTREAM/src/sim/s_sim.c" ] || { echo "oracle/upstream missing: git submodule update --init" >&2; exit 2; }
# The spec (docs/DESIGN.md): 32-bit QUAD via -DOSF1, wrapping signed overflow, no FP contraction.
SPEC_CFLAGS="-std=gnu89 -fcommon -fno-strict-aliasing -fwrapv -ffp-contract=off -w -DIS_LINUX -DOSF1"
prepare_tree() {  # $1 = build dir; copies upstream and applies patches/*.patch in order
  rm -rf "$1"; mkdir -p "$1"
  cp -a "$UPSTREAM/." "$1/"
  for p in "$ORACLE"/patches/*.patch; do
    [ -e "$p" ] || continue
    patch -s -d "$1" -p1 < "$p"
  done
}
