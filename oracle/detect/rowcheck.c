/* TwinCity UB detector runtime for TC_AT (row-accessor.py). An out-of-range subscript of a
 * row-pointer array is reported once per site, counted, and then performed anyway, so the
 * program goes on exactly as the original would (ASan still sees a row index past the array).
 * Report lines (stderr, or $TWINCITY_DETECT_LOG):  rowcheck: Map[120][5] at s_sim.c:1153  */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define MAXSITES 256
static struct { const char *file, *arr; int line; long n, x, y; } site[MAXSITES];
static int nsites;
static FILE *out(void) {
  static FILE *f; const char *p;
  if (!f) { p = getenv("TWINCITY_DETECT_LOG"); f = p ? fopen(p, "a") : NULL; if (!f) f = stderr; }
  return f;
}
static void summary(void) {
  int i;
  for (i = 0; i < nsites; i++)
    fprintf(out(), "rowcheck-summary: %s at %s:%d hits=%ld first=[%ld][%ld]\n",
            site[i].arr, site[i].file, site[i].line, site[i].n, site[i].x, site[i].y);
  fflush(out());
}
void tc_rowcheck(const char *arr, long x, long y, long X, long Y, const char *file, int line) {
  int i;
  if (x >= 0 && x < X && y >= 0 && y < Y) return;
  for (i = 0; i < nsites; i++)
    if (site[i].line == line && !strcmp(site[i].file, file) && !strcmp(site[i].arr, arr)) { site[i].n++; return; }
  if (nsites == 0) atexit(summary);
  if (nsites < MAXSITES) {
    site[nsites].file = file; site[nsites].arr = arr; site[nsites].line = line;
    site[nsites].n = 1; site[nsites].x = x; site[nsites].y = y; nsites++;
  }
  fprintf(out(), "rowcheck: %s[%ld][%ld] at %s:%d (bounds [%ld][%ld])\n", arr, x, y, file, line, X, Y);
  fflush(out());
}
