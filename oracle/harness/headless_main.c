/* Headless driver: load a city (path) or scenario (S1..S8), run N frames of
 * SimFrame()+MoveObjects() (speed 3, no views), print state hashes. */
#include "sim.h"
static unsigned long long fnv(const void*p,size_t n){const unsigned char*c=p;unsigned long long h=1469598103934665603ULL;size_t i;for(i=0;i<n;i++){h^=c[i];h*=1099511628211ULL;}return h;}
extern char *ResourceDir, *HomeDir;
int main(int argc,char**argv){
  int i, steps=atoi(argv[3]);
  static Sim s; sim=&s;
  ResourceDir=argv[1];
  initMapArrays(); InitFundingLevel(); ResetMapState(); ResetEditorState(); ClearMap();
  InitWillStuff(); SetFunds(5000); SimSpeed=3;
  if(argv[2][0]=='S') LoadScenario(atoi(argv[2]+1)); else LoadCity(argv[2]);
  if(argc>4) SeedRand(atoi(argv[4]));
  SimSpeed=3;
  for(i=0;i<steps;i++){ SimFrame(); MoveObjects(); }
  printf("map=%016llx pop=%ld funds=%ld time=%ld score=%d valves=%d,%d,%d sprites=%d\n",
    fnv(&Map[0][0],WORLD_X*WORLD_Y*2),(long)CityPop,(long)TotalFunds,(long)CityTime,CityScore,RValve,CValve,IValve,sim->sprites);
  if(getenv("SAVETO")) saveFile(getenv("SAVETO"));
  printf("tax=%d police%%=%f fire%%=%f road%%=%f autoBudget=%d autoBulldoze=%d speed=%d\n",CityTax,policePercent,firePercent,roadPercent,autoBudget,autoBulldoze,SimSpeed);
  return 0;
}
