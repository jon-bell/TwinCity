/* Virtual clock. Every gettimeofday() in the oracle goes through here (link with
 * -Wl,--wrap=gettimeofday). With TWINCITY_VCLOCK_STEP_US unset, the clock is frozen
 * at TWINCITY_VCLOCK_EPOCH (default 631152000 = 1990-01-01T00:00:00Z); with it set,
 * each call advances by that many microseconds. Either way the run is deterministic.
 * Part of the recorder identity: changing this file changes ground truth. */
#include <stdlib.h>
#include <sys/time.h>
static long long vt_us = -1;
int __wrap_gettimeofday(struct timeval *tv, void *tz) {
  (void)tz;
  if (vt_us < 0) {
    const char *e = getenv("TWINCITY_VCLOCK_EPOCH");
    vt_us = (e ? atoll(e) : 631152000LL) * 1000000LL;
  }
  const char *s = getenv("TWINCITY_VCLOCK_STEP_US");
  if (s) vt_us += atoll(s);
  tv->tv_sec = (time_t)(vt_us / 1000000LL);
  tv->tv_usec = (suseconds_t)(vt_us % 1000000LL);
  return 0;
}
