# TwinCity design

*Scope and design for porting the original Micropolis C to idiomatic Swift under differential testing. Draft of 2026-10-03; this document is the plan of record.*

Reuse the agent-driven migration loop from a NetHack C-to-JavaScript port on a second subject. Source: **the original C**, `micropolis-activity/src/sim/` in github.com/simhacker/micropolis (not MicropolisCore). Target: **idiomatic, safe Swift**, not a structure-preserving port.

That second choice is what makes this more than a NetHack rerun. The NetHack port kept C names and call order so the oracle lined up. This one has to state the paper's three parameters (the state that must agree, the tolerance, and the input distribution) for a port that is meant to differ. It's the first test of "bounded agreement with intent" on a port that was never meant to be structurally faithful.

Line references are to `oracle/upstream/micropolis-activity/src/sim/` unless noted.

---

## The three questions

### 1. How are sessions defined?

**NetHack (what we did).**
- A session is `{seed, datetime, nethackrc, moves}` plus `steps[]`.
- One step is one input boundary: `{key, rng[], screen 24×80, cursor}`. Each RNG entry has a call site, e.g. `rn2(2)=0 @ randomize_gem_colors(o_init.c:89)`.
- Multi-segment sessions share a virtual filesystem for save/restore.
- Sessions came from hand scripts, AFL over a structured IR (a header plus tagged keystrokes), and later a precondition-driven generator.
- A link-time `--wrap` recorder carves each session into per-call records `(fn, args, state_before, RNG slice, return, state_after_diff)`.

**Micropolis (proposed).** Micropolis is clock-driven, so the step is the **tick**: one `sim_loop(1)` (`SimFrame` + `MoveObjects` + one `sim_update`, including its view redraws), not an input. The "screen" is the per-view logical frame (see Visual fidelity).

```
session = {
  oracle:   {commit, compiler+version, flags, -DOSF1, harness hash},   // identity, asserted on replay
  start:    city .cty | scenario 1–8 | GenerateSomeCity(seed),
  seed:     SeedRand value applied after load; fixed gettimeofday value,
  views:    [{type, size, scroll origin, overlay mode}] + redraw cadence   // views are recorded
  settings: SimSpeed, GameLevel, autoBudget/autoBulldoze/autoGoto, Disasters on/off,
  events:   [{frame, action}]   // tool x y, tax, fund %, disaster, speed change
  ticks:    [{n, rng[] (value, range, caller), projection-hash, logical-frame-hash per view, messages[] (exact text), (full projection + logical frame every K ticks)}]
}
```

- **The input language** is the `sim` Tcl command set: LoadCity/LoadScenario, Speed, TaxRate, Fire/Police/RoadFund, AutoBudget, MakeFire/Flood/Tornado/Earthquake/Monster/Meltdown, FireBomb, and Tile/Fill for direct map writes. Tools take tile coordinates via `DoTool(view, tool, x, y)` (`w_tool.c:1545`); avoid ToolDown/ToolDrag, which use pixel coordinates and depend on pan. The harness calls the C directly rather than through Tcl.
- **Speed is semantic, not pacing.** `SimFrame` skips 4/5 of frames at speed 1 and 2/3 at speed 2, but sprites move every frame, and scan periods are indexed by speed (`s_sim.c:90–119`). A session must record the speed in effect at every frame.
- **Checkpoints can't be `.cty`.** The save format omits RNG state, sprites, overlays, phase counters, message and disaster state. Loading also reseeds from the clock and reruns `DoSimInit`. Define a full snapshot of the globals plus the RNG's static `next`, generated from `nm` over `.data`/`.bss`. Use `.cty` only as a start format.
- **Generators are easier than NetHack's.** The state space has direct constructors: `Tile`/`Fill`, `GenerateSomeCity(seed)`, 8 scenarios, and 24 bundled cities. The backtrace from an uncovered branch to "a meltdown next to a coal plant at speed 3 with funds < 0" becomes direct map writes, not 40 wizard-mode keystrokes. The open risk is the same as in the talk: a generated state may be impossible to reach in real play.

### 2. How is state checked?

