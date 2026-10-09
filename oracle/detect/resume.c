/* Detect driver shim (build-detect.sh links it with --wrap=SimFrame into both detect builds).
 * With TWINCITY_DETECT_RESUME set, a paused sim is resumed at speed 3 before each frame: the
 * headless driver has nobody to answer the budget window, which Pause()s the sim
 * (w_budget.c:321), and most sessions would otherwise stop after a few dozen ticks. Unset, the
 * shim only counts. At exit it prints `detect: ticks=N` (CityTime advanced) on stdout. */
#include "sim.h"
void __real_SimFrame(void);
static int start_set, resume;
static QUAD start;
static void done(void) { printf("detect: ticks=%ld\n", (long)(CityTime - start)); fflush(stdout); }
void __wrap_SimFrame(void) {
  if (!start_set) { start_set = 1; start = CityTime; resume = getenv("TWINCITY_DETECT_RESUME") != NULL; atexit(done); }
  if (resume && sim_paused) { sim_paused = 0; SimSpeed = 3; }
  __real_SimFrame();
}
