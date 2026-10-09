#!/bin/sh
# Runs the UB detector build (build-detect.sh) over the detect sessions and reports each
# site once, as file:line (oracle/detect/report.py), into build/detect/SITES. The sessions:
# every scenario S1..S8 and every city in res/cities, 20000 frames each on the headless driver,
# with TWINCITY_DETECT_RESUME answering the budget window (ticks per session: build/detect/TICKS).
# Then it checks:
#   1. twincity-detect-off (rewritten tree, checks compiled out) reproduces baselines/headless.txt
#      on the smoke session, and its code (disassembly with relocations, and data sections) is
#      identical to the headless build's, object by object;
#   2. the sanitized build reproduces baselines/headless.txt on the smoke session, and gives the
#      same first line as twincity-detect-off on every detect session (the sanitizers, -fno-wrapv
#      and TC_AT observe, they don't steer);
#   3. every session simulates at least MIN_TICKS ticks;
#   4. SITES equals baselines/detect-sites.txt (a new site, or a vanished one, is a finding).
# Fault modes, each must FAIL (CI asserts it): --fault-plant rebuilds with DETECT_FAULT=plant
# and reports whether all three planted sites were found, the Map row overrun by rowcheck only
# (ASan can't see it) and at its original address; it always exits non-zero, so CI also greps
# for the "plant: all" line. --fault-swap rebuilds with DETECT_FAULT=swap, so check 1 must catch
# a non-original TC_AT. Needs oracle/build/headless (build-headless.sh) for check 1.
. "$(dirname "$0")/common.sh"
B="$ORACLE/build/detect"; RES="$B/tree/res/"; FRAMES=20000; MIN_TICKS=1000; fail=0
case "${1:-}" in
  --fault-plant) DETECT_FAULT=plant "$ORACLE/build-detect.sh" >/dev/null ;;
  --fault-swap)  DETECT_FAULT=swap  "$ORACLE/build-detect.sh" >/dev/null ;;
  "") ;; *) echo "usage: $0 [--fault-plant|--fault-swap]" >&2; exit 2 ;;
esac
want=$(cat "$ORACLE/baselines/headless.txt")
off=$("$B/twincity-detect-off" "$RES" S2 3000 | head -1)
[ "$off" = "$want" ] || { printf 'FAIL compiled-out rewrite moved the smoke line:\n got    %s\n expect %s\n' "$off" "$want"; fail=1; }
code_of() {  # disassembly with relocations, plus every non-debug data section (ignores line info)
  objdump -dr "$1" | tail -n +4
  for s in $(objdump -h "$1" | awk '$2 ~ /^\./ {print $2}'); do
    case $s in .text*|.rela.text*|.debug*|.rela.debug*|.comment|.note*|.group) ;;
      .rela*) readelf -rW "$1" | sed -n "/'$s'/,/^$/p" | awk 'NR>2 {print $3, $5, $6, $7}' ;;
      *) objdump -s -j "$s" "$1" | tail -n +4 ;; esac
  done
}
for f in s_alloc s_disast s_eval s_fileio s_gen s_init s_msg s_power s_scan s_sim s_traf s_zone \
         rand random w_sprite w_tool w_budget w_util w_stubs w_eval w_update w_con w_resrc; do
  h="$ORACLE/build/headless/obj/$f.o"
  [ -f "$h" ] || { echo "FAIL no $h (run build-headless.sh)"; fail=1; continue; }
  [ "$(code_of "$B/obj-off/$f.o" | md5sum)" = "$(code_of "$h" | md5sum)" ] \
    || { echo "FAIL compiled-out rewrite changed the code of $f.o"; fail=1; }
done
L="$B/logs"; rm -rf "$L"; mkdir -p "$L"; : > "$B/TICKS"
export ASAN_OPTIONS=detect_leaks=0:halt_on_error=0:abort_on_error=0:handle_abort=1 UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=0
for s in S1 S2 S3 S4 S5 S6 S7 S8 $(cd "$B/tree/cities" && ls *.cty); do
  a=$s; [ "${s#S}" = "$s" ] && a="$B/tree/cities/$s"
  rc=0; TWINCITY_DETECT_RESUME=1 TWINCITY_DETECT_LOG="$L/$s.log" "$B/twincity-detect" "$RES" "$a" $FRAMES >"$L/$s.out" 2>>"$L/$s.log" || rc=$?
  [ $rc = 0 ] || { echo "FAIL $s exited $rc under the detector"; fail=1; }
  ref=$(TWINCITY_DETECT_RESUME=1 "$B/twincity-detect-off" "$RES" "$a" $FRAMES | head -1)
  [ "$(head -1 "$L/$s.out")" = "$ref" ] || { printf 'FAIL %s: the detector changed the outcome:\n got    %s\n expect %s\n' "$s" "$(head -1 "$L/$s.out")" "$ref"; fail=1; }
  t=$(sed -n 's/^detect: ticks=//p' "$L/$s.out"); echo "$s $t" >> "$B/TICKS"
  [ "${t:-0}" -ge $MIN_TICKS ] || { echo "FAIL $s simulated ${t:-?} ticks (< $MIN_TICKS)"; fail=1; }
done
smoke=$("$B/twincity-detect" "$RES" S2 3000 2>/dev/null | head -1)
[ "$smoke" = "$want" ] || { printf 'FAIL sanitized smoke run moved:\n got    %s\n expect %s\n' "$smoke" "$want"; fail=1; }
"$ORACLE/detect/report.py" "$L" > "$B/SITES" || { echo "FAIL report.py could not attribute every detector line (see '?' sites)"; fail=1; }
echo "detect sites ($(wc -l < "$B/TICKS") sessions x $FRAMES frames; ticks $(sort -k2n "$B/TICKS" | head -1 | cut -d' ' -f2)..$(sort -k2n "$B/TICKS" | tail -1 | cut -d' ' -f2)):"
sed 's/^/  /' "$B/SITES"
if [ "${1:-}" = --fault-plant ]; then
  missed=0
  for k in "93  asan  global-buffer-overflow" "93  ubsan  signed integer overflow" "105  rowcheck  Map subscript"; do
    grep -q "^sim/s_sim.c:$k" "$B/SITES" || { echo "plant: MISSED s_sim.c:$k"; missed=1; }
  done
  grep -q "^sim/s_sim.c:105  asan" "$B/SITES" && { echo "plant: ASan saw the row overrun (expected it blind; is the rowcheck still needed?)"; missed=1; }
  grep -qh "^plant: row overrun did not land" "$L"/*.out && { echo "plant: TC_AT did not perform the original access"; missed=1; }
  [ $missed = 0 ] && echo "plant: all three planted sites reported; the Map row overrun by rowcheck only, at its original address"
  fail=1
fi
diff -u "$ORACLE/baselines/detect-sites.txt" "$B/SITES" || { echo "FAIL detect sites differ from baselines/detect-sites.txt"; fail=1; }
[ $fail = 0 ] && echo "ok  detector: compiled-out rewrite is inert; detector doesn't steer; sites match baseline"
exit $fail
