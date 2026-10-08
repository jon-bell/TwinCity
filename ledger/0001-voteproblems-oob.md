# 0001 VoteProblems out of bounds

- **site:** `sim/s_eval.c:212,217` (`if (x > PROBNUM)` should bound with `>=`): reads
  `ProblemTable[10]`, writes `ProblemVotes[10]`.
- **detector:** ASan global-buffer-overflow (survey, 2026-10-03); confirmed by layout perturbation.
- **sessions:** every session that runs an evaluation (all scenarios, all cities).
- **class:** `varies`. Not score-only: the read decides how many `Rand(300)` draws
  `VoteProblems` makes, so under some layouts the whole session diverges from the first
  evaluation onward (see below).
- **ruling:** `pending`. The reference build exists (P0.4), but what counts as the 1990
  layout is now an open question (see "Layout is a property of the whole link").

## Perturbation (San Francisco scenario `S2`, 3,000 frames, headless driver, frozen clock)

Neighbours from `tools/layout-neighbour.py`; outcomes from `twincity-headless` /
`twincity-reference RES S2 3000`. All gcc 13.3, GNU ld 2.42, spec flags unless noted.

| build | link | `ProblemTable[10]` reads | `ProblemVotes[10]` writes | score | map / pop / funds / valves / sprites |
|---|---|---|---|---|---|
| x86-64, `-fno-common` | headless | padding (0) | padding | 318 | (2026-10-03 survey; same as next row) |
| x86-64, `-fcommon` (**current headless smoke**) | headless archive | `TrafficAverage` | **`CityScore`** | 322 | `98af6a0ddc02df38` / 97840 / 19089 / 1890 / 7 |
| x86-64, `-fcommon`, plus 30,000 unrelated functions | headless archive + pad | `TrafficAverage` | `AverageCityScore` | 318 | `98af6a0ddc02df38` / 97840 / 19089 / 1890 / 7 |
| `-m32 -fcommon`, `-O0`/`-O1`/`-O2` | headless objects in makefile `SRCS` order | `TrafficAverage` | `CityScore` | 322 | `98af6a0ddc02df38` / 97840 / 19089 / 1890 (`-O0`), 1889 (`-O1`,`-O2`) / 7 |
| **`-m32 -fcommon`, `-O1` (reference, `build-reference.sh`)** | **full app, original makefile** | **`CityPop` (low half)** | **`EvalValid`** | **318** | **`429a71a41f09285b` / 101840 / 19051 / 1831 / 5** |
| `-m32 -fcommon`, `-O0` | full app, original makefile | `CityPop` | `EvalValid` | 318 | same as reference |
| x86-64 `-fcommon`, `-O1`/`-O0` (`WIDTH=64`) | full app, original makefile | `CityPop` | `EvalValid` | 318 | same as reference |
| x86-64 `-fcommon`, `-O1` (**the xvfb session oracle**) | full app, original makefile | `CityPop` | `EvalValid` | n/a | (layout only: `build-xvfb.sh` binary) |
| `-m32 -fno-common`, `-O1` | full app, original makefile | `CityNo` | `ProblemTaken` | 318 | `98af6a0ddc02df38` / 97840 / 19089 / 1889 / 7 |

32-bit rows ran under qemu-i386 user-mode emulation (dev container without IA32 emulation).
On this session the emulated `-m32` reference and the native x86-64 full-app link agree on every
field. That is a consistency check, not a native-i386 cross-check.

### Why the reference diverges everywhere, not just in the score

At the first evaluation (CityTime 290, draw 4397) `VoteProblems` reads `ProblemTable[10]`:
19 (`TrafficAverage`) in the headless build, 18232 (the low half of `CityPop`) in the full-app
link. `Rand(300) < 18232` always holds, so `z` reaches 100 sooner and `VoteProblems` makes
fewer draws. `DoVotes` starts at draw 5000 in the headless build and 4941 in the reference;
every later draw is shifted. The write lands in `EvalValid` (49 votes), which
`CityEvaluation` overwrites with 1 (`s_eval.c:96`), so it is inert there.

### Layout is a property of the whole link

The proposer's premise in the original plan, that common symbols follow first-definition order
in the link, is false for GNU ld 2.42. It allocates commons in link-hash-table traversal order.
Evidence: adding 30,000 unrelated *function* symbols to the headless link (no data, first or
last in the link) moves `ProblemVotes[10]` from `CityScore` to `AverageCityScore` and the
score from 322 to 318. Consequences:

1. The headless oracle and the xvfb session oracle already disagree at this site under the
   current spec flags, so on every session with an evaluation they produce different RNG
   streams. `smoke-xvfb.sh` checks determinism only, so nothing catches this.
2. Any harness change that adds symbols to an oracle link can move ground truth. The headless
   smoke catches it through the score; the xvfb smoke does not.
3. The `-m32` makefile link is a reproducible stand-in, but its layout is decided by GNU ld's
   hash function over today's symbol set (including bundled Tcl/Tk/TclX), not by anything a
   1990 linker did.

## Next steps for the loop

1. ~~Build the reference layout~~ (P0.4: `oracle/build-reference.sh`).
2. Jon: decide what stands in for the 1990 layout given hash-ordered commons (needs-jon issue).
3. Proposer / adversary / verifier, as before, once (2) is settled. The verifier's
   re-record diff will **not** be limited to evaluation-derived state: the ruling moves the
   whole session for any build whose read differs from the ruled value, so expect it to move
   more than 5% of the corpus (escalation threshold).