**NetHack (what we did).**
- The judge compares RNG positionally (call sites not judged), plus 24×80 cells and the cursor.
- The campaign oracle records first divergence only, keyed by C location, then shrinks and buckets it.
- Per-function gates load `state_before`, install the C's RNG tape, call, and assert the return value plus the state delta.
- Gates are rated `diverged | high | low` on how much they exercised. A 12-way AND compound gate sits on top, with forward-only ratchets.
- The tests themselves were tested with a honeypot corpus, scrambled answer keys, and mutation of the gate logic.
- Weak points: the compared state was a fixed scalar schema, not a projection chosen per function. Pointer chains went uncaptured, and 269 of 733 gates turned out to be vacuous.

**Micropolis (proposed).** Same layers, but the compared state is an explicit, ratified projection, because the Swift state model is different from the C one.

| Layer | What's compared | Notes |
|---|---|---|
| Session | RNG draw sequence (value + range, exact), plus a per-frame projection | **Projection:** tile map with flag bits; overlays (pop density, traffic, pollution, land value, crime, power, fire/police coverage, growth); funds, tax, the three budget pairs; RCI valves; score, class, `ProblemVotes`/`ProblemOrder`; census histories; sprites (type, x, y, frame, dir); messages as events. **Excluded:** memory layout, padding, the `MiscHis` packing, the UI-only Max fields. |
| Phase / function | The same, scoped to what the function reads and writes | The seam is the C's decomposition: `Simulate` phases, `DoZone` and per-zone handlers, the power/pollution/crime/pop-density/fire scans, `DoTool`, disasters, budget. Swift may restructure *inside* a seam. Moving a seam costs a gate. |
| Abstraction function | C globals ↔ Swift `City` | **New artifact NetHack didn't need.** Agents write it and round-trip test it. Jon ratifies which fields count. |
| Testing the tests | Scrambled keys, planted fakes (lookup table, constants, skipped work), mutation of the gate logic, plus a vacuity census from day 1 | Port the NetHack red-team kit as-is. It's the most transferable part. |

- **In-process gates are cheap here.** Swift imports C natively, without C++ mode. A test target can link the oracle, set C globals from a snapshot, and call `DoMeltdown(x,y)` on both sides, with no file format in between. Everything is a process global, so tests run serially, or with one forked process per test. Statics (`rand.c:42 next`, `s_sim.c:643 RLevels/FLevels`) need C getter/setter shims. Function-like macros (`TILE_IS_*`, `SETPOWERBIT`) don't import, so Swift needs its own versions, and those need differential tests too.
- **Interop stays in the test target.** A Swift wrapper over the C is the transpiler route: faithful because it's still C. "Done" means the sim-core module links no C (checked mechanically: no C target dependency, no C symbols in `nm`).

### 3. How is non-determinism controlled?

**NetHack (what we did).**
- The RNG is frozen and every draw is logged with its C call site; the game's date is fixed, which pins calendar effects.
- Time zone, compiler, platform identity and terminal type are all pinned, each after it was found to have silently changed ground truth (e.g. gcc and clang evaluate a two-draw argument list in opposite orders).

The lesson ranked highest: the worst instrument errors left the RNG stream intact, and nothing gated on environment identity. **Assert the recorder's identity in every session.**

**Micropolis.**

