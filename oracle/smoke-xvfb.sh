#!/bin/sh
# Determinism smoke test for the session oracle: the full app under a private Xvfb on the
# frame-stepped scheduler (harness/sched.c), San Francisco scenario, screenshots at fixed
# ticks. Run twice at two host speeds (b sleeps SLOW_US real microseconds per tick) and
# byte-compare every channel: the per-tick trace (CityTime, draws, virtual clock, shake,
# speed), the RNG log, and the pixels. Identical at both speeds is the P1.1 proof.
# Fault mode: SMOKE_FAULT=wallclock leaks real time into the virtual clock; this must FAIL.
. "$(dirname "$0")/common.sh"
T="$ORACLE/build/xvfb/tree"; BIN="$T/src/sim/sim"
D=${TWINCITY_DISPLAY:-:91}; TICKS=${TICKS:-40,80}; STOP=${STOP:-80}; SLOW_US=${SLOW_US:-20000}
OUT="$ORACLE/build/xvfb/smoke"; rm -rf "$OUT"; mkdir -p "$OUT/a" "$OUT/b"
Xvfb "$D" -screen 0 1280x1024x24 -nolisten tcp -fp "$T/res/dejavu-lgc/,/usr/share/fonts/X11/misc/,built-ins" >/dev/null 2>&1 &
XP=$!; trap 'kill $XP 2>/dev/null' EXIT; sleep 1
for r in a b; do
  delay=0; [ $r = b ] && delay=$SLOW_US
  (cd "$T" && SIMHOME="$T" DISPLAY="$D" TWINCITY_CAPS="$TICKS" TWINCITY_STOP="$STOP" \
     TWINCITY_OUT="$OUT/$r" TWINCITY_RANDLOG="$OUT/$r/rand.log" TWINCITY_TRACE="$OUT/$r/trace" \
     env TWINCITY_WALL_DELAY_US=$delay ${SMOKE_FAULT:+TWINCITY_SCHED_FAULT=$SMOKE_FAULT} \
     timeout 300 "$BIN" -s 2 >"$OUT/$r/stdout" 2>"$OUT/$r/stderr") || true
done
grep TICK "$OUT/a/stderr" || true
fail=0
# Compare PIXELS (xwd headers carry window ids) and draw VALUES (logged caller PCs move with ASLR).
for f in "$OUT"/a/*.xwd; do
  ae=$(compare -metric AE "$f" "$OUT/b/$(basename "$f")" null: 2>&1 || true)
  [ "$ae" = "0" ] || { echo "FAIL $(basename "$f"): $ae pixels differ"; fail=1; }
done
cut -d' ' -f1,2 "$OUT/a/rand.log" > "$OUT/a/rand.vals"; cut -d' ' -f1,2 "$OUT/b/rand.log" > "$OUT/b/rand.vals"
cmp -s "$OUT/a/rand.vals" "$OUT/b/rand.vals" || { echo "FAIL RNG draw values differ"; fail=1; }
[ -s "$OUT/a/trace" ] || { echo "FAIL no trace (see $OUT/a/stderr)"; fail=1; }
cmp -s "$OUT/a/trace" "$OUT/b/trace" || { echo "FAIL per-tick trace differs between host speeds:"; diff "$OUT/a/trace" "$OUT/b/trace" | head -4; fail=1; }
ls "$OUT"/a/*.xwd >/dev/null 2>&1 || { echo "FAIL no captures (see $OUT/a/stderr)"; fail=1; }
[ $fail = 0 ] && echo "ok  $(ls "$OUT"/a/*.xwd | wc -l) captures pixel-identical, $(wc -l < "$OUT/a/rand.log") RNG draws and $(wc -l < "$OUT/a/trace") ticks identical at two host speeds (+${SLOW_US}us/tick)"
exit $fail
