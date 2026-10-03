#!/bin/sh
# Session oracle: the full original app (Tcl 6.7 / Tk 2.3 / TclX, bundled) for Xvfb.
# Needs X11 client libs (libX11, libXext, libXpm runtime). Headers for XShm/shape/xpm are
# substituted from stubinc/ if the -dev packages are absent. Output: oracle/build/xvfb/tree/src/sim/sim
. "$(dirname "$0")/common.sh"
B="$ORACLE/build/xvfb"; prepare_tree "$B/tree"
S="$B/tree/src"; X="$ORACLE/stubinc"; L="$B/lib"; mkdir -p "$L"
for so in Xext Xpm; do
  [ -e "/usr/lib/x86_64-linux-gnu/lib$so.so" ] || ln -sf "$(ls /usr/lib/x86_64-linux-gnu/lib$so.so.* | head -1)" "$L/lib$so.so"
done
if ! command -v yacc >/dev/null && ! command -v bison >/dev/null; then
  cp "$ORACLE/harness/tclxgdat-stub.c" "$S/tclx/src/tclxgdat.c"; echo "tclxgdat: stub" > "$B/GDAT"
else echo "tclxgdat: generated" > "$B/GDAT"; fi
P="${OPT:--O1} -g $SPEC_CFLAGS"
(cd "$S/tcl" && make CFLAGS="$P -I. -DTCL_LIBRARY=\\\"/usr/local/lib/tcl\\\"")
(cd "$S/tk" && make libtk.a CFLAGS="$P -I. -I$X -I/usr/include/X11 -I../tcl -DTK_VERSION=\\\"2.3\\\" -DUSE_XPM3")
(cd "$S/tclx" && make OPTIMIZE_FLAG="$P -DTCL_IEEE_FP_MATH -DDOMAIN=1 -DSING=2 -DOVERFLOW=3 -DUNDERFLOW=4 -DTLOSS=5 -DPLOSS=6 -I$X" \
   XPM_LIBS="-L$L -lXpm" TCL_TK_LIBS="-lX11 -lm -L$L -lXpm")
for f in wrap_clock wrap_rand probe_frame; do
  gcc -c $P -I$X -I"$S/sim/headers" -I"$S/tcl" -I"$S/tk" -I"$S/tclx/src" -I/usr/include/X11 "$ORACLE/harness/$f.c" -o "$B/$f.o"
done
(cd "$S/sim" && make sim CFLAGS="$P -DNO_AIRCRASH" \
   INCLUDES="-Iheaders -I$X -I/usr/include/X11 -I../tcl -I../tclx/src -I../tk" \
   LIBS="$B/wrap_clock.o $B/wrap_rand.o $B/probe_frame.o ../tclx/libtk.a ../tclx/libtcl.a -lm -L$L -lX11 -lXext -lXpm -Wl,--wrap=gettimeofday -Wl,--wrap=sim_rand -Wl,--wrap=UpdateFlush")
echo "built $S/sim/sim  (run: see oracle/README.md)"
