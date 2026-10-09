# TwinCity plan

The work plan agents execute autonomously. **The why is in `docs/DESIGN.md`; the rules are in
`CLAUDE.md`.** This file says what to do next and when a phase is done.

Agents may tick boxes, add tasks under a phase, and update **Now**. Changing a phase's
**exit criteria** or the **guardrails** needs `jon-approved` (see `CLAUDE.md`).

## Now

Phase 0 is nearly done; Phase 1 can start in parallel. Pick from these, top first:

1. `P0.6` optimisation invariance. Leads: `-m32` `-O1` moves `RValve` 1890 → 1889 (ledger/0001
   table), and `haight.cty` at 20000 frames ends with funds 775830 on the 32-bit reference build
   but 775828 on headless and reference64 (P0.5 PR), so 32-bit itself (x87 or ILP32) changes
   behaviour.
2. `P1.2` logical-frame dumper (`probe_frame.c`'s per-tick trace is the place to grow it).
3. `P0.7` committed identity.
4. `P0.9` detector coverage (sanitized session oracle; tool and disaster sweep).

Waiting on Jon (don't block on these; work elsewhere): ledger/0002 ruling. ledger/0001 is
ruled and pinned by `patches/0003`; other layout-dependent sites (P0.5 will find them) can still
make the oracles disagree, and adding symbols to an oracle link can still move those.

---

## Phase 0: Oracle

Goal: the original program runs deterministically, identifies itself, and can be called
from Swift.

- [x] P0.1 Headless build + determinism smoke (`oracle/build-headless.sh`, `smoke-headless.sh`)
- [x] P0.2 Session oracle under Xvfb + determinism smoke (`build-xvfb.sh`, `smoke-xvfb.sh`)
- [x] P0.3 First in-process gate: RNG, with a rejection-boundary test that kills a planted mutant
- [x] P0.4 **Reference-layout build** `oracle/build-reference.sh`. `-m32 -fcommon`, the original
  makefile's link order, spec flags otherwise. CI job installs `gcc-multilib`. Output: the
  VoteProblems neighbours and score under the reference layout, written into ledger/0001's
  perturbation table.
- [x] P0.5 **UB detector build** `oracle/build-detect.sh`. ASan + UBSan + `-ftrapv`, plus a
  bounds-checked `Map` accessor. That accessor needs an instrumentation-only patch: the smoke
  hashes must stay unchanged when it's compiled out. It runs the smoke sessions and reports
  each site as `file:line`.
- [ ] P0.6 **Optimisation invariance.** `smoke-headless.sh` also builds `-O2` and asserts the
  same hash as `-O0`. A difference is a ledger entry, not a flag change.
- [ ] P0.7 **Committed identity.** `oracle/IDENTITY.json`, written by `tools/oracle-identity.py`.
  CI fails on drift unless the same PR updates it. Recordings embed it.
- [ ] P0.8 **`Rand` range logging.** A probe (`-finstrument-functions` or an instrumentation-only
  patch) so each draw records its requested range. Calls from inside `s_sim.c` are invisible
  to `--wrap`.
- [ ] P0.9 **Detector coverage.** P0.5 runs on the headless driver only (S1–S8 and the 24
  cities), with no tools, no disasters and no views, and it stops at the first budget window
  when `autoBudget` is off. Add (a) a sanitized session-oracle build that runs the `smoke-xvfb.sh`
  session, with only `src/sim` instrumented, and (b) a detect driver that fires every disaster
  and applies every tool at map edges (`DoMeltdown`'s unchecked `Map[SX-1..SX+2]`,
  `s_sim.c:1153`). New sites become ledger entries.

**Exit:** P0.4–P0.8 done; CI green; smoke baselines unchanged, or changed only through ruled
ledger entries.

## Phase 1: Sessions and corpus

Goal: record any session of the original, with views open, deterministically. Replay it
headlessly where the headless build applies.

- [x] P1.1 **Frame-stepped scheduler.** Wrap the Tk timer handlers and `after` so that time
  advances only by tick on the virtual clock. Earthquake end (3000 ms), budget countdown and
  DropFireBombs all become tick-scheduled. Proof: identical recordings at two different
  wall-clock speeds of the host.
- [ ] P1.2 **Logical-frame dumper** in `probe_frame.c`, per `docs/DESIGN.md` "Visual
  fidelity". Covers the editor tile cache and pan, sprites, map state and overlay, graph and
  date, shake, blink, and pending tool. Proof: a tick where the pixels change but the frame
  doesn't is impossible on the smoke sessions; check that with a classic-skin pixel diff.
- [ ] P1.3 **Message capture.** Wrap `Eval`, plus a widget-tree text walk at each frame
  boundary. Text is exact, so no normalisation.
- [ ] P1.4 **Full-state snapshot and restore.** Generate the globals list from `nm` (`.data`
  and `.bss`) plus the C-shimmed statics. Proof: snapshot → restore → continue gives the
  same recording as an uninterrupted run, at 5 points in each smoke session.
- [ ] P1.5 **Session schema.** `docs/SESSION.md` plus a JSON Schema. Draft it, then open a PR
  labelled `needs-jon`: it encodes the projection.
- [ ] P1.6 **Recorder CLI.** Session spec → recording. Recording twice gives byte-identical
  output, ignoring ASLR-dependent PCs, which are resolved to `file:line`.
- [ ] P1.7 **Validate every channel.** A tool reports RNG, projection, logical frame, messages
  and classic pixels separately, and classifies every residual. Each channel has a `--fault`
  mode that proves it can fail (wrong clock, wrong flags, one view closed).
- [ ] P1.8 **Train corpus v0.** 24 cities × 8 scenarios × 3 speeds × view configurations,
  with scripted tool, budget and disaster events. `corpus/train/MANIFEST.json` carries a
  `reproduce` line and the oracle identity. A generator-spec lock in CI checks that the
  manifest still reproduces the corpus.
- [ ] P1.9 **Coverage.** gcov over the simulation C (`s_*.c` and the simulation parts of
  `w_tool.c`, `w_sprite.c` and `w_budget.c`), published per corpus.

**Exit:** P1.1–P1.9 done; the train corpus reproduces from its manifest; the channel validator
is green with every residual classified.

## Phase 2: Ratify and rule

Goal: what must agree is decided, and the UB loop runs on its own.

- [ ] P2.1 **Projection proposal.** The full field list, with exclusions and the reason for each.
  PR `needs-jon`.
- [ ] P2.2 **Abstraction function.** The C globals → Swift `City` mapping, plus a round-trip
  test design. PR `needs-jon`.
- [ ] P2.3 **UB loop tooling.** detect (P0.5) → perturbation runner (gcc/clang, -O levels,
  `-fcommon`/`-fno-common`, shuffled globals, poisoned padding and heap) → ledger entry
  generator → verifier (re-record diff limited to sessions that reach the site).
- [ ] P2.4 **UB loop self-test.** Planted sites, some inert and some projection-changing,
  in a scratch oracle copy. The loop must classify all of them correctly.
- [ ] P2.5 **Rule every open ledger entry** under the policy, starting with 0001.

**Exit:** P2.1 and P2.2 approved by Jon; P2.4 passes; no `pending` rulings except escalations.

## Phase 3: Gate infrastructure

Goal: any C function can get a strong, non-vacuous gate cheaply.

- [ ] P3.1 **Carving.** Per-call records from recordings: function, arguments, pre-state over
  the abstraction function, RNG slice, return value, and state delta. Handle the
  same-file-call blind spot with a probe.
- [ ] P3.2 **Generic gate harness.** In-process: load pre-state into the C globals and the Swift
  `City`, call both, diff through the abstraction function.
- [ ] P3.3 **Strength rating and vacuity census.** Flag empty assertions, no records, a single
  behaviour class, and stub-satisfiable gates (does a constant return pass ≥95% of records?).
  The census runs in CI and is published.
- [ ] P3.4 **Red-team kit.** Scrambled answer keys, planted fakes (constant, lookup table,
  skipped work, boundary mutants), and mutation of the gate logic itself, with its kill rate
  tracked.
- [ ] P3.5 **Seam inventory.** The call graph of the simulation C. List the seams (phases,
  `DoZone` and the zone handlers, scans, tools, disasters, budget, evaluation), ordered
  leaves-first, with the RNG draws and globals each one touches.

**Exit:** P3.1–P3.5 done; the census shows the existing gates as STRONG; the red-team kit
kills ≥95% of planted fakes.

## Phase 4: Port waves

Goal: every seam ported and gated; whole-session parity on train and sealed.

- [ ] P4.1 **Swift data model.** `City` value type, tile and zone enums, history arrays,
  budget, sprites. The C's layout is not reproduced; the abstraction function covers the gap.
- [ ] P4.2 **Waves.** Packets of one seam each, leaves-first, with no two packets in a wave
  touching the same Swift file. Each packet carries its records and a RED baseline.
- [ ] P4.3 **Message and string tables** loaded from the original's `res/` data.
- [ ] P4.4 **View layer.** Per-view logical frames from Swift state, including the
  view-driven RNG draws at the same points as the C.
- [ ] P4.5 **Classic-skin renderer.** Pixels match the original's back buffers on the
  pixel-test ticks.
- [ ] P4.6 **Session parity.** A Swift session runner. Train parity measured per landing; the
  sealed exam is sat by the proctor in TwinCity-sealed, on a cadence.

**Exit:** every seam in P3.5 STRONG-gated; train parity 100% on all channels; sealed
aggregate stable over two exams; the core links no C.

## Phase 5: Generators

Goal: coverage of the simulation C, not of the corpus we happened to record.

- [ ] P5.1 **Event-language generator arms.** Each arm is one file and a pure function of its
  seeded draws, with a recorded tape so mutation reproduces. It fails closed against the C's
  own tool and string tables.
- [ ] P5.2 **Precondition backtrace.** From an uncovered branch to a constructed state
  (`Tile`/`Fill`, scenarios, generated maps), with a function-scoped witness that is proven
  able to be absent.
- [ ] P5.3 **Coverage-guided fuzzing** over event programs.
- [ ] P5.4 **Reachability check** on generated states: a state built by direct map writes has
  to be one play could produce. This is an open question; write down what is checked and
  what isn't.

**Exit:** a branch-coverage plateau on the simulation C, with every uncovered branch explained.

---

## Guardrails (summary; `CLAUDE.md` is authoritative)

- Branch, PR and CI for everything. Squash-merge only when CI is green, the guarded-paths
  check passes (`scripts/check-guarded-paths.py`), and the adversary review is resolved.
- Patches, existing baselines (`oracle/baselines/`) and existing smoke scripts change only
  through a ruled ledger entry in the same PR, or a PR that implements an open `jon-ruled` issue.
- Jon reviews decisions, not PRs: one `needs-jon` issue per decision, then keep working on
  something unblocked. Anything waiting on him goes on the pinned Jon queue issue.
- Never access TwinCity-sealed. Never commit sessions. Never force-push `main`.
- Three failed attempts on one task: stop, write up the diagnosis in the task's issue, label it
  `blocked`, move on.
