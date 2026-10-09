# The oracle

`upstream/` is the original program, pinned (git submodule, `simhacker/micropolis` @ c98f6b0).
Nothing here edits it in place: builds copy `upstream/micropolis-activity` into `build/` and
apply `patches/` in order. **Every patch is part of the recorder identity**
(`tools/oracle-identity.py`) and must have a `ledger/` entry or say why it is environment-only.

| build | script | use |
|---|---|---|
| headless | `build-headless.sh` → `build/headless/{liboracle.a,twincity-headless}` | per-function differential gates (Swift links `liboracle.a` in-process); fast smoke runs. Runs `SimFrame`+`MoveObjects` only: no views, speed 3. **Not** a session oracle. |
| xvfb | `build-xvfb.sh` → `build/xvfb/tree/src/sim/sim` | the session oracle: full app, real Tk, views open, virtual clock |
| detect | `build-detect.sh` → `build/detect/{twincity-detect,twincity-detect-off}`; `run-detect.sh` | UB detector (P0.5): the headless sources under ASan + UBSan + `-ftrapv`, `-fno-common -fno-wrapv`, plus bounds-checked row-pointer maps (`detect/row-accessor.py`). Reports each site as `file:line` into `build/detect/SITES`; the expected list is `baselines/detect-sites.txt`. Not a recording oracle; `detect/` is outside the identity. |
| reference | `build-reference.sh` → `build/reference/{tree/src/sim/sim,twincity-reference}` | ledger rulings: the full app at `-m32`, linked by the original makefile; `twincity-reference` is that link entered through the headless driver (`twincity-reference RES S2 3000`) |

**Layout is a property of the whole link.** GNU ld places common symbols in link-hash-table
order, so adding *any* symbol to a link (even an unrelated function) can move which object an
out-of-bounds access lands in (ledger/0001). `tools/layout-neighbour.py BIN SYM INDEX SIZE`
reports where `&SYM[INDEX]` lands. `build-reference.sh` fails if its driver link and the app link
disagree at the ledger sites (`REFERENCE_FAULT=driver-symbols` shows it going red). Perturbation
knobs for ledger tables: `WIDTH=64`, `OPT=-O0`, `EXTRA_CFLAGS=...`.

**32-bit binaries on a kernel without IA32 emulation** (e.g. a Kata guest: "Exec format error"):
install `gcc-multilib libx11-dev:i386 libxext-dev:i386 libxpm-dev:i386 qemu-user` (after
`dpkg --add-architecture i386`), then register qemu-i386 with binfmt_misc (until reboot):

```sh
sudo mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null
echo ':qemu-i386:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x03\x00:\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-i386:' \
  | sudo tee /proc/sys/fs/binfmt_misc/register
```

Spec flags (`common.sh`): `-std=gnu89 -fcommon -fno-strict-aliasing -fwrapv -ffp-contract=off -DOSF1`.
`-DOSF1` makes `QUAD` 32-bit (the spec word size); `-fcommon` is the 1990 linker model. It
used to change behaviour at ledger/0001, which `patches/0003` now pins.

Harness (`harness/`), all link-time `--wrap`, with no source edits:
- `wrap_clock.c`: virtual clock for `gettimeofday` (frozen by default; `TWINCITY_VCLOCK_STEP_US` to advance per call,
  except when `sched.c` owns the clock).
- `wrap_rand.c`: every `sim_rand` draw, with caller PCs, to `$TWINCITY_RANDLOG`.
- `probe_frame.c`: per-tick hook at `UpdateFlush`; xwd captures (`TWINCITY_CAPS`, `TWINCITY_STOP`, `TWINCITY_OUT`),
  a per-tick trace (`TWINCITY_TRACE`), and `TWINCITY_WALL_DELAY_US` to imitate a slower host.
- `sched.c` (xvfb build): the frame-stepped scheduler. Tk's timers move into a virtual queue that
  copies Tk 2.3's ordering quirks, and the virtual clock advances only when the app would block,
  after an `XSync` and a full drain of X and idle events. Recordings are therefore independent of
  host speed; `smoke-xvfb.sh` runs at two speeds to prove it. `TWINCITY_SCHED=off` restores the
  old per-call clock; `TWINCITY_SCHED_FAULT=wallclock` is the planted fault.
- `ui_stubs.c`, `xstubs.c`, `headless_main.c`: the headless build's UI stand-ins and driver.
  `InitGraphMax` is copied verbatim, because it mutates sim state.
- `reference_main.c`: `__wrap_main` for the reference build; an empty Tcl interpreter and
  `initGraphs`, then `headless_main.c` unchanged.
- `tclxgdat-stub.c`: used only when no yacc/bison is available (recorded in the identity env).

`stubinc/` holds ABI-compatible XShm/shape/xpm headers for hosts without libxext-dev/libxpm-dev.

Known gaps, which are phase-1 work:
- range logging for `Rand` (calls from inside `s_sim.c` aren't interceptable by `--wrap`);
- logical-frame dumps (currently screenshots only);
- wall-clock inputs left for event injection (P1.6): X server timestamps (double-click, selection
  timeouts) and stdin under `-t` still come from the real world; injected events need virtual
  timestamps;
- of the scheduler's timed paths, only the earthquake end is exercised (in `smoke-xvfb.sh`); the
  budget countdown and DropFireBombs wait for scripted sessions;
- full-state snapshots.
