#!/usr/bin/env python3
"""Enforce CLAUDE.md's guarded paths on a PR.

  scripts/check-guarded-paths.py <base-ref> [<head-ref>]
      $PR_LABELS  the PR's labels, comma-separated
      $PR_BODY    the PR's description; each `Implements #N` names an issue it carries out

Exit 0 when the diff is allowed, 1 (with reasons) when it needs `jon-approved`.
An issue counts as decided only if it carries `jon-ruled` (looked up with `gh`; any lookup
failure counts as not ruled). `--self-test` builds scratch repos covering each rule.
"""
import os, re, subprocess, sys, tempfile

ALWAYS = [r"^CLAUDE\.md$", r"^docs/DESIGN\.md$", r"^\.github/", r"^scripts/check-", r"^oracle/common\.sh$",
          r"^oracle/upstream$", r"^\.gitmodules$"]
PATCHES = r"^oracle/patches/"
BASELINES = r"^oracle/baselines/"
SMOKE = r"^oracle/smoke-[^/]*\.sh$"

def git(*a, cwd=None):
    return subprocess.run(["git", *a], capture_output=True, text=True, check=True, cwd=cwd).stdout

def show(ref, path, cwd):
    try: return git("show", f"{ref}:{path}", cwd=cwd)
    except subprocess.CalledProcessError: return ""

def plan_guarded(text):
    """The parts of docs/PLAN.md agents may not change: every **Exit:** paragraph and the Guardrails section."""
    exits = re.findall(r"^\*\*Exit:\*\*.*?(?=\n\n|\Z)", text, flags=re.S | re.M)
    g = text.split("## Guardrails", 1)
    return exits + ([g[1]] if len(g) > 1 else [])

def ruled_ledger(changed, head, cwd):
    """True if the PR adds/edits a ledger entry that carries a non-pending, non-escalated ruling."""
    for p in changed:
        if re.match(r"^ledger/\d{4}-.*\.md$", p):
            t = show(head, p, cwd)
            m = re.search(r"^- \*\*ruling:\*\*\s*`?([^`\n]*)", t, flags=re.M)
            esc = re.search(r"^- \*\*escalated:\*\*\s*(\S+)", t, flags=re.M)
            if m and not m.group(1).startswith("pending") and esc and esc.group(1).lower().startswith("no"):
                return True
    return False

def gh_jon_ruled(n):
    try:
        out = subprocess.run(["gh", "issue", "view", str(n), "--json", "labels", "-q", ".labels[].name"],
                             capture_output=True, text=True, check=True, timeout=60).stdout
    except Exception:
        return False
    return "jon-ruled" in out.split()

def implements_ruled(body, is_ruled):
    """Issues the PR says it implements that Jon has ruled on (label `jon-ruled`)."""
    return [n for n in re.findall(r"\bImplements #(\d+)\b", body or "", flags=re.I) if is_ruled(n)]

def verdict(base, head, labels, cwd=None, body="", is_ruled=gh_jon_ruled):
    if "jon-approved" in labels: return []
    status = [l.split("\t") for l in git("diff", "--no-renames", "--name-status", f"{base}...{head}", cwd=cwd).splitlines() if l]
    changed = [p for _, p in status]
    why = [f"{p}: guarded (needs jon-approved)" for p in changed if any(re.search(r, p) for r in ALWAYS)]
    if "docs/PLAN.md" in changed and plan_guarded(show(base, "docs/PLAN.md", cwd)) != plan_guarded(show(head, "docs/PLAN.md", cwd)):
        why.append("docs/PLAN.md: Exit criteria or Guardrails changed (needs jon-approved)")
    # Baseline values live in oracle/baselines/, never in the smoke scripts.
    for p in changed:
        if re.search(SMOKE, p) and re.search(r"^\s*EXPECT\w*=", show(head, p, cwd), flags=re.M):
            why.append(f"{p}: baseline value in a smoke script (move it to oracle/baselines/)")
    # Ground truth: patches, and changes to existing baselines (adding a new baseline is allowed:
    # the PR's own CI run has to reproduce it).
    ruled = [p for s, p in status if re.search(PATCHES, p) or (re.search(BASELINES, p) and s != "A")]
    if ruled and not ruled_ledger(changed, head, cwd) and not implements_ruled(body, is_ruled):
        why += [f"{p}: needs a ruled, non-escalated ledger entry, or `Implements #N` for a jon-ruled issue "
                f"(or jon-approved)" for p in ruled]
    return why

