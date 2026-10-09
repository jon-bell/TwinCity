#!/bin/sh
# Determinism smoke test for the session oracle: the full app under a private Xvfb on the
# frame-stepped scheduler (harness/sched.c), San Francisco scenario, screenshots at fixed
# ticks. Run twice at two host speeds (b sleeps SLOW_US real microseconds per tick) and
# byte-compare every channel: the per-tick trace (CityTime, draws, virtual clock, shake,
# speed, blink), the RNG log, and the pixels. Identical at both speeds is the P1.1 proof.
# 400 ticks of S2 include the earthquake and its 3000 ms end, so timing reaches behaviour.
# Both runs must exit 0 and produce every tick and capture, and b must really be slower.
# Fault mode: SMOKE_FAULT=wallclock leaks real time into the virtual clock; this must FAIL,
# on behavioural channels (RNG, pixels, CityTime/shake/blink), not only the clock column.
. "$(dirname "$0")/common.sh"
T="$ORACLE/build/xvfb/tree"; BIN="$T/src/sim/sim"
D=${TWINCITY_DISPLAY:-:91}; TICKS=${TICKS:-200,400}; STOP=${STOP:-400}; SLOW_US=${SLOW_US:-20000}
[ "$SLOW_US" -gt 0 ] || { echo "FAIL SLOW_US must be > 0 (the two runs must differ in host speed)"; exit 1; }
OUT="$ORACLE/build/xvfb/smoke"; rm -rf "$OUT"; mkdir -p "$OUT/a" "$OUT/b"
Xvfb "$D" -screen 0 1280x1024x24 -nolisten tcp -fp "$T/res/dejavu-lgc/,/usr/share/fonts/X11/misc/,built-ins" >/dev/null 2>&1 &
XP=$!; trap 'kill $XP 2>/dev/null' EXIT; sleep 1
for r in a b; do
  delay=0; [ $r = b ] && delay=$SLOW_US; rc=0
  (cd "$T" && SIMHOME="$T" DISPLAY="$D" TWINCITY_CAPS="$TICKS" TWINCITY_STOP="$STOP" \
     TWINCITY_OUT="$OUT/$r" TWINCITY_RANDLOG="$OUT/$r/rand.log" TWINCITY_TRACE="$OUT/$r/trace" \
     env TWINCITY_WALL_DELAY_US=$delay ${SMOKE_FAULT:+TWINCITY_SCHED_FAULT=$SMOKE_FAULT} \
     timeout 600 "$BIN" -s 2 >"$OUT/$r/stdout" 2>"$OUT/$r/stderr") || rc=$?
  echo $rc > "$OUT/$r/rc"
done
grep TICK "$OUT/a/stderr" || true
fail=0
ncaps=$(echo "$TICKS" | tr ',' '\n' | grep -c .)
for r in a b; do
  [ "$(cat "$OUT/$r/rc")" = 0 ] || { echo "FAIL run $r exited $(cat "$OUT/$r/rc") (see $OUT/$r/stderr)"; fail=1; }
  [ "$(wc -l < "$OUT/$r/trace" 2>/dev/null || echo 0)" -eq "$STOP" ] || { echo "FAIL run $r: trace has $(wc -l < "$OUT/$r/trace" 2>/dev/null) of $STOP ticks"; fail=1; }
  [ "$(ls "$OUT/$r"/*.xwd 2>/dev/null | wc -l)" -eq "$ncaps" ] || { echo "FAIL run $r: $(ls "$OUT/$r"/*.xwd 2>/dev/null | wc -l) of $ncaps captures"; fail=1; }
done
# Compare PIXELS (xwd headers carry window ids) and draw VALUES (logged caller PCs move with ASLR).
for f in "$OUT"/a/*.xwd; do
  ae=$(compare -metric AE "$f" "$OUT/b/$(basename "$f")" null: 2>&1 || true)
  [ "$ae" = "0" ] || { echo "FAIL $(basename "$f"): $ae pixels differ"; fail=1; }
done
cut -d' ' -f1,2 "$OUT/a/rand.log" > "$OUT/a/rand.vals"; cut -d' ' -f1,2 "$OUT/b/rand.log" > "$OUT/b/rand.vals"
cmp -s "$OUT/a/rand.vals" "$OUT/b/rand.vals" || { echo "FAIL RNG draw values differ"; fail=1; }
[ -s "$OUT/a/trace" ] || { echo "FAIL no trace (see $OUT/a/stderr)"; fail=1; }
cmp -s "$OUT/a/trace" "$OUT/b/trace" || { echo "FAIL per-tick trace differs between host speeds:"; diff "$OUT/a/trace" "$OUT/b/trace" | head -4; fail=1; }
# Behaviour without the clock column, reported separately so a fault shows where it lands.
cut -d' ' -f1-3,5- "$OUT/a/trace" > "$OUT/a/behav"; cut -d' ' -f1-3,5- "$OUT/b/trace" > "$OUT/b/behav"
cmp -s "$OUT/a/behav" "$OUT/b/behav" || { echo "FAIL behaviour (CityTime/draws/shake/speed/blink) differs from tick $(diff "$OUT/a/behav" "$OUT/b/behav" | sed -n '1s/[^0-9].*//p')"; fail=1; }
[ $fail = 0 ] && echo "ok  $(ls "$OUT"/a/*.xwd | wc -l) captures pixel-identical, $(wc -l < "$OUT/a/rand.log") RNG draws and $(wc -l < "$OUT/a/trace") ticks identical at two host speeds (+${SLOW_US}us/tick)"
exit $fail
