/* Per-tick capture hook for the Xvfb oracle. Link with -Wl,--wrap=UpdateFlush
 * (UpdateFlush runs at the end of every sim_update, including Kick-driven ones).
 *   TWINCITY_CAPS=t1,t2,...  xwd the root window at those ticks into $TWINCITY_OUT
 *   TWINCITY_STOP=n          exit after tick n
 * TODO(phase 1): dump the logical frame (per-view tile cache, sprites, overlay state,
 * widget text) here instead of only screenshots. See docs/DESIGN.md, "Visual fidelity". */
#include "sim.h"
extern struct XDisplay *XDisplays;
extern long twincity_rand_draws(void);
static int ticks;
void __real_UpdateFlush(void);
void __wrap_UpdateFlush(void) {
  char cmd[600], key[32], list[600];
  struct XDisplay *xd;
  char *caps = getenv("TWINCITY_CAPS");
  int stop = getenv("TWINCITY_STOP") ? atoi(getenv("TWINCITY_STOP")) : 0;
  __real_UpdateFlush();
  ticks++;
  for (xd = XDisplays; xd; xd = xd->next) XSync(xd->dpy, False);
  if (caps) {
    sprintf(key, ",%d,", ticks); snprintf(list, sizeof list, ",%s,", caps);
    if (strstr(list, key)) {
      snprintf(cmd, sizeof cmd, "xwd -root -silent -display %s > %s/t%04d.xwd",
               getenv("DISPLAY"), getenv("TWINCITY_OUT") ? getenv("TWINCITY_OUT") : ".", ticks);
      system(cmd);
      fprintf(stderr, "TICK %d CityTime %d ShakeNow %d flagBlink %d draws %ld\n",
              ticks, (int)CityTime, ShakeNow, flagBlink, twincity_rand_draws());
    }
  }
  if (stop && ticks >= stop) { fprintf(stderr, "STOP at tick %d\n", ticks); exit(0); }
}