def self_test():
    ruled_issues = {"7"}
    is_ruled = lambda n: n in ruled_issues
    led = lambda r, e: {"ledger/0009-x.md": f"- **ruling:** {r}\n- **escalated:** {e}\n"}
    cases = [  # (files to write on the branch (None deletes), PR body, labels, expect_ok)
        ({"Sources/TwinCityCore/X.swift": "x"}, "", [], True),
        ({"CLAUDE.md": "changed"}, "", [], False),
        ({"CLAUDE.md": "changed"}, "", ["jon-approved"], True),
        ({"CLAUDE.md": "changed"}, "Implements #7", [], False),            # a ruling never unlocks ALWAYS paths
        ({".github/workflows/ci.yml": "x"}, "Implements #7", [], False),
        ({"scripts/check-guarded-paths.py": "x"}, "", [], False),
        ({"scripts/ci-extra.sh": "echo more checks"}, "", [], True),       # the agent-owned CI extension point
        ({"oracle/smoke-headless.sh": "cmp $(cat baselines/headless.txt) && stricter"}, "", [], True),
        ({"oracle/smoke-headless.sh": "EXPECT=2"}, "", [], False),          # value smuggled into a script
        ({"oracle/smoke-new.sh": "  EXPECT_LAYOUT=x"}, "", [], False),
        ({"oracle/baselines/new.txt": "v"}, "", [], True),                  # new baseline: CI reproduces it
        ({"oracle/baselines/headless.txt": "2"}, "", [], False),            # moving existing ground truth
        ({"oracle/baselines/headless.txt": None}, "", [], False),           # deleting it
        ({"oracle/baselines/headless.txt": "2", **led("`pending`", "no")}, "", [], False),
        ({"oracle/baselines/headless.txt": "2", **led("reproduce: 0", "yes")}, "", [], False),
        ({"oracle/baselines/headless.txt": "2", **led("reproduce: 0", "no")}, "", [], True),
        ({"oracle/baselines/headless.txt": "2", **led("reproduce: 0", "yes")}, "Implements #7", [], True),
        ({"oracle/baselines/headless.txt": "2"}, "Implements #8", [], False),  # #8 not jon-ruled
        ({"oracle/baselines/headless.txt": "2"}, "Closes #7", [], False),      # only `Implements` counts
        ({"oracle/patches/0009-x.patch": "p"}, "", [], False),
        ({"oracle/patches/0009-x.patch": "p"}, "Fixes it.\n\nImplements #7.", [], True),
        ({"docs/PLAN.md": "## Now\nnew\n\n**Exit:** a\n\n## Guardrails\ng\n"}, "", [], True),
        ({"docs/PLAN.md": "## Now\nold\n\n**Exit:** b\n\n## Guardrails\ng\n"}, "", [], False),
        ({"docs/PLAN.md": "## Now\nold\n\n**Exit:** a\n\n## Guardrails\nweaker\n"}, "", [], False),
        ({"oracle/harness/probe.c": "x"}, "", [], True),
    ]
    ok = True
    for i, (files, body, labels, expect) in enumerate(cases):
        with tempfile.TemporaryDirectory() as d:
            def w(p, t):
                f = os.path.join(d, p)
                if t is None: os.remove(f); return
                os.makedirs(os.path.dirname(f) or d, exist_ok=True); open(f, "w").write(t)
            git("init", "-q", "-b", "main", cwd=d)
            for p, t in {"CLAUDE.md": "c", "oracle/smoke-headless.sh": "cmp $(cat baselines/headless.txt)",
                         "oracle/baselines/headless.txt": "1",
                         "docs/PLAN.md": "## Now\nold\n\n**Exit:** a\n\n## Guardrails\ng\n"}.items(): w(p, t)
            git("add", "-A", cwd=d); git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base", cwd=d)
            git("checkout", "-qb", "pr", cwd=d)
            for p, t in files.items(): w(p, t)
            git("add", "-A", cwd=d); git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "pr", cwd=d)
            got = not verdict("main", "pr", labels, cwd=d, body=body, is_ruled=is_ruled)
            if got != expect: ok = False; print(f"self-test case {i} FAILED: {files} {body!r} {labels} expected ok={expect}")
    print(f"self-test: {len(cases)} cases", "ok" if ok else "FAILED"); return ok

if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]: sys.exit(0 if self_test() else 1)
    base = sys.argv[1]; head = sys.argv[2] if len(sys.argv) > 2 else "HEAD"
    labels = [l.strip() for l in os.environ.get("PR_LABELS", "").split(",") if l.strip()]
    why = verdict(base, head, labels, body=os.environ.get("PR_BODY", ""))
    for w in why: print("guarded-paths:", w)
    print("guarded-paths:", "ok" if not why else "needs jon-approved (see CLAUDE.md, Guarded paths)")
    sys.exit(1 if why else 0)
