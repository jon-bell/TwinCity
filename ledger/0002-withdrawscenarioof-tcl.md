# 0002 WithdrawScenarioOf: missing `[` (Tcl)

- **site:** `res/micropolis.tcl:3164` — `set win WindowLink $head.scenario]`.
- **detector:** manual (session oracle failed to start, 2026-10-03).
- **effect:** every head entering the `play` state (`PrepHead`, `micropolis.tcl:1094`) raises
  "wrong # args". Under `-s N` startup the error is fatal, so the original cannot start a
  scenario from the command line at all.
- **class:** not a memory error, so outside the UB loop's policy. **Escalated to Jon.**
- **oracle patch:** `oracle/patches/0002-tcl-withdrawscenarioof-bracket.patch`, applied
  **provisionally** so the session oracle can run.
- **ruling:** `pending (Jon)`. Options: keep the fix as an environment-level patch (the
  interactive original may surface this as a tkerror dialog and continue; check that first),
  or reproduce the error path in the Swift UI layer.
