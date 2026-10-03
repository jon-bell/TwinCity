/* Globals and UI entry points the sim TUs expect from sim.c / w_tk.c / w_graph.c, stubbed
 * so the simulation links without Tcl/Tk/X. InitGraphMax is copied VERBATIM from
 * w_graph.c because it mutates sim state (clamps negative history to 0): do not stub it. */
#include "sim.h"
/* --- globals normally in sim.c / w_tk.c / w_graph.c --- */
Sim *sim = NULL; int sim_skips=0, sim_skip=0, sim_paused=0, sim_paused_speed=3, heat_steps=0;
struct timeval start_time;
char *CityFileName=NULL, *StartupName=NULL; int Startup=0;
int DoAnimation=1, DoMessages=1, DoNotices=1, UpdateDelayed=0;
short NewGraph=0, Graph10Max, Graph120Max;
Tcl_Interp *tk_mainInterp=NULL;
int sim_exit(int v){return 0;}
/* --- UI stubs --- */
int Eval(char *s){ if(getenv("SHOWEVAL")) fprintf(stderr,"EVAL %s\n",s); return 0;}
int Kick(){return 0;} int InvalidateEditors(){return 0;} int InvalidateMaps(){return 0;}
int EventuallyRedrawView(){return 0;} int doAllGraphs(){return 0;} int ChangeCensus(){CensusChanged=1;return 0;}
int MakeSound(){return 0;} int MakeSoundOn(){return 0;} int DoEarthQuake(){return 0;}
int StartMicropolisTimer(){return 0;} int StopMicropolisTimer(){return 0;}
int ResetLastKeys(){return 0;} int ViewToPixelCoords(){return 0;}
int AddInk(){return 0;} int FreeInk(){return 0;} int NewInk(){return 0;} int StartInk(){return 0;}
/* verbatim copy of w_graph.c InitGraphMax: it mutates sim history */
InitGraphMax(void)
{
  register x;
  ResHisMax = 0; ComHisMax = 0; IndHisMax = 0;
  for (x = 118; x >= 0; x--) {
    if (ResHis[x] > ResHisMax) ResHisMax = ResHis[x];
    if (ComHis[x] > ComHisMax) ComHisMax = ComHis[x];
    if (IndHis[x] > IndHisMax) IndHisMax = IndHis[x];
    if (ResHis[x] < 0) ResHis[x] = 0;
    if (ComHis[x] < 0) ComHis[x] = 0;
    if (IndHis[x] < 0) IndHis[x] = 0;
  }
  Graph10Max = ResHisMax;
  if (ComHisMax > Graph10Max) Graph10Max = ComHisMax;
  if (IndHisMax > Graph10Max) Graph10Max = IndHisMax;
  Res2HisMax = 0; Com2HisMax = 0; Ind2HisMax = 0;
  for (x = 238; x >= 120; x--) {
    if (ResHis[x] > Res2HisMax) Res2HisMax = ResHis[x];
    if (ComHis[x] > Com2HisMax) Com2HisMax = ComHis[x];
    if (IndHis[x] > Ind2HisMax) Ind2HisMax = IndHis[x];
    if (ResHis[x] < 0) ResHis[x] = 0;
    if (ComHis[x] < 0) ComHis[x] = 0;
    if (IndHis[x] < 0) IndHis[x] = 0;
  }
  Graph120Max = Res2HisMax;
  if (Com2HisMax > Graph120Max) Graph120Max = Com2HisMax;
  if (Ind2HisMax > Graph120Max) Graph120Max = Ind2HisMax;
}
