/* RNG draw log. Link with -Wl,--wrap=sim_rand. sim_rand lives alone in rand.c, so
 * every call from another translation unit is intercepted (Rand16, Rand16Signed and,
 * through them, Rand). When TWINCITY_RANDLOG names a file, each draw is written as
 *   <draw#> <value> <caller-pc> <caller's-caller-pc>
 * Resolve PCs to file:line offline with addr2line against an -O0 -g build.
 * TODO(phase 1): log the requested range by also wrapping Rand(); calls to Rand from
 * inside s_sim.c are not interceptable with --wrap, so that needs -finstrument-functions
 * or a probe macro (see docs/DESIGN.md, "--wrap misses calls within a file"). */
#include <execinfo.h>
#include <stdio.h>
#include <stdlib.h>
extern int __real_sim_rand(void);
static FILE *log_f; static int log_init; static long draws;
int __wrap_sim_rand(void) {
  int v = __real_sim_rand();
  if (!log_init) { const char *p = getenv("TWINCITY_RANDLOG"); log_init = 1; if (p) log_f = fopen(p, "w"); }
  draws++;
  if (log_f) {
    void *bt[4]; int d = backtrace(bt, 4);
    fprintf(log_f, "%ld %d %p %p\n", draws, v, d > 1 ? bt[1] : 0, d > 2 ? bt[2] : 0);
  }
  return v;
}
long twincity_rand_draws(void) { return draws; }
