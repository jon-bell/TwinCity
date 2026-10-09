/* Frame-stepped scheduler for the Xvfb oracle (docs/PLAN.md P1.1). Link with
 *   -Wl,--wrap=Tk_CreateTimerHandler,--wrap=Tk_CreateMicroTimerHandler,
 *   --wrap=Tk_DeleteTimerHandler,--wrap=Tk_DoOneEvent,--wrap=Tk_MainLoop,--wrap=Tk_Sleep
 * Every caller of these is outside tkevent.c, so --wrap sees all of them; Tk_MainLoop's own
 * Tk_DoOneEvent call is the one exception, which is why Tk_MainLoop is replaced too.
 *
 * Model: an infinitely fast host. Virtual time (wrap_clock.c) stands still while the app
 * works and moves only when the app would block. Before anything that could block, every
 * display is XSync'ed and the X queue and idle callbacks are drained; only when nothing is
 * left does the clock jump to the next timer, which then fires. So the sim timer (ticks),
 * the earthquake end, the budget countdown and DropFireBombs (Tcl `after`) all fire at
 * virtual times that are a function of the session alone, never of wall-clock speed.
 *
 * Timers live in our queue, not Tk's, with tkevent.c's arithmetic and ordering copied
 * exactly, quirks included (C: tclx/tkucbsrc/tkevent.c:928-1105, the copy libtk.a links;
 * tk/tkevent.c differs only in TclX signal checks):
 *  - Tk_CreateTimerHandler and Tk_CreateMicroTimerHandler keep *separate* id counters, so
 *    their tokens collide, and Tk_DeleteTimerHandler removes the first match in queue order;
 *  - usec is normalised with `> 1000000`, so 1000000 is a legal usec;
 *  - a new timer goes after every timer due at the same time or earlier (FIFO on ties);
 *  - a timer fires when strictly earlier than now, so it runs at due + 1 us;
 *  - Tk_DoOneEvent's phase order: X/file events, then one *due* timer, then the delayed
 *    motion event, then idle handlers, then wait. Timers that tie with the one that moved the
 *    clock are due at once, so they fire back to back, before idle handlers and inside
 *    `update` (TK_DONT_WAIT), as in Tk.
 * TWINCITY_SCHED=off passes everything through to real Tk (the old harness: virtual time
 * stepped per gettimeofday call, which couples it to host speed only sporadically).
 * TWINCITY_SCHED_FAULT=wallclock is the planted fault for smoke-xvfb.sh: each timer firing
 * also adds the real time elapsed since the previous one, so recordings must then differ
 * between host speeds. Part of the recorder identity. */
#include "sim.h"

typedef struct VTimer {
  long sec, usec;
  Tk_TimerProc *proc;
  ClientData clientData;
  Tk_TimerToken token;
  struct VTimer *next;
} VTimer;

static VTimer *queue;
static int sched = -1;

extern long long twincity_vclock_us(void);
extern void twincity_vclock_set(long long us);
Tk_TimerToken __real_Tk_CreateTimerHandler(int, Tk_TimerProc *, ClientData);
Tk_TimerToken __real_Tk_CreateMicroTimerHandler(int, int, Tk_TimerProc *, ClientData);
void __real_Tk_DeleteTimerHandler(Tk_TimerToken);
int __real_Tk_DoOneEvent(int);
int __real_gettimeofday(struct timeval *, void *);
void __real_Tk_MainLoop(void);
void __real_Tk_Sleep(int);

int twincity_sched_owns_clock(void) {
  if (sched < 0) { const char *e = getenv("TWINCITY_SCHED"); sched = !(e && !strcmp(e, "off")); }
  return sched;
}

static Tk_TimerToken insert(long sec, long usec, Tk_TimerProc *proc, ClientData cd, int id) {
  VTimer *t = malloc(sizeof *t), *t2, *prev;
  if (!t) { fprintf(stderr, "twincity-sched: out of memory\n"); exit(3); }
  t->sec = sec; t->usec = usec; t->proc = proc; t->clientData = cd;
  t->token = (Tk_TimerToken)(long)id;
  for (t2 = queue, prev = NULL; t2 != NULL; prev = t2, t2 = t2->next)
    if ((t2->sec > sec) || ((t2->sec == sec) && (t2->usec > usec))) break;
  if (prev == NULL) { t->next = queue; queue = t; } else { t->next = prev->next; prev->next = t; }
  return t->token;
}

Tk_TimerToken __wrap_Tk_CreateTimerHandler(int milliseconds, Tk_TimerProc *proc, ClientData cd) {
  static int id = 0;
  struct timeval tv; long sec, usec;
  if (!twincity_sched_owns_clock()) return __real_Tk_CreateTimerHandler(milliseconds, proc, cd);
  gettimeofday(&tv, NULL);
  sec = tv.tv_sec + milliseconds/1000; usec = tv.tv_usec + (milliseconds%1000)*1000;
  if (usec > 1000000) { usec -= 1000000; sec += 1; }   /* C: tkucbsrc/tkevent.c:946 (sic: >) */
  id++;
  return insert(sec, usec, proc, cd, id);
}

