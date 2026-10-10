#!/bin/sh
# UB detector build of the session oracle (P0.5, second half): the full app as build-xvfb.sh
# builds it, with only src/sim instrumented. Tcl/Tk/TclX and the harness objects are the
# session oracle's own (oracle/build/xvfb, uninstrumented), linked against the ASan runtime.
# src/sim gets oracle/detect/row-accessor.py over every file in its makefile (the headless
# set plus sim.c, the g_* views, w_keys and w_sim), then two builds from that one tree:
#   build/detect-xvfb/san/sim  $SAN -DTC_DETECT, at the session oracle's -O level
#   build/detect-xvfb/off/sim  TC_AT compiled out, with build-xvfb.sh's flags and link;
#                              run-detect-xvfb.sh asserts its code equals build/xvfb's.
# Fault modes (run-detect-xvfb.sh --fault-*): DETECT_FAULT=plant|steer|swap, see
# oracle/detect/faults.sh. Needs oracle/build/xvfb (build-xvfb.sh).
. "$(dirname "$0")/common.sh"
X="$ORACLE/build/xvfb"; XT="$X/tree/src"
for f in "$XT/tclx/libtk.a" "$XT/tclx/libtcl.a" "$X/wrap_clock.o" "$X/wrap_rand.o" "$X/probe_frame.o" "$X/sched.o"; do
  [ -f "$f" ] || { echo "no $f (run build-xvfb.sh)" >&2; exit 2; }
done
B="$ORACLE/build/detect-xvfb"; rm -rf "$B"; mkdir -p "$B"; prepare_tree "$B/tree"
S="$B/tree/src/sim"; L="$X/lib"; I="$ORACLE/stubinc"
SIM=$(sed -n '/^SRCS = /,/^$/p' "$S/makefile" | grep -o '[a-z_]*\.c' | sed 's/\.c$//' | tr '\n' ' ')
. "$ORACLE/detect/faults.sh"
[ "${DETECT_FAULT:-}" = plant ] && fault_plant "$S"
"$ORACLE/detect/row-accessor.py" "$S" $SIM | tee "$B/ROWS"
[ "${DETECT_FAULT:-}" = steer ] && fault_steer "$S"
[ "${DETECT_FAULT:-}" = swap ] && fault_swap "$S"
P="${OPT:--O1} -g $SPEC_CFLAGS"
SAN="-fno-common -fno-wrapv -ftrapv -fno-omit-frame-pointer -fsanitize=address,undefined,float-cast-overflow,float-divide-by-zero -fsanitize-recover=all"
# Each variant gets its own tree/src/sim beside symlinks to the session oracle's built tcl, tk
# and tclx. Sources compile by absolute path, so sanitizer reports name tree/src/sim/FILE:LINE
# (report.py's attribution). The off build adds -fmacro-prefix-map, which keeps __FILE__ (assert's
# strings) the makefile's relative name; the san build doesn't, since rowcheck reports __FILE__.
# The compile line is otherwise the makefile's implicit rule.
build() {  # $1 = variant dir, $2 = extra cflags ($V expands to the variant's src), $3 = extra link inputs
  V="$1/tree/src"; mkdir -p "$V"; cp -a "$S" "$V/sim"
  for d in tcl tk tclx; do ln -s "$XT/$d" "$V/$d"; done
  CF="$P -DNO_AIRCRASH $(eval echo "$2")"; INC="-I$V/sim/headers -I$I -I/usr/include/X11 -I$V/tcl -I$V/tclx/src -I$V/tk"
  for f in $SIM; do gcc $CF $INC -c -o "$V/sim/$f.o" "$V/sim/$f.c"; done
  gcc $CF -L/usr/X11/lib -L/usr/X11R6/lib $INC $(for f in $SIM; do echo "$V/sim/$f.o"; done) $3 \
    "$X/wrap_clock.o" "$X/wrap_rand.o" "$X/probe_frame.o" "$X/sched.o" "$V/tclx/libtk.a" "$V/tclx/libtcl.a" \
    -lm -L"$L" -lX11 -lXext -lXpm -Wl,--wrap=gettimeofday -Wl,--wrap=sim_rand -Wl,--wrap=UpdateFlush \
    -Wl,--wrap=Tk_CreateTimerHandler,--wrap=Tk_CreateMicroTimerHandler,--wrap=Tk_DeleteTimerHandler,--wrap=Tk_DoOneEvent,--wrap=Tk_MainLoop,--wrap=Tk_Sleep \
    -o "$1/sim"
}
gcc -c $P $SAN -DTC_DETECT -I"$S/headers" -I"$I" -I"$XT/tcl" -I"$XT/tk" -I"$XT/tclx/src" -I/usr/include/X11 "$ORACLE/detect/rowcheck.c" -o "$B/rowcheck.o"
build "$B/san" "$SAN -DTC_DETECT" "$B/rowcheck.o"
build "$B/off" '-fmacro-prefix-map=$V/sim/=' ""
echo "built $B/san/sim and $B/off/sim"
