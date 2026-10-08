/* Entry for the reference-layout oracle (build-reference.sh): the full app's link, entered
 * via --wrap=main. Gives the app's Tcl hooks an empty interpreter (UI commands fail as
 * unknown commands, which Eval ignores; Tk calls only queue idle handlers that never run)
 * and the graph history buffers sim_init allocates (initGraphs, w_graph.c:550; no draws, no
 * sim state), then runs the unchanged headless driver, compiled in as headless_main(). */
#include "sim.h"
extern Tcl_Interp *tk_mainInterp;
int headless_main(int argc, char **argv);
int __wrap_main(int argc, char **argv) {
  static Sim s;
  tk_mainInterp = Tcl_CreateInterp();
  sim = &s; initGraphs();  /* headless_main then installs its own zeroed Sim */
  return headless_main(argc, argv);
}
