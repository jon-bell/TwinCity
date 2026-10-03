# 0001 VoteProblems out of bounds

- **site:** `sim/s_eval.c:212,217` (`if (x > PROBNUM)` should bound with `>=`): reads
  `ProblemTable[10]`, writes `ProblemVotes[10]`.
- **detector:** ASan global-buffer-overflow (survey, 2026-10-03); confirmed by layout perturbation.
- **sessions:** every session that runs an evaluation (all scenarios, all cities).
- **class:** `varies`.
- **ruling:** `pending` — awaits the 32-bit reference-layout build (`-m32 -fcommon`).

## Perturbation so far (San Francisco scenario, 3,000 frames, headless, frozen clock)

| build | `ProblemTable[10]` reads | `ProblemVotes[10]` writes | score |
|---|---|---|---|
| gcc 13, `-fno-common`, x86-64 | padding (0) | padding | 318 |
| gcc 13, `-fcommon`, x86-64 (current spec flags) | `TrafficAverage` | **`CityScore`** | 322 |
| gcc, `-m32 -fcommon` (1990 reference stand-in) | ? | ? | ? |

Map, population, funds and valves are identical across the two measured builds; only the
score (and anything derived from it) moves.

## Next steps for the loop

1. Build the reference layout (`-m32`, needs gcc-multilib; CI runners have it).
2. Proposer: state the reference value and argue the stand-in is faithful at this site
   (common-symbol order follows first definition order in the link; the original makefile's
   link order is in `src/sim/makefile`).
3. Adversary: argue it isn't (e.g. 1990 compilers sorted commons differently).
4. Verifier: oracle patch makes every build produce the reference value; re-record diff
   touches only evaluation-derived state.
