#!/bin/sh
# Runs the UB detector build (build-detect.sh) over the detect sessions and reports each
# site once, as file:line (oracle/detect/report.py), into build/detect/SITES. The sessions:
# every scenario S1..S8 and every city in res/cities, FRAMES (default 20000) frames each on the
# headless driver; S2 is the headless smoke session. Then it checks:
#   1. twincity-detect-off (rewritten tree, checks compiled out) reproduces baselines/headless.txt,
#      and its code (disassembly with relocations, and data sections) is identical to the
#      headless build's, object by object;
#   2. the sanitized run of the smoke session also reproduces baselines/headless.txt
#      (the sanitizers and TC_AT observe, they don't steer);
#   3. SITES equals baselines/detect-sites.txt (a new site, or a vanished one, is a finding).
# Fault modes, each must FAIL (CI asserts it): --fault-plant rebuilds with DETECT_FAULT=plant
# and reports whether all three planted sites were found, the Map row overrun by rowcheck only
# (ASan can't see it); it always exits non-zero, so CI also greps for the "plant: all" line;
# --fault-swap rebuilds with DETECT_FAULT=swap, so check 1 must catch a non-original TC_AT.
# Needs oracle/build/headless (build-headless.sh) for the .text comparison.
. "$(dirname "$0")/common.sh"
B="$ORACLE/build/detect"; RES="$B/tree/res/"; FRAMES=${FRAMES:-20000}; fail=0
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
    case $s in .text*|.rela*|.debug*|.comment|.note*|.group) ;; *) objdump -s -j "$s" "$1" | tail -n +4 ;; esac
  done
}
for o in "$B"/obj-off/*.o; do
  h="$ORACLE/build/headless/obj/$(basename "$o")"
  [ -f "$h" ] || { echo "FAIL no $h (run build-headless.sh)"; fail=1; continue; }
  [ "$(code_of "$o" | md5sum)" = "$(code_of "$h" | md5sum)" ] \
    || { echo "FAIL compiled-out rewrite changed the code of $(basename "$o")"; fail=1; }
done
L="$B/logs"; rm -rf "$L"; mkdir -p "$L"
export ASAN_OPTIONS=detect_leaks=0:halt_on_error=0:abort_on_error=0 UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=0
for s in S1 S2 S3 S4 S5 S6 S7 S8 $(cd "$B/tree/cities" && ls *.cty); do
  a=$s; [ "${s#S}" = "$s" ] && a="$B/tree/cities/$s"
  TWINCITY_DETECT_LOG="$L/$s.log" "$B/twincity-detect" "$RES" "$a" "$FRAMES" >"$L/$s.out" 2>>"$L/$s.log" \
    || { echo "FAIL $s exited $? under the detector"; fail=1; }
done
smoke=$("$B/twincity-detect" "$RES" S2 3000 2>/dev/null | head -1)
[ "$smoke" = "$want" ] || { printf 'FAIL sanitized smoke run moved:\n got    %s\n expect %s\n' "$smoke" "$want"; fail=1; }
"$ORACLE/detect/report.py" "$L" > "$B/SITES"
echo "detect sites ($(ls "$L"/*.log | wc -l) sessions x $FRAMES frames):"; sed 's/^/  /' "$B/SITES"
if [ "${1:-}" = --fault-plant ]; then
  missed=0
  for k in "93  asan  global-buffer-overflow" "93  ubsan  signed integer overflow" "105  rowcheck  Map subscript"; do
    grep -q "^sim/s_sim.c:$k" "$B/SITES" || { echo "plant: MISSED s_sim.c:$k"; missed=1; }
  done
  grep -q "^sim/s_sim.c:105  asan" "$B/SITES" && { echo "plant: ASan saw the row overrun (expected it blind; is the rowcheck still needed?)"; missed=1; }
  [ $missed = 0 ] && echo "plant: all three planted sites reported; the Map row overrun by rowcheck only"
  fail=1
fi
if [ "${FRAMES}" = 20000 ]; then
  diff -u "$ORACLE/baselines/detect-sites.txt" "$B/SITES" || { echo "FAIL detect sites differ from baselines/detect-sites.txt"; fail=1; }
fi
[ $fail = 0 ] && echo "ok  detector: compiled-out rewrite is inert; sanitized smoke unchanged; sites match baseline"
exit $fail
