#!/usr/bin/env python3
"""Recorder identity: which oracle produced a recording.

A corpus is (generator specs x recorder). This hashes every committed input that determines
what the oracle records: the pinned upstream commit, oracle/patches/*, the build scripts and
spec flags (common.sh), the harness sources and stub headers. It deliberately does NOT hash
the built binary, which embeds its build directory and would change on every rebuild.

The compiler version IS part of the identity here (unlike the NetHack campaign), because
K&R C under a modern compiler is where layout-dependent behaviour moves (ledger/0001).

  tools/oracle-identity.py            print identity JSON
  tools/oracle-identity.py --check F  exit 1 if the current identity differs from F's
"""
import hashlib, json, os, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
O = ROOT / "oracle"
INPUTS = sorted(
    [O / "common.sh", O / "build-headless.sh", O / "build-xvfb.sh"]
    + list((O / "patches").glob("*.patch"))
    + list((O / "harness").glob("*.c"))
    + [p for p in (O / "stubinc").rglob("*") if p.is_file()]
)

# Runtime knobs that change what the oracle records. Set ones join the digest, so a recording
# made with, say, the scheduler off or faulted cannot claim the default identity. (Unset, the
# identity is unchanged. TWINCITY_WALL_DELAY_US is not here: smoke-xvfb.sh proves it inert.)
KNOBS = ["TWINCITY_SCHED", "TWINCITY_SCHED_FAULT", "TWINCITY_VCLOCK_STEP_US", "TWINCITY_VCLOCK_EPOCH"]

def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        return None

def identity():
    files = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()[:16] for p in INPUTS}
    compiler = (run("gcc", "--version") or "").splitlines()[:1]
    upstream = run("git", "-C", str(O / "upstream"), "rev-parse", "HEAD")
    gdat = (O / "build/xvfb/GDAT")
    comps = {"upstream": upstream, "compiler": compiler[0] if compiler else None, "files": files}
    knobs = {k: os.environ[k] for k in KNOBS if k in os.environ}
    if knobs: comps["knobs"] = knobs
    digest = hashlib.sha256(json.dumps(comps, sort_keys=True).encode()).hexdigest()[:16]
    return {"identity": digest, **comps,
            "env": {"tclxgdat": gdat.read_text().strip() if gdat.exists() else None}}  # recorded, not compared

if __name__ == "__main__":
    cur = identity()
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        want = json.loads(pathlib.Path(sys.argv[2]).read_text())
        if want["identity"] != cur["identity"]:
            changed = [k for k in set(cur["files"]) | set(want["files"]) if cur["files"].get(k) != want["files"].get(k)]
            for k in ("upstream", "compiler", "knobs"):
                if cur.get(k) != want.get(k): changed.append(k)
            print(f"identity drift {want['identity']} -> {cur['identity']}: {sorted(changed)}"); sys.exit(1)
        print(f"ok {cur['identity']}"); sys.exit(0)
    print(json.dumps(cur, indent=2))