Tk_TimerToken __wrap_Tk_CreateMicroTimerHandler(int seconds, int microseconds, Tk_TimerProc *proc, ClientData cd) {
  static int id = 0;   /* C: tkucbsrc/tkevent.c:1013, a second counter: tokens collide with the above */
  struct timeval tv; long sec, usec;
  if (!twincity_sched_owns_clock()) return __real_Tk_CreateMicroTimerHandler(seconds, microseconds, proc, cd);
  gettimeofday(&tv, NULL);
  sec = tv.tv_sec + seconds; usec = tv.tv_usec + microseconds;
  while (usec > 1000000) { usec -= 1000000; sec += 1; }   /* C: tkucbsrc/tkevent.c:1024 */
  id++;
  return insert(sec, usec, proc, cd, id);
}

void __wrap_Tk_DeleteTimerHandler(Tk_TimerToken token) {
  VTimer *t, *prev;
  if (!twincity_sched_owns_clock()) { __real_Tk_DeleteTimerHandler(token); return; }
  if (token == 0) return;
  for (t = queue, prev = NULL; t != NULL; prev = t, t = t->next) {
    if (t->token != token) continue;
    if (prev == NULL) queue = t->next; else prev->next = t->next;
    free(t);
    return;
  }
}

static void sync_displays(void) {
  TkDisplay *d;
  for (d = tkDisplayList; d != NULL; d = d->nextPtr) XSync(d->display, False);
}

static void fire_next(void) {
  VTimer *t = queue;
  long long due = (long long)t->sec * 1000000LL + t->usec;
  queue = t->next;
  if (twincity_vclock_us() <= due) twincity_vclock_set(due + 1);
  if (getenv("TWINCITY_SCHED_FAULT") && !strcmp(getenv("TWINCITY_SCHED_FAULT"), "wallclock")) {
    static long long last; struct timeval rt; long long now;
    __real_gettimeofday(&rt, NULL); now = (long long)rt.tv_sec * 1000000LL + rt.tv_usec;
    if (last) twincity_vclock_set(twincity_vclock_us() + (now - last));
    last = now;
  }
  (*t->proc)(t->clientData);
  free(t);
}

static int head_due(void) {   /* C: tkucbsrc/tkevent.c checkTime: timer time strictly < now */
  long long now = twincity_vclock_us();
  long sec = (long)(now / 1000000LL), usec = (long)(now % 1000000LL);
  return queue != NULL && ((queue->sec < sec) || ((queue->sec == sec) && (queue->usec < usec)));
}

int __wrap_Tk_DoOneEvent(int flags) {
  int f = flags;
  if (!twincity_sched_owns_clock()) return __real_Tk_DoOneEvent(flags);
  if ((f & TK_ALL_EVENTS) == 0) f |= TK_ALL_EVENTS;      /* C: tkucbsrc/tkevent.c:1233 */
  sync_displays();
  /* Tk's phases in Tk's order, none of them waiting. */
  if ((f & (TK_X_EVENTS|TK_FILE_EVENTS))
      && __real_Tk_DoOneEvent((f & (TK_X_EVENTS|TK_FILE_EVENTS)) | TK_DONT_WAIT)) return 1;
  if ((f & TK_TIMER_EVENTS) && head_due()) { fire_next(); return 1; }
  if (__real_Tk_DoOneEvent((f & ~TK_TIMER_EVENTS) | TK_DONT_WAIT)) return 1;   /* motion, idle */
  /* Nothing ready. A call that may not block returns, as in Tk; otherwise time passes. */
  if ((f & TK_DONT_WAIT) || !(f & (TK_TIMER_EVENTS|TK_FILE_EVENTS|TK_X_EVENTS))) return 0;
  if ((f & TK_TIMER_EVENTS) && queue != NULL) { fire_next(); return 1; }
  fprintf(stderr, "twincity-sched: would block forever at vclock %lld us (no timers, no events)\n",
          twincity_vclock_us());
  exit(3);
}

void __wrap_Tk_MainLoop(void) {
  if (!twincity_sched_owns_clock()) { __real_Tk_MainLoop(); return; }
  while (!tkMustExit && tk_NumMainWindows > 0)           /* C: tkucbsrc/tkevent.c:1544 */
    __wrap_Tk_DoOneEvent(0);
}

void __wrap_Tk_Sleep(int ms) {
  if (!twincity_sched_owns_clock()) { __real_Tk_Sleep(ms); return; }
  twincity_vclock_set(twincity_vclock_us() + (long long)(ms/1000) * 1000000LL + (ms%1000) * 1000LL);
}
