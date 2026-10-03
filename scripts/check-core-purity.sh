#!/bin/sh
# TwinCityCore must stay a pure, dependency-free, deterministic Swift module.
set -eu
cd "$(dirname "$0")/.."
fail=0
bad() { echo "core-purity: $1"; fail=1; }
# 1. No imports at all (no Foundation/Glibc/Darwin/COracle).
grep -rnE '^\s*(@_?[a-zA-Z]+\s+)*import\s' Sources/TwinCityCore && bad "TwinCityCore must not import anything"
# 2. Banned APIs: hidden nondeterminism, concurrency, unsafe memory, hashed collections.
# (comments are stripped first, so docs may name the banned APIs)
BANNED='\.random\(|SystemRandomNumberGenerator|RandomNumberGenerator|Clock|Date\(|\basync\b|\bawait\b|\bactor\b|Task[ ({]|Dispatch|Unsafe[A-Z]|\bDictionary\b|\bSet<|\[[A-Za-z0-9_]+ *: *[A-Za-z0-9_]+\]\('
for f in $(find Sources/TwinCityCore -name '*.swift'); do
  hits=$(sed 's://.*$::' "$f" | grep -nE "$BANNED" || true)
  [ -n "$hits" ] && { echo "$hits" | sed "s|^|$f:|"; bad "banned API in $f (see docs/DESIGN.md, Swift side)"; }
done
# 3. The target declares no dependencies.
grep -A3 'name: "TwinCityCore"' Package.swift | grep -q 'dependencies: \[\]' || bad "TwinCityCore must declare dependencies: []"
[ $fail = 0 ] && echo "core-purity: ok"
exit $fail
