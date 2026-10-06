#!/usr/bin/env python3
"""Enforce CLAUDE.md's guarded paths on a PR.

  scripts/check-guarded-paths.py <base-ref> [<head-ref>]   (labels in $PR_LABELS, comma-separated)

Exit 0 when the diff is allowed, 1 (with reasons) when it needs `jon-approved`.
`--self-test` builds scratch repos covering each rule and checks every verdict.
"""
import os, re, subprocess, sys, tempfile

ALWAYS = [r"^CLAUDE\.md$", r"^docs/DESIGN\.md$", r"^\.github/", r"^scripts/check-", r"^oracle/common\.sh$",
          r"^oracle/upstream$", r"^\.gitmodules$"]
RULED = [r"^oracle/patches/", r"^oracle/smoke-[^/]*\.sh$"]

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

def verdict(base, head, labels, cwd=None):
    if "jon-approved" in labels: return []
    changed = [l for l in git("diff", "--name-only", f"{base}...{head}", cwd=cwd).splitlines() if l]
    why = [f"{p}: guarded (needs jon-approved)" for p in changed if any(re.search(r, p) for r in ALWAYS)]
    if "docs/PLAN.md" in changed and plan_guarded(show(base, "docs/PLAN.md", cwd)) != plan_guarded(show(head, "docs/PLAN.md", cwd)):
        why.append("docs/PLAN.md: Exit criteria or Guardrails changed (needs jon-approved)")
    ruled = [p for p in changed if any(re.search(r, p) for r in RULED)]
    if ruled and not ruled_ledger(changed, head, cwd):
        why += [f"{p}: needs a ruled, non-escalated ledger entry in the same PR (or jon-approved)" for p in ruled]
    return why

def self_test():
    cases = [  # (files to write on the branch, labels, expect_ok)
        ({"Sources/TwinCityCore/X.swift": "x"}, [], True),
        ({"CLAUDE.md": "changed"}, [], False),
        ({"CLAUDE.md": "changed"}, ["jon-approved"], True),
        ({"oracle/smoke-headless.sh": "EXPECT=2"}, [], False),
        ({"oracle/smoke-headless.sh": "EXPECT=2", "ledger/0009-x.md": "- **ruling:** `pending`\n- **escalated:** no\n"}, [], False),
        ({"oracle/smoke-headless.sh": "EXPECT=2", "ledger/0009-x.md": "- **ruling:** reproduce: 0\n- **escalated:** yes\n"}, [], False),
        ({"oracle/smoke-headless.sh": "EXPECT=2", "ledger/0009-x.md": "- **ruling:** reproduce: 0\n- **escalated:** no\n"}, [], True),
        ({"docs/PLAN.md": "## Now\nnew\n\n**Exit:** a\n\n## Guardrails\ng\n"}, [], True),
        ({"docs/PLAN.md": "## Now\nold\n\n**Exit:** b\n\n## Guardrails\ng\n"}, [], False),
        ({"docs/PLAN.md": "## Now\nold\n\n**Exit:** a\n\n## Guardrails\nweaker\n"}, [], False),
        ({"oracle/harness/probe.c": "x"}, [], True),
    ]
    ok = True
    for i, (files, labels, expect) in enumerate(cases):
        with tempfile.TemporaryDirectory() as d:
            def w(p, t):
                os.makedirs(os.path.dirname(os.path.join(d, p)) or d, exist_ok=True); open(os.path.join(d, p), "w").write(t)
            git("init", "-q", "-b", "main", cwd=d)
            for p, t in {"CLAUDE.md": "c", "oracle/smoke-headless.sh": "EXPECT=1",
                         "docs/PLAN.md": "## Now\nold\n\n**Exit:** a\n\n## Guardrails\ng\n"}.items(): w(p, t)
            git("add", "-A", cwd=d); git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base", cwd=d)
            git("checkout", "-qb", "pr", cwd=d)
            for p, t in files.items(): w(p, t)
            git("add", "-A", cwd=d); git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "pr", cwd=d)
            got = not verdict("main", "pr", labels, cwd=d)
            if got != expect: ok = False; print(f"self-test case {i} FAILED: {files} {labels} expected ok={expect}")
    print("self-test:", "ok" if ok else "FAILED"); return ok

if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]: sys.exit(0 if self_test() else 1)
    base = sys.argv[1]; head = sys.argv[2] if len(sys.argv) > 2 else "HEAD"
    labels = [l.strip() for l in os.environ.get("PR_LABELS", "").split(",") if l.strip()]
    why = verdict(base, head, labels)
    for w in why: print("guarded-paths:", w)
    print("guarded-paths:", "ok" if not why else "needs jon-approved (see CLAUDE.md, Guarded paths)")
    sys.exit(1 if why else 0)
