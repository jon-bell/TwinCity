# 0004 doMessage: signed overflow in the message-expiry test, on an ABI-dependent `TickCount`

- **site:** `sim/s_msg.c:316`: `} else if ((TickCount() - LastMesTime) > (60 * 30)) {`. Both
  operands are `QUAD` (`int` under the spec's `-DOSF1`), and the subtraction overflows `int`.
  That is undefined behaviour in C89. The spec's `-fwrapv` defines it as wrapping, so every
  oracle build gives a deterministic result.
  The value it subtracts comes from `TickCount()` (`sim/w_stubs.c:106`):
  `(QUAD)((time.tv_sec / 60) + (time.tv_usec * 1000000 / 60))`. The `tv_usec` term is
  meant to be 1/60-second ticks, but it multiplies instead of dividing, so it grows by 16666 per
  microsecond and dominates the value:
  - on LP64 (headless, xvfb, reference64), `long` is 64-bit, so the product fits. The sum is
    truncated to the 32-bit `QUAD`, which is implementation-defined (mod 2^32 on gcc), not
    undefined.
  - on ILP32 (reference, and the 1990 targets), the product overflows `long`, which is
    undefined behaviour. `-fwrapv` makes it wrap *before* the division by 60, so the result is a
    different number.

  The detector is LP64 only, so it reports `:316` but cannot see `w_stubs.c:106`.
- **detector:** UBSan `signed-integer-overflow`, session-oracle UB detector build
  (`oracle/build-detect-xvfb.sh`, P0.5), 2026-10-10. Recorded in
  `oracle/baselines/detect-xvfb-sites.txt`.
- **sessions:** 14 of the 32 xvfb detect sessions (3000 ticks each). The list is in the
  baseline. The headless detect runs (`run-detect.sh`: the same 32 sessions, 1250 ticks) don't
  reach `:316`, but headless does run `doMessage`. `DoUpdateHeads` → `updateDate`
  (`w_update.c:176`) is reached from `DoBudgetNow` (`w_budget.c:198`, `:209`; yearly via
  `CollectTax`, `s_sim.c:660`) and `InitWillStuff` (`s_init.c:130`), as well as from the
  session oracle's `sim_update_editors` (`sim.c:284`). The adversary review of #18 used gdb on the
  headless build. On `haight.cty` at 20000 frames: 28 `doMessage` calls and 25 `TickCount`
  calls, all at `:308` (the `MessagePort` branch). S1 and S2: 3 `doMessage` calls each. A port
  of `doMessage`/`TickCount` therefore runs on headless-gated paths too. (The
  `build-headless.sh:4` comment, "never runs … doMessage", is wrong. It isn't corrected here,
  because that file is an input to the oracle identity.)
- **perturbation:** the values below are `TickCount()` from a stand-alone reproduction of the
  `w_stubs.c:106` expression (gcc 13.3, `-std=gnu89 -fwrapv -O1`), on virtual-clock instants from
  the S1 run. They are not yet from the oracle builds:

  | virtual clock (µs) | LP64 | ILP32 (`-m32`) |
  |---|---|---|
  | 631152000000000 (session start) | 10519200 | 10519200 |
  | 631152024925988 | −1736216651 | −18229732 |
  | 631152024937988 (12 ms later) | −1536216651 | 38604691 |
  | 631152099778982 | 108650646 | 37067858 |

  So the two ABIs disagree on `TickCount()`, and the wrapped difference at `:316` can have
  opposite signs, which flips the 30-second expiry. On LP64 the 12 ms step moves `TickCount` by
  +200000000. On ILP32 it moves it by +56834423. In both cases the step is far above 1800, so
  "30 seconds" is a few microseconds of virtual time on either ABI.
  The session oracle runs only on LP64, so no oracle pair can exhibit the difference today.
- **class:** `varies` (LP64 vs ILP32), going by the table. Not measured: whether the projection
  moves. When the test is false, a positive `MesNum` falls through to `SetMessageField` with the
  same text again (`s_msg.c:363–375`). The first display with `autoGo` on already cleared
  `MesX`/`MesY`, so `DoAutoGoto` doesn't run again. When it is true, `MesNum = 0`. The likely effect is on the message
  field's redraws, not its text. A negative `MesNum` (a picture message) takes the `:314`
  branch, not this one. The test has no `Rand` call, so the RNG draw sequence is unaffected.
- **ruling:** `pending`. For P2.5: unlike ledger/0003 (x87 vs SSE), this one depends on the
  ABI. "Reproduce the 1990 layout" plausibly covers it, because the 1990 targets were ILP32. But
  the session oracle, which is what records message text, is LP64. The proposer should start by
  measuring whether any projected field moves (an ILP32 `TickCount` swapped in via `--wrap`).
- **oracle patch:** none.
- **arguments:** none yet.
- **escalated:** no.
