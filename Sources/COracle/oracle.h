/* Clean, fully prototyped declarations of the original C functions the differential
 * tests call. Do NOT import headers/sim.h into Swift: its K&R declarations import badly.
 * Add a prototype here when a gate needs a function; keep signatures exactly as the C.
 * Under -DOSF1, QUAD is int. */
#ifndef TWINCITY_ORACLE_H
#define TWINCITY_ORACLE_H
int sim_rand(void);                 /* rand.c   */
void sim_srand(unsigned int seed);  /* rand.c   */
short Rand(short range);            /* s_sim.c  */
int Rand16(void);                   /* s_sim.c  */
int Rand16Signed(void);             /* s_sim.c  */
#endif
