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
# Fault modes (run-detect.sh --fault-*): DETECT_FAULT=plant|steer|swap, see oracle/detect/faults.sh.
. "$(dirname "$0")/common.sh"
B="$ORACLE/build/detect"; prepare_tree "$B/tree"
S="$B/tree/src"
SIM="s_alloc s_disast s_eval s_fileio s_gen s_init s_msg s_power s_scan s_sim s_traf s_zone
     rand random w_sprite w_tool w_budget w_util w_stubs w_eval w_update w_con w_resrc"
. "$ORACLE/detect/faults.sh"
[ "${DETECT_FAULT:-}" = plant ] && fault_plant "$S/sim"
"$ORACLE/detect/row-accessor.py" "$S/sim" $SIM | tee "$B/ROWS"
[ "${DETECT_FAULT:-}" = steer ] && fault_steer "$S/sim"
[ "${DETECT_FAULT:-}" = swap ] && fault_swap "$S/sim"
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
