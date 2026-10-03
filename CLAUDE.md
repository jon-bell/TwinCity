# CLAUDE.md: TwinCity constitution

TwinCity ports the original Micropolis C (`oracle/upstream/micropolis-activity`) to idiomatic,
safe Swift (`Sources/TwinCityCore`). The original program is the oracle. Read
`docs/DESIGN.md` before planning any work; this file is the rules, and the design doc is the why.

## What "done" means for a unit of work

A C function (or phase, or tool) is ported when **all** of these hold:
1. Its Swift counterpart passes a per-function differential gate against the C oracle
   (`Tests/OracleDifferentialTests`), in process, on recorded pre-states.
2. The gate is **not vacuous**. It has records, a non-empty assertion surface, more than one
   observed behaviour, and it fails against planted fakes: a constant-return stub, a
   lookup table, skipped work, and boundary mutants. Add the planted fake to the test that
   kills it.
3. Whole-session parity on train holds or improves: RNG draw sequence exact, projection
   exact, logical frame exact, message text exact.
4. `scripts/check-core-purity.sh` passes.

## Cardinal rules

1. **The oracle is ground truth, including its bugs.** Never "fix" behaviour in Swift
   because the C looks wrong. Undefined or layout-dependent behaviour goes through
   `ledger/` under the fixed policy (reproduce the 1990 layout); everything else is
   reproduced exactly, with a `// C:` comment citing file:line.
2. **Only the first divergence is meaningful.** Diagnose the earliest tick and draw where
   Swift and C disagree. Later differences are consequences.
3. **Do not edit the referee.** Porters never edit `oracle/` (upstream, patches, harness,
   build scripts), the gates' comparison code, recorded fixtures, corpus manifests, or
   `docs/DESIGN.md`'s projection. Those changes go through the supervisor and land with a
   ledger entry or an identity change.
4. **TwinCityCore imports nothing.** No Foundation, Glibc/Darwin, or C. No stdlib randomness,
   clocks, concurrency, `Dictionary`/`Set`, or `Unsafe*`. All randomness flows through
   `SimRNG`; the port must make the same draws in the same order as the C.
5. **Interop is test-only.** Never wrap or call the C from shipped code. That is the
   transpiler route, and it would make the port faithful only because it is still C.
6. **Keep the C's seams.** The C's function and phase boundaries are where gates attach.
   Restructure freely inside a seam. Moving a seam needs a new gate first.
7. **Integers and floats are explicit.** Wrapping arithmetic (`&+ &- &*`, `&<<`) and
   `truncatingIfNeeded:` wherever the C relies on wrap or truncation. Do float math in
   `Double` where C promotes `float * double-literal`. Emulate C's float→int conversion
   explicitly. A Swift trap in a differential run is a finding: report it to the ledger,
   and don't silence it.
8. **Text comes from the original's data.** Message strings are loaded from the original
   `res/stri.*` files and Tcl sources, never retyped.
9. **Sealed is sealed.** The sealed corpus lives in the private `TwinCity-sealed` repo. Never
   name a sealed session in a brief, never diagnose one, never commit its seed here. If a
   sealed result looks interesting, generate a new train session that exercises the same code.
10. **A green instrument is not a working one.** Every new gate, generator witness, or
    validator ships with a fault mode that proves it can go red.

## Determinism

- The oracle runs only through the harness: virtual clock (`wrap_clock.c`), spec flags
  (`oracle/common.sh`), patches in order. `tools/oracle-identity.py` names the oracle.
  Recordings carry it, and replays assert it.
- Sessions are ticks (`sim_loop(1)`), not `SimFrame`s. Speed, views, and timers are session
  content (`docs/DESIGN.md`, "Visual fidelity").
- Oracle globals are process-global: oracle-backed test suites are `.serialized`.

## Roles

- **Supervisor**: plans waves, owns `oracle/`, gates, ledger rulings, manifests, and this file.
  Never ports.
- **Porter**: one seam per packet, in an isolated worktree. Edits only the target Swift file(s)
  and their tests. Propose-only. The supervisor integrates.
- **UB proposer / adversary / verifier**: the ledger loop (`ledger/README.md`). Escalate to
  Jon on disagreement after one rebuttal, or when a ruling moves more than 5% of the corpus.
- **Jon**: owns the projection, the policy, and escalations. Audits a sample of rulings each wave.

## Commands

```sh
oracle/build-headless.sh && oracle/smoke-headless.sh
TWINCITY_ORACLE=1 swift test
oracle/build-xvfb.sh && oracle/smoke-xvfb.sh
scripts/check-core-purity.sh
tools/oracle-identity.py
```
