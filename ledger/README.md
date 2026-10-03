# Ruling ledger

One file per site where the original C's behaviour is undefined, layout-dependent, or
otherwise needs a ruling before the port can agree with it. The loop that fills this
ledger is specified in `docs/DESIGN.md` ("Agentic loop for memory errors and undefined
behavior"). **Policy (fixed): reproduce the 1990 layout.** Inert sites get safe Swift and no
oracle change; sites that change the projection get the 1990 reference-layout value, pinned
in the oracle by a numbered patch and reproduced explicitly in Swift.

Each entry records:

| field | meaning |
|---|---|
| `site` | file:line in `oracle/upstream/micropolis-activity/src/` |
| `detector` | sanitizer, bounds-checked accessor, Swift trap, layout perturbation, or manual |
| `sessions` | which corpus sessions reach it (train/probe only; never name sealed sessions) |
| `perturbation` | table: build variant → projection outcome |
| `class` | `inert` or `varies` |
| `ruling` | `safe-swift` (inert) or `reproduce: <value>`; or `pending` |
| `oracle patch` | `oracle/patches/NNNN-*.patch`, if any (patches are part of the recorder identity) |
| `arguments` | proposer, adversary, verifier summaries |
| `escalated` | yes/no, and why |
