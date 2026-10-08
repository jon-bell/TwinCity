# 0001 VoteProblems out of bounds

- **site:** `sim/s_eval.c:212,217` (`if (x > PROBNUM)` should bound with `>=`): reads
  `ProblemTable[10]`, writes `ProblemVotes[10]`.
- **detector:** ASan global-buffer-overflow (survey, 2026-10-03; needs `-fno-common`, since ASan
  puts no redzones on commons); confirmed by layout perturbation.
- **sessions:** every session that runs an evaluation (all scenarios, all cities).
- **class:** `varies`. Not score-only: the read decides how many `Rand(300)` draws
  `VoteProblems` makes, so under some layouts the whole session diverges from the first
  evaluation onward (see below).
- **ruling:** `reproduce: ProblemTable[10] = (short)CityPop; ProblemVotes[10] = EvalValid`. These
  are the values of the reference layout (`build-reference.sh`: `-m32`, original makefile link),
  which Jon ruled is the 1990-layout stand-in by definition (#6, option 1, 2026-10-08).
- **oracle patch:** `oracle/patches/0003-voteproblems-pin-reference-layout.patch`.
- **Swift:** the port of `VoteProblems` must reproduce both explicitly: the read when `x == 10`
  is the low 16 bits of `CityPop`, and the vote is added to `EvalValid`. That write is inert
  because `DoProblems` is only reached from `CityEvaluation`, which sets `EvalValid = 1`
  afterwards (`s_eval.c:96`), but a gate on `VoteProblems` alone will see it.
- **arguments:** *proposer:* the reference layout is reproducible, and native i386 (CI) and
  qemu-i386 agree on it. *adversary:* it isn't the 1990 layout. GNU ld orders commons by hash,
  and on a big-endian target (several early Unix ports likely were; not verified) the read
  would be the *high* half of `CityPop` even with the same neighbour. *ruling:* Jon chose the reference by definition
  over an unrecoverable 1990 order (#6). *verifier:* below.
- **escalated:** yes. The ruling moves every session with an evaluation (more than 5%) and
  re-baselines `smoke-headless.sh`. Resolved by Jon's ruling on #6; this PR needs `jon-approved`.

## Verification (patch 0003 applied; S2, 3,000 frames)

Every build that disagreed before now produces the reference outcome:

| build | outcome |
|---|---|
| headless, x86-64 archive link (smoke) | `map=429a71a41f09285b pop=101840 funds=19051 score=318 valves=1831 sprites=5` |
| headless + 30,000 unrelated function symbols | same |
| headless, `-fno-common -fsanitize=address` | same, and ASan clean for all 3,000 frames |
| reference `-m32` (default `-O1`; `-O0`; `-fno-common`) | same |
| reference x86-64 (`WIDTH=64`) | same |

Fault: the same ASan build without patch 0003 stops at
`global-buffer-overflow ... VoteProblems src/sim/s_eval.c:212`.

The xvfb session oracle has no score output to compare. It runs the same patched `s_eval.c`,
which no longer reads or writes past either array, so its layout can no longer matter here.

## Perturbation before the patch (San Francisco scenario `S2`, 3,000 frames, headless driver, frozen clock)

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

Done: reference build (P0.4), ruling (#6), oracle patch 0003, verification above. Remaining:
reproduce the pinned values in the Swift `VoteProblems` port (phase 4) with a gate record at
`x == 10`.
