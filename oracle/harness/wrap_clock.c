/* Virtual clock. Every gettimeofday() in the oracle goes through here (link with
 * -Wl,--wrap=gettimeofday). With TWINCITY_VCLOCK_STEP_US unset, the clock is frozen
 * at TWINCITY_VCLOCK_EPOCH (default 631152000 = 1990-01-01T00:00:00Z); with it set,
 * each call advances by that many microseconds. Either way the run is deterministic.
 * When the frame-stepped scheduler (sched.c) is linked and on, it owns the clock: the
 * step is ignored and time moves only through twincity_vclock_set.
 * Part of the recorder identity: changing this file changes ground truth. */
#include <stdlib.h>
#include <sys/time.h>
static long long vt_us = -1;
extern int twincity_sched_owns_clock(void) __attribute__((weak));
static void vclock_init(void) {
  if (vt_us < 0) {
    const char *e = getenv("TWINCITY_VCLOCK_EPOCH");
    vt_us = (e ? atoll(e) : 631152000LL) * 1000000LL;
  }
}
long long twincity_vclock_us(void) { vclock_init(); return vt_us; }
void twincity_vclock_set(long long us) { vclock_init(); vt_us = us; }
int __wrap_gettimeofday(struct timeval *tv, void *tz) {
  (void)tz;
  vclock_init();
  if (!(twincity_sched_owns_clock && twincity_sched_owns_clock())) {
    const char *s = getenv("TWINCITY_VCLOCK_STEP_US");
    if (s) vt_us += atoll(s);
  }
  tv->tv_sec = (time_t)(vt_us / 1000000LL);
  tv->tv_usec = (suseconds_t)(vt_us % 1000000LL);
  return 0;
}
