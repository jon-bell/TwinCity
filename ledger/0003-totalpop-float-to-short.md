# 0003 SetValves: out-of-range float → short in `TotalPop`

- **site:** `sim/s_sim.c:442`: `TotalPop = NormResPop + ComPop + IndPop;`. `NormResPop` is a
  `float` (`s_sim.c:421`), so the sum is a float and the store converts it to `short`. When the sum
  is above 32767, that conversion is undefined behaviour (C89 §3.2.1.3).
- **detector:** UBSan `float-cast-overflow`, UB detector build (`oracle/build-detect.sh`, P0.5),
  2026-10-09. Recorded in `oracle/baselines/detect-sites.txt`.
- **sessions:** `res/cities/finnigan.cty` (the sum is 36862) and `neatmap.cty` (33469) on the
  headless driver. These are the only 2 of the 32 detect sessions (S1–S8 and the 24 cities)
  that reach it. Each session runs 20000 frames, which is 1250 ticks, with the detect driver
  answering every budget window (`TWINCITY_DETECT_RESUME`, `oracle/detect/resume.c`). Without
  that, both cities stop at the first tax time: `CollectTax` → `DoBudget` → `Pause`
  (`w_budget.c:321`), and so do 15 other sessions. Both cities still reach the site.
- **perturbation:** the codegen differs by target. The values below come from a stand-alone
  reproduction of the expression (gcc 13.3, `-std=gnu89 -fwrapv -ffp-contract=off`, sum 36863),
  not yet from the oracle builds:

  | build | instruction | stored value |
  |---|---|---|
  | x86-64 `-O0`/`-O1`/`-O2` (headless, xvfb, reference64) | `cvttss2si` to 32-bit, keep the low 16 bits | −28673 (wraps mod 2^16) |
  | `-m32` `-O0`/`-O1`/`-O2` (reference) | x87 `fistps` (16-bit store) | −32768 (integer indefinite) |
  | `-m32 -msse2 -mfpmath=sse` | `cvttss2si` | −28673 |

  Not yet measured on the oracle builds themselves. A headless-vs-reference comparison of the
  two cities says nothing yet: on the plain headless driver, which the reference build also
  uses, both stop at the first budget window before simulating a single tick.
- **class:** `varies` (reference vs the x86-64 oracles), going by the table. Not measured yet:
  whether a projected field moves. `TotalPop` is read by:
  - `s_sim.c:441`: `LastTotalPop = TotalPop` on the next pass;
  - `s_eval.c:85`: `if (TotalPop)` gates `CityEvaluation`'s `GetAssValue`/`DoPopNum`/`DoProblems`,
    including `VoteProblems`' `Rand(300)` draws;
  - `s_sim.c:655–657`: `TaxFund`, and `if (TotalPop)`;
  - the advisor messages (`s_msg.c:157–177`);
  - a condition in `w_sprite.c:1503`.

  When the sum is a multiple of 65536, SSE stores 0 and x87 stores −32768, which flips both
  `if (TotalPop)` branches. That means a different RNG draw count, so the whole session
  diverges.
- **ruling:** `pending`. For P2.5: the policy pins *layout*-dependent values to the reference
  build. This value depends on the instruction set instead (x87 vs SSE), so the proposer should
  first argue whether "reproduce the 1990 layout" covers it. 1990 targets with x87 or 68881 FPUs
  would also have had their own out-of-range conversion results.
- **oracle patch:** none.
- **arguments:** none yet.
- **escalated:** no.
