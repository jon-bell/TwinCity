# 0003 SetValves: out-of-range float → short in `TotalPop`

- **site:** `sim/s_sim.c:442`: `TotalPop = NormResPop + ComPop + IndPop;`. `NormResPop` is a
  `float` (`s_sim.c:421`), so the sum is a float and the store converts it to `short`. When the sum
  is above 32767, that conversion is undefined behaviour (C89 §3.2.1.3).
- **detector:** UBSan `float-cast-overflow`, UB detector build (`oracle/build-detect.sh`, P0.5),
  2026-10-09. Recorded in `oracle/baselines/detect-sites.txt`.
- **sessions:** `res/cities/finnigan.cty` (the sum is 36862) and `neatmap.cty` (33469) on the
  headless driver. These are the only 2 of the 32 detect sessions (S1–S8 and the 24 cities,
  20000 frames each) that reach it. Both cities start at `CityTime` 0 with `autoBudget` off, so
  the headless driver stops at the first tax time: `CollectTax` → `DoBudget` → `Pause`
  (`w_budget.c:321`). Sessions in which someone answers the budget window will reach the site
  more often.
- **perturbation:** the codegen differs by target. The values below come from a stand-alone
  reproduction of the expression (gcc 13.3, `-std=gnu89 -fwrapv -ffp-contract=off`, sum 36863),
  not yet from the oracle builds:

  | build | instruction | stored value |
  |---|---|---|
  | x86-64 `-O0`/`-O1`/`-O2` (headless, xvfb, reference64) | `cvttss2si` to 32-bit, keep the low 16 bits | −28673 (wraps mod 2^16) |
  | `-m32` `-O0`/`-O1`/`-O2` (reference) | x87 `fistps` (16-bit store) | −32768 (integer indefinite) |
  | `-m32 -msse2 -mfpmath=sse` | `cvttss2si` | −28673 |

  On the oracle: `finnigan.cty` and `neatmap.cty` give the same first smoke line on headless and
  reference at 20000 frames. `TotalPop` itself is not in that line.
- **class:** `varies` (reference vs the x86-64 oracles), going by the table. Not measured yet:
  whether a projected field moves. `TotalPop` feeds `TaxFund` (`s_sim.c:655`), the advisor
  messages (`s_msg.c:157–177`) and a condition in `w_sprite.c:1503`.
- **ruling:** `pending`. For P2.5: the policy pins *layout*-dependent values to the reference
  build. This value depends on the instruction set instead (x87 vs SSE), so the proposer should
  first argue whether "reproduce the 1990 layout" covers it. 1990 targets with x87 or 68881 FPUs
  would also have had their own out-of-range conversion results.
- **oracle patch:** none.
- **arguments:** none yet.
- **escalated:** no.
