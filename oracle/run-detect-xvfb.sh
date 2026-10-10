#!/bin/sh
# Runs the session oracle's UB detector build (build-detect-xvfb.sh) under a private Xvfb on
# the frame-stepped scheduler, and reports each site once, as file:line (oracle/detect/report.py),
# into build/detect-xvfb/SITES. The sessions: every scenario (-s 1..8) and every city in
# res/cities, STOP ticks each (scenarios S2, S3, S5 and S7 end near tick 3850, when the
# scheduler has nothing left to run and exits 3; STOP stays below that), views open, so the UI-side sim code headless stubs out (sim.c,
# the g_* views, w_update's date and message path) runs too. Then it checks:
#   1. off/sim (rewritten tree, checks compiled out) has the session oracle's code, object by
#      object (oracle/detect/code-of.sh), and reproduces smoke-xvfb.sh's run a: the per-tick
#      trace, the RNG draw values and the pixels of both captures;
#   2. on every session, san/sim gives the session oracle's (build/xvfb) trace, RNG draw values
#      and final-tick pixels (the sanitizers, -fno-wrapv, -fno-common and TC_AT observe, they
#      don't steer), and both exit 0 after STOP ticks;
#   3. every session's CityTime advances at least MIN_CT from tick 10 (a city loads at tick 3) to
#      STOP: the sim really ran.
#   4. SITES equals baselines/detect-xvfb-sites.txt (a new site, or a vanished one, is a finding).
# Fault modes, each must FAIL (CI asserts it): --fault-plant, --fault-swap, --fault-steer rebuild
# with DETECT_FAULT=plant|swap|steer (oracle/detect/faults.sh): plant must report all three
# planted sites, the Map row overrun by rowcheck only and at its original address (it always
# exits non-zero, so CI also greps for the "plant: all" line); swap must fail check 1; steer
# must fail check 2. --fault-short runs every session for STOP/10 ticks, so check 3 must fail.
# SESSIONS overrides the session list (CI's fault runs use two). Needs oracle/build/xvfb.
. "$(dirname "$0")/common.sh"
X="$ORACLE/build/xvfb"; T="$X/tree"; REF="$T/src/sim/sim"; B="$ORACLE/build/detect-xvfb"
STOP=3000; MIN_CT=150; fail=0
case "${1:-}" in
  --fault-plant) DETECT_FAULT=plant "$ORACLE/build-detect-xvfb.sh" >/dev/null ;;
  --fault-swap)  DETECT_FAULT=swap  "$ORACLE/build-detect-xvfb.sh" >/dev/null ;;
  --fault-steer) DETECT_FAULT=steer "$ORACLE/build-detect-xvfb.sh" >/dev/null ;;
  --fault-short|"") ;;
  *) echo "usage: $0 [--fault-plant|--fault-swap|--fault-steer|--fault-short]" >&2; exit 2 ;;