| Source | Where | Control |
|---|---|---|
| RNG | One LCG, `sim_rand` (`rand.c:44`), low 24 bits, so its output doesn't depend on width. `Rand(short)` does rejection sampling, with a `range++` overflow at 32767 (`s_sim.c:1195`). `random.c` (BSD) appears dead; confirm. | Wrap `sim_rand` (its own translation unit, so `--wrap` works) and log value, range and caller. Swift gets an injected `SimRNG` that does **not** conform to `RandomNumberGenerator`. |
| Clock seeding | `RandomlySeedRand` = `usec^sec^sim_rand()` (`s_sim.c:1227`), run on every load, scenario and new city (`s_init.c:73`). `GenerateMap` reseeds after building terrain (`s_gen.c:153`). | `-Wl,--wrap=gettimeofday` to a fixed value. **Verified:** haight 3,000 frames, unpinned clock: 3 runs gave 3 different maps (pop 199,460 / 204,560 / 198,140). Pinned: identical. |
| UI draws from the sim RNG | Earthquake shake, 2 × ShakeNow per view per redraw (`w_map.c:397`, `w_editor.c:906`), cleared by a **real-time** Tk timer. Mono dither (`g_map.c:294`). Colormap fallback (`w_x.c:317`). Camera views (`g_cam.c`, compiled out, so dead). Debug keys. Tcl `sim Rand` in `UIGenerateNewCity` and `UIMakeMonster`. | Views are recorded (Jon), so these draws are part of the session: the oracle is the full app under Xvfb on a virtual clock, every draw is tagged by caller, and the Swift view layer must make the same draws at the same points. Shake end runs on the virtual clock. The headless per-function oracle *injects* UI draws from the log. |
| Message pacing | `doMessage` draws `Rand(5)`, throttled on wall-clock `TickCount()` (`s_msg.c:316`; `w_stubs.c:100` also overflows). `MessagePort` holds one message, so update frequency changes which messages land. | One `sim_update` per tick plus recorded Kick-driven updates; the throttle runs on the virtual clock (and the Swift port reproduces `TickCount`'s overflow); messages recorded as exact text. |
| Timer coupling | The Tk timer drives `sim_loop`, and the delay stretches during mouse-down and quakes (`w_tk.c:581–616`). Tcl `after` timers are used for fire bombs and the budget countdown. | The harness steps frames itself; the timer goes away. Fire bombs and similar timed actions become frame-stamped events. |
| Word size | `QUAD` = `long`. On LP64 the save writes `*(QUAD*)(MiscHis+N)` as 8 bytes and **zeroes CrimeRamp/PolluteRamp** (`s_fileio.c:335`, confirmed). Assessed value `z*1000` is width-dependent. | Pin `-DOSF1` (QUAD = `int`): it preserves the ramps and gives the same sim hashes. Leftover: `_half_swap_longs` handed an `int*`. |
| Undefined behavior / out-of-bounds | `VoteProblems` uses `x > PROBNUM` (`s_eval.c:212,217`): reads `ProblemTable[10]` and writes `ProblemVotes[10]`. Under gcc 13 these land on padding (read 0, write a no-op); older layouts likely differ. `DoMeltdown` writes `Map[SX-1..SX+2]` unchecked at edges (`s_sim.c:1170`). Because `Map` is one contiguous buffer, `Map[x][100]` reads `Map[x+1][0]` **without tripping ASan**. | ASan/UBSan was clean over 5 cities and 8 scenarios × 3,000 frames apart from VoteProblems; tools and disasters were **not** exercised. Add a bounds-checked map accessor to a recording build. Each hit gets a ruling (below). |
| Compiler and flags | K&R C89 with implicit int, so GCC 14+ rejects it. The makefile uses `-O3` with no `-fwrapv`. | `-std=gnu89 -fwrapv -ffp-contract=off`, pinned compiler, recorded in session identity. Check that `-O0` and `-O2` hashes match. |
| Float | Many float ops compute in **double** (`(float)RoadSpend/(float)RoadFund * 32.0`, the demand model `.02`, `3.7`, `1.3`, at `s_sim.c:419–470, 673–686`; `s_eval.c:310`), then truncate to `short`. | Translate as `Float(Double(x) * 1000.0)` followed by an explicit, documented conversion. A per-function gate on each of these. |
| Swift side | Per-process seeded `Dictionary`/`Set` iteration, `Int.random`, clocks, concurrency, Foundation | Sim-core SwiftPM target with zero dependencies, no Foundation or Glibc. Ban `Dictionary`/`Set`/`async`/`.random`/clocks via SwiftLint custom rules. Run the suite twice with **random** hash seeds as a canary (don't set `SWIFT_DETERMINISTIC_HASHING` in CI). |

---

## Idiomatic Swift: what changes vs. NetHack

1. **Agreement on behaviour, not memory.** Exact RNG draw sequence plus the projection above. Draw-order parity is the cheap anchor: in an RNG-driven sim, one reordered draw changes the whole city, so any looser tolerance hides real bugs.
2. **Safety turns C accidents into findings.** Swift traps where C wraps or reads out of bounds, and each trap in the harness needs a ruling:
   - **Intended:** the C relies on it, and the port reproduces it explicitly (`&+`, `truncatingIfNeeded:`) with a comment. Examples: the `(short)(zscore - 26380)` wrap (`s_zone.c:181`); `getRandom(4)` giving 5 park outcomes.
   - **Accident:** patch the oracle to the intended value, record a deliberate divergence, and the port does the safe thing. Examples: VoteProblems out of bounds; the LP64 funds read; meltdown at map edges.

   Agents find and classify; Jon ratifies. This is the paper's boundary between checkable and semantic decisions, now with a ledger.
3. **Idiomatic data model, C's seams.** Value-type `City`, enums for tile kinds and zones, an injected RNG and clock, no globals. Keep the C's function and phase boundaries as the gate seams.
4. **Fallback if per-function gates through the abstraction function are too expensive:** two stages. First a structurally faithful *safe* Swift port gated per function against the C, then a refactor to idioms gated against stage 1, which is Swift-vs-Swift and much cheaper. The risk is that stage 2 never ships.

## Phases

| # | Deliverable | Exit condition |
|---|---|---|
| 0 | Oracle: **session oracle = full app under Xvfb on a virtual clock** (`oracle/build-xvfb.sh`, `oracle/smoke-xvfb.sh`); fast per-function oracle = headless build (`oracle/build-headless.sh`); frame-stepped scheduler replacing Tk timers; identity stamp, `sim_rand` call-site log, bounds-checked recording build, `-DOSF1 -fwrapv -ffp-contract=off` | Same hashes across rebuilds and `-O0`/`-O2`. Identity asserted on replay. |
| 1 | Session recorder plus corpus: 24 cities × 8 scenarios × speeds × autoBudget × view configurations, scripted tool/disaster events, logical frame + messages per tick, classic-skin captures, a full-state snapshot every K ticks | Replay of every session matches. Coverage (gcov over `s_*.c`, the sim part of `w_tool.c`, `w_sprite.c`, `w_budget.c`) reported. |
| 2 | Ratify the projection and abstraction function; UB loop running (detect, perturb, rule, record) | Jon signs off on the projection and the UB policy; the UB loop passes its planted-site test. |
| 3 | Per-function carving plus gates (in-process via C import); red-team kit; vacuity census | Planted fakes fail. Gate-logic mutation kill rate tracked. |
| 4 | Port loop: wave packets at subsystem seams, the NetHack attempt ladder and porter isolation (porters can't edit the oracle, gates, snapshots or the projection) | Every seam green and rated high. Whole-session parity on the full corpus plus a **held-out** corpus porters never see. |
| 5 | Generator: precondition backtrace from uncovered branches to `Tile`/`Fill`/scenario constructions, plus fuzzing over the event language | Feasible coverage plateau. Generated states checked against the C. |

Rough size: about 6.2k lines of sim C (about 4.2k without comments), plus the sim parts of `w_sprite.c`/`w_tool.c`/`w_budget.c`. Roughly a fiftieth of NetHack. Small enough to run the whole loop in weeks and to try ideas cut from the talk, e.g. carving vs. generating.

## Decisions

Jon, 2026-10-03:
- [x] **Message text must match exactly.** Messages are in the projection as text, not ids.
- [x] **Memory errors are decided by an agentic loop**, not case by case by Jon. Design below.
- [x] **32-bit word size** (`-DOSF1`) is the spec.
- [x] **Views are recorded.** The port aims for **visual fidelity with room to reskin** (see "Visual fidelity" below). This also means the oracle needs real Tk under Xvfb, not only the stub build.

Also decided:
- [x] **Staging: idiomatic at C seams** (no two-stage fallback unless gates through the abstraction function prove too expensive).
- [x] **Name: TwinCity** (Jon, 2026-10-03). Repo/package `TwinCity`. Not yet checked for conflicts.
- [x] **UB policy: reproduce the 1990 layout** (below).
- [x] **Repo:** `github.com/jon-bell/TwinCity` (public, GPLv3). Sealed manifests and exam history go in a **private companion repo** (`TwinCity-sealed`), because a sealed generator seed in a public repo lets anyone, porter agents included, regenerate the exam.
- [x] Visual-fidelity survey folded in (below). **Plan complete; scaffold on Jon's go.**

---

## Agentic loop for memory errors and undefined behavior

The paper puts "what must agree" on the human side of the delegation boundary. This loop keeps the human decision at the level of **one policy**, set once. Per-site rulings are delegated, because a perturbation experiment can mostly *measure* whether a site has a meaning.

1. **Detect.** Three detectors run over the whole corpus:
   - a recording build with ASan, UBSan, `-ftrapv` and a bounds-checked `Map` accessor (catches `Map[x][100]`, which ASan misses);
   - Swift traps in differential runs (C continued, Swift trapped);
   - in-range reads of padding or neighbouring globals, flagged by the layout perturbation in step 2.

   Each hit becomes a ledger entry: site, detector, and the sessions that reach it.
2. **Perturb.** An agent re-runs the affected sessions on N perturbed oracle builds, where the UB has room to behave differently: gcc vs clang, `-O0`/`-O2`, `-fcommon`/`-fno-common`, global declaration order shuffled, padding and fresh heap poisoned with random bytes, `malloc` scribble. It diffs the **projection**, not memory.
   - **Invariant:** the UB's value never reaches anything that must agree. Classified *inert*. The Swift port does the safe thing, with no oracle change. This should close most cases automatically.
   - **Varies:** the C has no single meaning, so a ruling is required (step 3).

   This is the fault-injection idea the paper cites (Carbin & Rinard 2010) applied to undefined-behavior sites. It uses internal proxies only, and judgment enters only through the policy.
3. **Rule (policy: reproduce the 1990 layout; see below).** A proposer agent states the value the reference-layout build produces at the site and argues that the build is a faithful stand-in there. An adversary agent tries to show it isn't, e.g. that the neighbouring object differs from the 1990 layout. A verifier checks that the oracle patch is minimal: a re-record diff over the full corpus changes only sessions that reach the site, and only after the first time they reach it.
4. **Record.** The ruling and the oracle patch become a numbered patch in the oracle's patch series. The patches are hashed into the recorder identity, so the corpus re-records and the identity check (below) proves it. The ledger entry keeps the perturbation table, the session diff and both agents' arguments.
5. **Escalate** only when the proposer and adversary disagree after one rebuttal, or when a ruling moves more than a set share of the corpus (5% as a starting value). Jon audits a random sample of closed rulings each wave, using the ledger as the audit trail.

**The policy (Jon, 2026-10-03): reproduce the 1990 layout.** Inert means safe Swift and no oracle change. Changes the state means the oracle is pinned to the value a **1990-era reference layout** produces, and the Swift port reproduces that value explicitly, with a comment and a ledger link. The loop never "fixes to intent": an obvious off-by-one is still the program's behaviour.

This needs one extra instrument: a **reference-layout build** that stands in for 1990. 32-bit (`-m32`, which needs gcc-multilib) and `-fcommon`, with globals laid out in declaration order and link order as in the original makefile. The loop's job at a varying site is then to:
1. determine the reference build's value;
2. check that the value is deterministic across reruns and cases of the same build;
3. patch the oracle so every build produces that value (making the value explicit instead of layout-dependent).

The proposer and adversary argue whether the reference build is a faithful stand-in at that site, e.g. whether it is padding or a neighbour that would have sat there in 1990. VoteProblems is the first case, and it is already measured (`ledger/0001-voteproblems-oob.md`). With `-fno-common` both out-of-bounds slots are padding, and San Francisco at 3,000 frames scores 318. With `-fcommon` (the 1990 linker model, now in the spec flags) `ProblemTable[10]` reads `TrafficAverage` and `ProblemVotes[10]` **writes `CityScore`**, and the score is 322. The neighbours depend on the linker's common-symbol order, so the 32-bit reference build still has to confirm them.

**Testing the loop:** plant known UB sites in a scratch copy of the oracle, some inert and some that change the projection, and require the loop to classify them correctly. This is the honeypot discipline applied to the loop that sets the rules.

---

## Visual fidelity (views recorded, reskinnable)

**Status (2026-10-03).** The original app, with real Tcl 6.7, Tk 2.3 and TclX, builds on gcc 13 x86-64 and runs under Xvfb at 24-bit with XShm. No packages had to be installed: header substitutes stand in for libxext-dev and libxpm-dev, and `tclxgdat.c` is stubbed because there is no yacc. The build is `oracle/build-xvfb.sh`; `oracle/smoke-xvfb.sh` checks determinism.
- With a virtual clock (`--wrap=gettimeofday`), two fresh runs gave **pixel-identical** screenshots (ImageMagick AE=0) at sim_update ticks 20, 60, 120 and 200, with a shake active at 200, and identical RNG draw counts.
- With the real clock, the RNG totals differ by tick 20 and up to 489,743 pixels differ.

**Finding that changes the oracle design: views change sim state.**
- `animateTiles()` (`g_ani.c:67`) rewrites `Map`. It runs only from the editor draw path (`w_editor.c:872`), once per `sim_update`, and only when an editor is visible.
- `doMessage` draws `Rand(5)` up to 3× (`s_msg.c:324`) from `sim_update`.
- With `UserSoundOn` (read from the city file), `MakeSound` runs Tcl `sim Rand 40` (`micropolis.tcl:1027`).
- Editor shake draws 2 per visible editor per tick (`w_editor.c:907`), map shake 2 per map (`w_map.c:398`), plus Expose redraws (`w_tk.c:315`).

So **the session oracle is the full app under Xvfb on a virtual clock**, and the step is the **tick** (`sim_loop(1)`: SimFrame, MoveObjects, sim_update), not a SimFrame. The headless build stays as the fast per-function oracle. Its `SimFrame(); MoveObjects();` loop matches the app only at speed 3 with no views, and a session-level check must not rely on it.

**Scope cuts:**
- **Camera:** compiled out of the original (`#ifdef CAM`, never defined), so it isn't ported.
- **Mono and dither path:** depth 1 won't start on Xvfb, so it can't be oracled. Colour (24-bit) only, and 8-bit as a stretch.

**Logical frame (must match exactly), per view per tick.** All of it can be captured with `--wrap` hooks, with no source edits.
- **Editor:**
  - size, `pan_x/y`, visibility;
  - the per-view tile cache `view->tiles[col][row]`, which already holds the *displayed* id after blink and dynamic filtering;
  - sprites (type, frame, x, y, offsets, w, h) in list order;
  - `PendingTool/X/Y`, and the tool cursor `tool_x/y/mode/showing`;
  - ink and the shake (dx, dy).
- **Map:**
  - `map_state` (15 overlay modes) and `Map & LOMASK` after animation;
  - the overlay array for that mode, and `DynamicData[16]`;
  - editor rectangles, ink and shake.
- **Graph:** the scaled `History10/120` bytes, range, mask, year.
- **Date widget:** month, year, `lastmonth/lastyear`, and the skipped-month trail.
- **Text:** every widget's `-text` and text-widget contents, read by walking the Tcl widget tree at the frame boundary, plus every C→Tcl string captured by wrapping `Eval`.
- **Frame boundary:** wrap `UpdateFlush` (end of each `sim_update`, including Kick-driven updates), then drain Tk idle events and dump.

**Where pixels leak beyond the logical frame:**
- The shake copies to the window at an offset, so the uncovered strip keeps the previous frame.
- The cursor and editor rectangles are drawn directly on the window.
- The pending-tool bob comes from `tv_usec` (`w_editor.c:1068`).
- The ink strategy is chosen by timing an `XSync` (`w_editor.c:1470`).
- `flagBlink` comes from `tv_usec` (`sim.c:251`).
- Tk widgets redraw at idle time.
- Fonts: the `FontInfo` patterns aren't full XLFDs, so Tk falls back to `fixed`.

No XOR drawing was found. Rulings:
1. Blink, bob and shake end are driven by the virtual clock, so they're deterministic and part of the logical frame.
2. The **classic-skin pixel test** compares the editor's back buffer (`pixmap2` after DrawObjects and the chalk overlay, before the shake copy and cursor) and the map's composed image, plus the window only at ticks where no shake is active. The window-level effects (shake offset, cursor) are already exact in the logical frame.
3. The ink strategy is pinned to one branch.
4. Xvfb runs fresh per recording, with fixed `-fp` fonts, no window manager and fixed window placement.

**Exact message text: the sources.**
- `res/stri.301` (64 status messages, via `GetIndString`, `w_resrc.c:165`) and `stri.202`/`stri.219` (zone-status labels).
- C `sprintf` for funds, date, evaluation (class and problem names hard-coded at `w_eval.c:64-75`), budget, demand and options.
- Tcl: 37 notice texts (`micropolis.tcl:425-610`), the "`$CurrentDate: Score …`" line (`:1945`), the budget countdown, and dialog labels.
- Delivery goes through `doMessage` (`s_msg.c:297`), called from `DoUpdateHeads` on every `sim_update`, then `UISetMessage` to the editor label and the head log (trimmed at 500/250 lines).
- There's no localization. The Swift port ships these strings as data, loaded from the same files, never retyped (the generator rule "fail closed against the C's own tables").

**Bugs in the original seen so far**, handled by the policy:
- `TickCount()` overflows (`w_stubs.c:106`), so the 30-second message expiry is effectively random. Pinned by the virtual clock. The Swift port reproduces the overflowed arithmetic on the virtual clock (reproduce policy).
- `GetIndString` copies `strings[num-1]` even after its "monkey's uncle" fallback (`w_resrc.c:204`, missing `else`). This goes through the UB loop if any session reaches it with a bad index.
- `micropolis.tcl:3164` is missing a `[` (`set win WindowLink …`), so starting with `-s N` aborts. The harness doesn't use `-s`: scenarios load via `sim LoadScenario`. The bug is recorded but out of scope (CLI, not sim).
- `xset … >&/dev/null` (`:416`) fails under dash. Harness-side environment patch, recorded in the identity.

**What a session records about views and timing:**
- every view: class, Tk path, size, visibility and stacking, per-tick pan (AutoGoto moves it), `map_state`, `DynamicFilter`, and whether a notice view is up;
- `sim Delay/Skips`, `SimSpeed`, per-view `skips`, `DoAnimation`, `UserSoundOn`, `autoGo`, `DoMessages`, `DoNotices`;
- input as frame-stamped events: Tcl `sim` and editor commands, or synthetic X events for pointer and keyboard paths.

**Deterministic UI driving.** Replace the Tk timer handlers and `after` with a frame-stepped scheduler on the virtual clock. Each tick:
1. inject the recorded events;
2. fire due timers (earthquake end at 3000 ms virtual, the budget countdown, DropFireBombs);
3. `sim_loop(1)`;
4. drain idle;
5. dump the logical frame, plus an `xwd` capture on pixel-test ticks.

---

## Principles carried over from the NetHack port

These are the rules the NetHack C-to-JavaScript campaign paid to learn. They are adopted here as constraints, not suggestions.

- **A corpus is (generator specs × recorder).** Lock both. The recorder identity hashes every committed input that determines a recording (build scripts, oracle patches, harness, upstream commit), not the binary, which embeds its build path. Compiler version is compared too: K&R C on a modern compiler is exactly where undefined behaviour moves. `tools/oracle-identity.py`.
- **Validate every channel; never quote a single number.** "All RNG draws match" said nothing about the screen once. Every validation reports every channel (RNG, projection, logical frame, messages, classic-skin pixels). Every residual is classified or the gate fails. Every gate has a fault mode that proves it can go red.
- **Generators are pure functions of their randomness.** Each generator arm takes all of its nondeterminism from one seeded stream (no clock, no global RNG), so a recorded tape of its draws reproduces the input byte for byte. One file per arm. Fail closed against the C's own tables (tool ids, string tables) instead of hand copies. Every target has a *witness* proving the C actually ran it, and the witness must be able to be absent.
- **Train is targetable; sealed is measure-only.** Sealed corpora live in a separate private repository. They are never named in a brief, never diagnosed, scored on a cadence and not per landing, and their history is aggregate-only. Tools refuse to print per-session sealed results.
- **Steer on coverage of the C, not on a score.** Branch coverage of the simulation C is the goal; the sealed exam is a tripwire.
- **Run the vacuity census from wave 1.** Rate every passing gate on how much it can see: empty assertions, no records, one observed behaviour, and whether a constant-return stub would pass. A green gate is not a working gate. The very first gate in this repo had a surviving boundary mutant until a targeted test was added (`Tests/OracleDifferentialTests`).

## Prior art

- Swiftopolis (jmper1, about 2015): a hobby Swift port derived from Micropolis + MicropolisJ, not playable, no differential testing.
- micropolisJS: derived from the Java version, not the C.
- No published C→Swift agent migration with per-function bit-exact gates turned up.
