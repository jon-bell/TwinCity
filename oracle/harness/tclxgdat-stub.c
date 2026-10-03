/* Used only when no yacc/bison is available to generate tclxgdat.c from tclxgdat.y.
 * Tcl_GetDate backs TclX's `convertclock`, which Micropolis never calls. Whether this
 * stub or the generated parser was used is recorded in the oracle identity. */
#include <time.h>
time_t Tcl_GetDate(char *p, time_t now, long zone) { (void)p; (void)now; (void)zone; return (time_t)-1; }
