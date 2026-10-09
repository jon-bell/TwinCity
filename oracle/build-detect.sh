#!/bin/sh
# UB detector build (docs/DESIGN.md, "Agentic loop", step 1): the headless oracle's sources and
# driver under ASan + UBSan + -ftrapv, -fno-common (ASan does not instrument commons) and
# -fno-wrapv (the spec's -fwrapv hides signed overflow), all recovering so one run reports
# every site (a -ftrapv trap aborts instead; ASan's handle_abort gives it a stack, so it is
# still reported at file:line, and the session fails). On top, oracle/detect/row-accessor.py
# rewrites every A[i][j] on the row-pointer maps (Map, PopDensity, ..., Qtem) into a
# bounds-checked TC_AT, which catches Map[x][100] (contiguous rows: invisible to ASan). It
# does not see accesses through raw pointers into the maps (w_con.c's TileAdrPtr[±1],
# [±WORLD_Y]). The rewrite is instrumentation-only; two outputs:
#   build/detect/twincity-detect      sanitizers + -DTC_DETECT       (run-detect.sh runs it)
#   build/detect/twincity-detect-off  the same rewritten tree, TC_AT compiled out, built exactly
#                                     as build-headless.sh builds; run-detect.sh asserts it gives
#                                     baselines/headless.txt and the headless build's code.
# Both link oracle/detect/resume.c (--wrap=SimFrame): it counts ticks and, with
# TWINCITY_DETECT_RESUME, answers the budget window. Unset, both run exactly the smoke driver.
# Detect-only files live in oracle/detect/, outside the recorder identity's inputs.
# Fault modes (run-detect.sh --fault-*): DETECT_FAULT=plant plants three UB sites in SimFrame
# (a global overflow and a signed overflow on s_sim.c:93, a Map row overrun on :105, which also
# checks the overrun lands on Map[4][0], read without TC_AT); DETECT_FAULT=swap makes the
# compiled-out TC_AT swap its subscripts; DETECT_FAULT=steer makes the detect-side TC_AT shift
# every column subscript by one. Neither is the original access.
. "$(dirname "$0")/common.sh"
B="$ORACLE/build/detect"; prepare_tree "$B/tree"
S="$B/tree/src"
SIM="s_alloc s_disast s_eval s_fileio s_gen s_init s_msg s_power s_scan s_sim s_traf s_zone
     rand random w_sprite w_tool w_budget w_util w_stubs w_eval w_update w_con w_resrc"
if [ "${DETECT_FAULT:-}" = plant ]; then  # same line count: fills the blank lines 93 and 105
  for n in 93 105; do sed -n ${n}p "$S/sim/s_sim.c" | grep -q '^$' || { echo "plant: s_sim.c:$n is not blank" >&2; exit 2; }; done
  sed -i '93s/.*/  { volatile int tc_k = 0; volatile short tc_p; volatile int tc_big = 2147483647; tc_p = FireStMap[SmX + tc_k][0]; tc_big = tc_big + (tc_k == 0); }/' "$S/sim/s_sim.c"
  sed -i '105s/.*/  { volatile short tc_p = Map[3][WORLD_Y]; if (\&Map[3][WORLD_Y] != *(Map + 4)) printf("plant: row overrun did not land on Map[4][0]\\n"); }/' "$S/sim/s_sim.c"
fi
"$ORACLE/detect/row-accessor.py" "$S/sim" $SIM | tee "$B/ROWS"
if [ "${DETECT_FAULT:-}" = steer ]; then
  sed -i 's/&A\[tc_a_\]\[tc_b_\]; }))/\&A[tc_a_][(tc_b_ + 1) % (Y)]; }))/' "$S/sim/headers/sim.h"
  grep -q '(tc_b_ + 1) % (Y)' "$S/sim/headers/sim.h" || { echo "steer fault did not apply" >&2; exit 2; }
fi
if [ "${DETECT_FAULT:-}" = swap ]; then
  sed -i 's/^#define TC_AT(A, X, Y, a, b) A\[a\]\[b\]$/#define TC_AT(A, X, Y, a, b) A[b][a]/' "$S/sim/headers/sim.h"
  grep -q 'A\[b\]\[a\]' "$S/sim/headers/sim.h" || { echo "swap fault did not apply" >&2; exit 2; }
fi
INC="-I$ORACLE/stubinc -I$S/sim/headers -I$S/tcl -I$S/tk -I$S/tclx/src"
SAN="-fno-common -fno-wrapv -ftrapv -fno-omit-frame-pointer -fsanitize=address,undefined,float-cast-overflow,float-divide-by-zero -fsanitize-recover=all"
build() {  # $1 = obj dir, $2 = output, $3 = extra cflags, $4 = extra ldflags
  CF="-O0 -g -fPIC $SPEC_CFLAGS $3 $INC"; mkdir -p "$1"
  for f in $SIM; do gcc -c $CF "$S/sim/$f.c" -o "$1/$f.o"; done
  for f in headless_main ui_stubs xstubs wrap_clock wrap_rand; do gcc -c $CF "$ORACLE/harness/$f.c" -o "$1/$f.o"; done
  gcc -c $CF "$ORACLE/detect/resume.c" -o "$1/resume.o"
  [ -z "$3" ] || gcc -c $CF "$ORACLE/detect/rowcheck.c" -o "$1/rowcheck.o"
  gcc $4 $(for f in headless_main $SIM ui_stubs xstubs wrap_clock wrap_rand resume; do echo "$1/$f.o"; done) \
    $([ -z "$3" ] || echo "$1/rowcheck.o") -lm -Wl,--wrap=gettimeofday -Wl,--wrap=sim_rand -Wl,--wrap=SimFrame -o "$2"
}
build "$B/obj" "$B/twincity-detect" "$SAN -DTC_DETECT" "-fsanitize=address,undefined"
build "$B/obj-off" "$B/twincity-detect-off" "" ""
echo "built $B/twincity-detect and $B/twincity-detect-off"
