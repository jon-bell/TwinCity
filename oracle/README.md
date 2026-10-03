# The oracle

`upstream/` is the original program, pinned (git submodule, `simhacker/micropolis` @ c98f6b0).
Nothing here edits it in place: builds copy `upstream/micropolis-activity` into `build/` and
apply `patches/` in order. **Every patch is part of the recorder identity**
(`tools/oracle-identity.py`) and must have a `ledger/` entry or say why it is environment-only.

| build | script | use |
|---|---|---|
| headless | `build-headless.sh` → `build/headless/{liboracle.a,twincity-headless}` | per-function differential gates (Swift links `liboracle.a` in-process); fast smoke runs. Runs `SimFrame`+`MoveObjects` only: no views, speed 3. **Not** a session oracle. |
| xvfb | `build-xvfb.sh` → `build/xvfb/tree/src/sim/sim` | the session oracle: full app, real Tk, views open, virtual clock |

Spec flags (`common.sh`): `-std=gnu89 -fcommon -fno-strict-aliasing -fwrapv -ffp-contract=off -DOSF1`.
`-DOSF1` makes `QUAD` 32-bit (the spec word size); `-fcommon` is the 1990 linker model and
**changes behaviour** (ledger/0001).

Harness (`harness/`), all link-time `--wrap`, with no source edits:
- `wrap_clock.c`: virtual clock for `gettimeofday` (frozen by default; `TWINCITY_VCLOCK_STEP_US` to advance per call).
- `wrap_rand.c`: every `sim_rand` draw, with caller PCs, to `$TWINCITY_RANDLOG`.
- `probe_frame.c`: per-tick hook at `UpdateFlush`; xwd captures (`TWINCITY_CAPS`, `TWINCITY_STOP`, `TWINCITY_OUT`).
- `ui_stubs.c`, `xstubs.c`, `headless_main.c`: the headless build's UI stand-ins and driver.
  `InitGraphMax` is copied verbatim, because it mutates sim state.
- `tclxgdat-stub.c`: used only when no yacc/bison is available (recorded in the identity env).

`stubinc/` holds ABI-compatible XShm/shape/xpm headers for hosts without libxext-dev/libxpm-dev.

Known gaps, which are phase-1 work:
- range logging for `Rand` (calls from inside `s_sim.c` aren't interceptable by `--wrap`);
- logical-frame dumps (currently screenshots only);
- full-state snapshots;
- the 32-bit reference-layout build (`-m32`).