esac
RUN_STOP=$STOP; [ "${1:-}" = --fault-short ] && RUN_STOP=$((STOP / 10))
SESSIONS=${SESSIONS:-"S1 S2 S3 S4 S5 S6 S7 S8 $(cd "$T/cities" && ls *.cty | tr '\n' ' ')"}
D=${TWINCITY_DISPLAY:-:92}
Xvfb "$D" -screen 0 1280x1024x24 -nolisten tcp -fp "$T/res/dejavu-lgc/,/usr/share/fonts/X11/misc/,built-ins" >/dev/null 2>&1 &
XP=$!; trap 'kill $XP 2>/dev/null' EXIT; sleep 1
export ASAN_OPTIONS=detect_leaks=0:halt_on_error=0:abort_on_error=0:handle_abort=1 UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=0
L="$B/logs"; rm -rf "$L"; mkdir -p "$L"
run() {  # $1 = binary, $2 = out dir, $3 = caps, $4 = stop, $5 = session; stderr -> $2/log
  mkdir -p "$2"; a="-s ${5#S}"; [ "${5#S}" = "$5" ] && a="$T/cities/$5"; rc=0
  (cd "$T" && SIMHOME="$T" DISPLAY="$D" TWINCITY_CAPS="$3" TWINCITY_STOP="$4" TWINCITY_OUT="$2" \
     TWINCITY_RANDLOG="$2/rand.log" TWINCITY_TRACE="$2/trace" TWINCITY_DETECT_LOG="$2/log" \
     timeout 900 "$1" $a >"$2/stdout" 2>>"$2/log") || rc=$?
  cut -d' ' -f1,2 "$2/rand.log" > "$2/rand.vals" 2>/dev/null || :
  echo $rc > "$2/rc"
}
same() {  # $1 = label, $2 = got dir, $3 = expected dir: trace, RNG values, every capture
  ok=0
  cmp -s "$2/trace" "$3/trace" || { echo "FAIL $1: per-tick trace differs from tick $(diff "$2/trace" "$3/trace" | sed -n '1s/[^0-9].*//p')"; ok=1; }
  cmp -s "$2/rand.vals" "$3/rand.vals" || { echo "FAIL $1: RNG draw values differ"; ok=1; }
  for f in "$3"/*.xwd; do
    [ -f "$f" ] || { echo "FAIL $1: no captures in $3"; ok=1; break; }
    ae=$(compare -metric AE "$f" "$2/$(basename "$f")" null: 2>&1 || true)
    [ "$ae" = 0 ] || { echo "FAIL $1: $(basename "$f"): $ae pixels differ"; ok=1; }
  done
  return $ok
}
# 1. compiled-out code and the smoke session (smoke-xvfb.sh: S2, captures at 200 and 400).
for o in "$T"/src/sim/*.o; do
  f=$(basename "$o")
  [ -f "$B/off/tree/src/sim/$f" ] || { echo "FAIL no off/tree/src/sim/$f"; fail=1; continue; }
  [ "$("$ORACLE/detect/code-of.sh" "$B/off/tree/src/sim/$f" | md5sum)" = "$("$ORACLE/detect/code-of.sh" "$o" | md5sum)" ] \
    || { echo "FAIL compiled-out rewrite changed the code of $f"; fail=1; }
done
run "$REF" "$L/smoke.ref" 200,400 400 S2; run "$B/off/sim" "$L/smoke.off" 200,400 400 S2
same "compiled-out rewrite, smoke session" "$L/smoke.off" "$L/smoke.ref" || fail=1
# 2-3. every session under the detector, against the session oracle.
: > "$B/CITYTIME"
for s in $SESSIONS; do
  run "$REF" "$L/$s.ref" $RUN_STOP $RUN_STOP "$s"; run "$B/san/sim" "$L/$s" $RUN_STOP $RUN_STOP "$s"
  for v in "$s" "$s.ref"; do
    [ "$(cat "$L/$v/rc")" = 0 ] || { echo "FAIL $v exited $(cat "$L/$v/rc") (see $L/$v/log)"; fail=1; }
    n=$(wc -l < "$L/$v/trace" 2>/dev/null || echo 0)
    [ "$n" -eq $STOP ] || { echo "FAIL $v: trace has $n of $STOP ticks"; fail=1; }
  done
  same "$s: the detector changed the outcome" "$L/$s" "$L/$s.ref" || fail=1
  ct=$(awk 'NR == 10 { a = $2 } END { print $2 - a }' "$L/$s/trace" 2>/dev/null); echo "$s ${ct:-0}" >> "$B/CITYTIME"
  [ "${ct:-0}" -ge $MIN_CT ] || { echo "FAIL $s: CityTime advanced ${ct:-0} (< $MIN_CT)"; fail=1; }
done
mkdir -p "$B/sitelogs"; rm -f "$B/sitelogs"/*; for s in $SESSIONS; do cp "$L/$s/log" "$B/sitelogs/$s.log"; done
"$ORACLE/detect/report.py" "$B/sitelogs" > "$B/SITES" || { echo "FAIL report.py could not attribute every detector line (see '?' sites)"; fail=1; }
echo "detect-xvfb sites ($(wc -l < "$B/CITYTIME") sessions x $RUN_STOP ticks; CityTime advanced $(sort -k2n "$B/CITYTIME" | head -1 | cut -d' ' -f2)..$(sort -k2n "$B/CITYTIME" | tail -1 | cut -d' ' -f2)):"
sed 's/^/  /' "$B/SITES"
if [ "${1:-}" = --fault-plant ]; then
  missed=0
  for k in "93  asan  global-buffer-overflow" "93  ubsan  signed integer overflow" "105  rowcheck  Map subscript"; do
    grep -q "^sim/s_sim.c:$k" "$B/SITES" || { echo "plant: MISSED s_sim.c:$k"; missed=1; }
  done
  grep -q "^sim/s_sim.c:105  asan" "$B/SITES" && { echo "plant: ASan saw the row overrun (expected it blind; is the rowcheck still needed?)"; missed=1; }
  grep -qh "^plant: row overrun did not land" "$L"/*/stdout && { echo "plant: TC_AT did not perform the original access"; missed=1; }
  [ $missed = 0 ] && echo "plant: all three planted sites reported; the Map row overrun by rowcheck only, at its original address"
  fail=1
fi
diff -u "$ORACLE/baselines/detect-xvfb-sites.txt" "$B/SITES" || { echo "FAIL detect sites differ from baselines/detect-xvfb-sites.txt"; fail=1; }
[ $fail = 0 ] && echo "ok  detector (session oracle): compiled-out rewrite is inert; detector doesn't steer; sites match baseline"
exit $fail
