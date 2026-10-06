# TwinCity

An agent-driven port of the **original Micropolis C** (the GPL release of the 1989 SimCity
source, OLPC/Unix version) to **idiomatic, memory-safe Swift**, where every step is checked
by differential testing against the original program running beside it. Two cities, one plan.

- **The oracle is the original program.** The pinned upstream (`oracle/upstream`, the
  `micropolis-activity` C/Tcl/Tk code) is built two ways: a headless sim-only library for fast
  per-function gates, and the full app under Xvfb on a virtual clock for whole sessions with
  views open. Both are deterministic (`oracle/smoke-*.sh`).
- **The port is not a transpile.** `TwinCityCore` is a dependency-free Swift module with its
  own data model. It agrees with the original on a ratified *projection* of state, the exact
  RNG draw sequence, exact message text, and a per-view *logical frame*. Pixels are free to
  change (reskinning is allowed), but the classic skin must match the original pixel for pixel.
- **Undefined behaviour gets a ruling, not a copy.** Safe Swift traps where C silently wraps
  or reads out of bounds. Each site goes through an agentic loop (detect → perturb → rule →
  record) under one fixed policy: reproduce what the 1990 memory layout did. See `ledger/`.

Design: [`docs/DESIGN.md`](docs/DESIGN.md). Plan and exit criteria: [`docs/PLAN.md`](docs/PLAN.md). Agent rules: [`CLAUDE.md`](CLAUDE.md).

## Quick start

```sh
git submodule update --init                # pinned upstream (shallow)
oracle/build-headless.sh && oracle/smoke-headless.sh
swift test                                 # golden tests, no oracle needed
TWINCITY_ORACLE=1 swift test               # + per-function differential gates vs. the C
oracle/build-xvfb.sh && oracle/smoke-xvfb.sh   # session oracle (needs Xvfb, xwd, ImageMagick)
scripts/check-core-purity.sh               # TwinCityCore stays pure
tools/oracle-identity.py                   # which oracle produced a recording
```

Requires Swift 6, gcc, and for the session oracle the X11 client libraries (libX11, libXext,
libXpm) plus Xvfb.

## Status (2026-10-03)

Scaffold. Ported so far: the RNG (`sim_rand`, `Rand`, `Rand16`, `Rand16Signed`), gated
in-process against the C, including a rejection-boundary test that a planted `>=`→`>` mutant
fails. The first ledger entries are open: `VoteProblems` out of bounds, which is measurably
layout-dependent (score 318 vs 322), and a Tcl bug that blocks scenario startup.

## License

GPLv3 or later with Electronic Arts' additional terms (see `LICENSE` and `NOTICE`). This is
a modified version of Micropolis and is not affiliated with Electronic Arts or Micropolis GmbH.
