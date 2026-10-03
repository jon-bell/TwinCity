#!/bin/sh
# Headless sim-only oracle: s_*.c + rand.c + the sim parts of w_*.c, X11/Tk stubbed.
# Fast per-function oracle. NOT the session oracle: it never runs the view paths
# (animateTiles, view shake draws, doMessage), so it matches the app only at speed 3
# with no views open. Output: oracle/build/headless/{twincity-headless,liboracle.a}
. "$(dirname "$0")/common.sh"
B="$ORACLE/build/headless"; prepare_tree "$B/tree"
S="$B/tree/src"
# -fPIC: the Swift test bundle is a shared object. Verified not to move the smoke baseline.
CF="${OPT:--O0} -g -fPIC $SPEC_CFLAGS -I$ORACLE/stubinc -I$S/sim/headers -I$S/tcl -I$S/tk -I$S/tclx/src"
SIM="s_alloc s_disast s_eval s_fileio s_gen s_init s_msg s_power s_scan s_sim s_traf s_zone
     rand random w_sprite w_tool w_budget w_util w_stubs w_eval w_update w_con w_resrc"
mkdir -p "$B/obj"
for f in $SIM; do gcc -c $CF "$S/sim/$f.c" -o "$B/obj/$f.o"; done
for f in headless_main ui_stubs xstubs wrap_clock wrap_rand; do gcc -c $CF "$ORACLE/harness/$f.c" -o "$B/obj/$f.o"; done
ar rcs "$B/liboracle.a" $(for f in $SIM ui_stubs xstubs wrap_clock wrap_rand; do echo "$B/obj/$f.o"; done)
gcc "$B/obj/headless_main.o" "$B/liboracle.a" -lm -Wl,--wrap=gettimeofday -Wl,--wrap=sim_rand -o "$B/twincity-headless"
echo "built $B/twincity-headless"
