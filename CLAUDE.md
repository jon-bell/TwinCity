# CLAUDE.md: TwinCity constitution

TwinCity ports the original Micropolis C (`oracle/upstream/micropolis-activity`) to idiomatic,
safe Swift (`Sources/TwinCityCore`). The original program is the oracle. Agents work here
**autonomously**: this file is the rules, `docs/PLAN.md` is the work and its exit criteria,
and `docs/DESIGN.md` is the why. Read all three before starting.

## Autonomous session loop

Every session, in order:

1. **Sync and verify.** Pull `main` and run `git submodule update --init`. Check that CI on
   `main` is green (`gh run list -L 1`). If it's red, fixing it is your task. If the cause
   isn't clear after one attempt, open a `needs-jon` issue and stop, rather than stacking
   changes on a red main.
2. **Pick work.** Take the top unclaimed item in `docs/PLAN.md` → **Now**, or the
   earliest unchecked task of the current phase. Claim it with a GitHub issue titled with
   its task id (e.g. `P0.4 reference-layout build`), assigned to yourself and labelled with
   its phase. Skip tasks with an open issue labelled `blocked` or `needs-jon`.
3. **Work on a branch** `agent/<task-id>-<slug>`. Keep commits small. Every claim in a PR is
   backed by a command and its output.
4. **Prove it.** Run everything CI runs (see Commands) locally first. Every new instrument,
   gate or validator ships with a fault mode that shows it can go red, and the PR includes
   that output.
5. **Open a PR** that closes the issue. Its body states what changed, the evidence, what
   was not checked, and the plan checkbox it ticks.
6. **Merge or hand off.** Squash-merge your own PR only when CI is green and the
   guarded-paths check passes. Otherwise leave it open with `needs-jon`. Update **Now** in
   `docs/PLAN.md` if the next priorities changed.

**Stop and escalate** (a `needs-jon` issue, then move to other unblocked work) when:
- a smoke baseline or recorded ground truth would change without a ruled ledger entry;
- the oracle identity drifts unexpectedly;
- a ledger ruling escalates (proposer and adversary still disagree after one rebuttal, or a
  ruling moves more than 5% of the corpus);
- a task needs a decision `docs/DESIGN.md` marks as Jon's: the projection, the abstraction
  function, the policy, or naming and licensing;
- you would need root, a new paid service, or any repository other than TwinCity;
- the same task has failed 3 attempts. Write up the diagnosis on its issue and label it
  `blocked`.

## Guarded paths

`scripts/check-guarded-paths.py` runs on every PR and enforces the following.

| Paths | Rule |
|---|---|
| `CLAUDE.md`, `docs/DESIGN.md`, `.github/**`, `scripts/check-*`, `oracle/common.sh` (spec flags), `oracle/upstream` (pinned commit), and the **Guardrails** and **Exit** text in `docs/PLAN.md` | Needs the label `jon-approved`, which only Jon applies. |
| `oracle/patches/**`, `oracle/smoke-*.sh` (baselines) | Allowed only together with a ledger entry in the same PR whose ruling is not `pending` and which is not escalated. Otherwise needs `jon-approved`. |
| Everything else, including `oracle/harness/**` and the build scripts | Normal review. CI must stay green with the smoke baselines unchanged; that is the proof that instrumentation didn't move ground truth. |

**Never apply `jon-approved` yourself, and never remove `needs-jon`.** Agents run on Jon's
credentials, so the label is a promise, not a lock. Self-approval is the one violation that
defeats every other guardrail. Never push to `main` directly; branch protection requires CI.

## What "done" means for a port

A C function, phase or tool is ported when **all** of these hold:
1. Its Swift counterpart passes a per-function differential gate against the C oracle,
   in process, on recorded pre-states (`Tests/OracleDifferentialTests`).
2. The gate is **not vacuous**:
   - it has records and a non-empty assertion surface;
   - it sees more than one behaviour;
   - it fails against planted fakes: a constant-return stub, a lookup table, skipped work,
     and boundary mutants.

   Commit each planted fake with the test that kills it.
3. Whole-session parity on train holds or improves: the RNG draw sequence, the projection,
   the logical frame and the message text are all exact.
4. `scripts/check-core-purity.sh` passes.

## Cardinal rules

1. **The oracle is ground truth, including its bugs.** Never fix behaviour in Swift because
   the C looks wrong. Undefined or layout-dependent behaviour goes through `ledger/` under the
   fixed policy, reproduce the 1990 layout. Everything else is reproduced exactly, with a
   `// C: file.c:line` comment.
2. **Only the first divergence is meaningful.** Diagnose the earliest tick and draw where Swift
   and C disagree. Later differences are consequences.
3. **Don't edit the referee to get green.** Porters don't touch `oracle/`, gate comparison
   code, recorded fixtures or corpus manifests. Changing those is instrument work: its own
   task, its own PR, its own proof.
4. **TwinCityCore imports nothing.** No Foundation, Glibc/Darwin, or C. No stdlib randomness,
   clocks, concurrency, `Dictionary`/`Set`, or `Unsafe*`. All randomness goes through
   `SimRNG`, making the same draws in the same order as the C.
5. **Interop is test-only.** Never call the C from shipped code. A port that wraps the C is
   faithful only because it is still C.
6. **Keep the C's seams.** Gates attach at the C's function and phase boundaries.
   Restructure freely inside a seam. To move a seam, add the new gate first.
7. **Integers and floats are explicit.**
   - Use wrapping arithmetic (`&+ &- &*`, `&<<`) and `truncatingIfNeeded:` wherever the C
     wraps or truncates.
   - Use `Double` where C promotes `float * double-literal`.
   - Emulate C's float→int conversion explicitly.
   - A Swift trap in a differential run is a finding. Report it to the ledger; don't silence it.
8. **Text comes from the original's data** (`res/stri.*`, Tcl sources). Never retype it.
9. **Sealed is sealed.** Never clone, read or mention the contents of `jon-bell/TwinCity-sealed`,
   even though your credentials may reach it. If an aggregate exam result is posted to the
   exam-log issue, treat it as a tripwire and never as a target. To probe something it
   suggests, generate new *train* sessions.
10. **A green instrument is not a working one.** Nothing ships without a demonstrated way
    to go red.

## Determinism

- The oracle runs only through the harness: the virtual clock (`wrap_clock.c`), the spec
  flags (`oracle/common.sh`), and the patches in order. `tools/oracle-identity.py` names the
  oracle; recordings carry that identity and replays assert it.
- Sessions are ticks (`sim_loop(1)`), not `SimFrame`s. Speed, views and timers are session
  content.
- The oracle's state is process-global, so oracle-backed test suites are `.serialized`.

## Environment

- Swift 6.x. On Jon's dev VM it's at `~/.local/swift/swift-6.4.0-RELEASE-ubuntu24.04/usr/bin`,
  not on `PATH` by default.
- No sudo. If a task needs a system package, use CI (where `apt-get` works) or open a
  `needs-jon` issue.
- Push over HTTPS. The repo's credential helper is `gh auth git-credential`.
- Commit trailer: `Co-Authored-By: <model> <noreply@anthropic.com>`.

## Commands

```sh
git submodule update --init
oracle/build-headless.sh && oracle/smoke-headless.sh
swift test && TWINCITY_ORACLE=1 swift test
oracle/build-xvfb.sh && oracle/smoke-xvfb.sh
scripts/check-core-purity.sh
tools/oracle-identity.py
```
