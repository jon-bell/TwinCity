#!/bin/sh
# Reference-layout oracle (ledger policy: reproduce the 1990 layout). The full original app,
# built as build-xvfb.sh does but 32-bit (-m32, ILP32 like the 1990 targets) and linked by the
# original makefile (src/sim/makefile), so every object and library is in the original link.
# Needs gcc-multilib and libx11/libxext/libxpm :i386; on a kernel without IA32 emulation the
# outputs run under qemu-i386 (see oracle/README.md).
#
# GNU ld places common symbols in link-hash-table order, which depends on every symbol in the
# link (ledger/0001), so layout is a property of the whole link. Two outputs share one link:
#   tree/src/sim/sim      the app, as the makefile links it
#   twincity-reference    the same link plus the headless driver, entered via --wrap=main
# check_layout below fails the build if their layouts at ledger sites differ.
. "$(dirname "$0")/common.sh"
# Perturbation only (ledger tables): WIDTH=64 builds the same thing for x86-64, into build/reference64.
if [ "${WIDTH:-32}" = 64 ]; then M=""; L="/usr/lib/x86_64-linux-gnu"; B="$ORACLE/build/reference64"
else M="-m32"; L="/usr/lib/i386-linux-gnu"; B="$ORACLE/build/reference"; fi
prepare_tree "$B/tree"
S="$B/tree/src"; X="$ORACLE/stubinc"
for so in X11 Xext Xpm; do [ -e "$L/lib$so.so" ] || { echo "missing $L/lib$so.so: apt-get install lib${so#X}-dev:i386" | tr A-Z a-z >&2; exit 2; }; done
if ! command -v yacc >/dev/null && ! command -v bison >/dev/null; then
  cp "$ORACLE/harness/tclxgdat-stub.c" "$S/tclx/src/tclxgdat.c"; echo "tclxgdat: stub" > "$B/GDAT"
else echo "tclxgdat: generated" > "$B/GDAT"; fi
P="$M ${OPT:--O1} -g $SPEC_CFLAGS ${EXTRA_CFLAGS:-}"
(cd "$S/tcl" && make CFLAGS="$P -I. -DTCL_LIBRARY=\\\"/usr/local/lib/tcl\\\"")
(cd "$S/tk" && make libtk.a CFLAGS="$P -I. -I$X -I/usr/include/X11 -I../tcl -DTK_VERSION=\\\"2.3\\\" -DUSE_XPM3")
(cd "$S/tclx" && make OPTIMIZE_FLAG="$P -DTCL_IEEE_FP_MATH -DDOMAIN=1 -DSING=2 -DOVERFLOW=3 -DUNDERFLOW=4 -DTLOSS=5 -DPLOSS=6 -I$X" \
   XPM_LIBS="-L$L -lXpm" TCL_TK_LIBS="-lX11 -lm -L$L -lXpm")
INC="-I$X -I$S/sim/headers -I$S/tcl -I$S/tk -I$S/tclx/src -I/usr/include/X11"
for f in wrap_clock wrap_rand probe_frame; do gcc -c $P $INC "$ORACLE/harness/$f.c" -o "$B/$f.o"; done
gcc -c $P $INC -Dmain=headless_main "$ORACLE/harness/headless_main.c" -o "$B/headless_main.o"
gcc -c $P $INC "$ORACLE/harness/reference_main.c" -o "$B/reference_main.o"
HARNESS="$B/wrap_clock.o $B/wrap_rand.o $B/probe_frame.o"
LIBS="../tclx/libtk.a ../tclx/libtcl.a -lm -L$L -lX11 -lXext -lXpm -Wl,--wrap=gettimeofday -Wl,--wrap=sim_rand -Wl,--wrap=UpdateFlush"
SIMINC="-Iheaders -I$X -I/usr/include/X11 -I../tcl -I../tclx/src -I../tk"
(cd "$S/sim" && make sim CFLAGS="$P -DNO_AIRCRASH" INCLUDES="$SIMINC" LIBS="$HARNESS $LIBS")
# Same command line as the makefile's `sim` rule, plus the driver object and --wrap=main.
(cd "$S/sim" && make -n sim CFLAGS="$P -DNO_AIRCRASH" INCLUDES="$SIMINC" LIBS="$HARNESS $LIBS" -W sim.o \
   | grep -- ' -o sim$' | sed "s# -o sim\$# $B/reference_main.o $B/headless_main.o -Wl,--wrap=main -o $B/twincity-reference#" > "$B/LINK")
# Fault mode (proves check_layout can fail): REFERENCE_FAULT=driver-symbols adds 30000
# unrelated function symbols to the driver link only, which reorders its commons.
if [ "${REFERENCE_FAULT:-}" = driver-symbols ]; then
  python3 -c "print(''.join('int zz_fault_%d(void){return %d;}\\n' % (i, i) for i in range(30000)))" > "$B/fault.c"
  gcc -c $P "$B/fault.c" -o "$B/fault.o"; sed -i "s# -o $B/twincity-reference\$# $B/fault.o&#" "$B/LINK"
fi
(cd "$S/sim" && sh "$B/LINK")
check_layout() {  # the driver must not move any ledger site's neighbours
  a=$("$ORACLE/../tools/layout-neighbour.py" "$S/sim/sim" "$@"); b=$("$ORACLE/../tools/layout-neighbour.py" "$B/twincity-reference" "$@")
  [ "$(echo "$a" | sed 's/ (0x.*//')" = "$(echo "$b" | sed 's/ (0x.*//')" ] || { echo "FAIL driver moved the layout:\n app:\n$a\n driver:\n$b" >&2; exit 1; }
  echo "$a" | sed 's/ (0x.*//'
}
check_layout ProblemTable 10 2 ProblemVotes 10 2 > "$B/LAYOUT"
cat "$B/LAYOUT"
echo "built $B/twincity-reference  (layout reference: $S/sim/sim)"
