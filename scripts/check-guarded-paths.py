#!/usr/bin/env python3
"""Enforce CLAUDE.md's guarded paths on a PR.

  scripts/check-guarded-paths.py <base-ref> [<head-ref>]
      $PR_LABELS  the PR's labels, comma-separated
      $PR_BODY    the PR's description

Exit 0 when the diff is allowed, 1 (with reasons) when it needs `jon-approved`.
A PR carries out a decision when its body has a line that is exactly `Implements #N` (outside
HTML comments and code blocks) and also says `Closes #N`, and #N is an *open issue* (not a PR)
labelled `jon-ruled`. Merging closes #N, so each ruling unlocks one PR. The lookup uses `gh`;
any failure counts as not ruled. `--self-test` builds scratch repos covering each rule.
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

def diff_status(base, head, cwd):
    """[(status, path)] with raw paths (-z: no quoting, so non-ASCII or quoted names still match)."""
    f = git("diff", "-z", "--no-renames", "--name-status", f"{base}...{head}", cwd=cwd).split("\0")
    if f and f[-1] == "": f.pop()
    if len(f) % 2: raise SystemExit("guarded-paths: unparseable diff (odd field count): FAIL")
    out = list(zip(f[0::2], f[1::2]))
    bad = [x for x in out if x[0] not in ("A", "M", "D", "T") or not x[1]]
    if bad: raise SystemExit(f"guarded-paths: unparseable diff entries {bad!r}: FAIL")
    return out

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

def gh_issue(n):
    """{'state','is_pr','labels'} for #n, or None if the lookup fails."""
    try:
        out = subprocess.run(["gh", "api", f"repos/{{owner}}/{{repo}}/issues/{n}", "--jq",
                              '[.state, (has("pull_request")|tostring), ([.labels[].name]|join(","))]|join(" ")'],
                             capture_output=True, text=True, check=True, timeout=60).stdout.split(" ")
    except Exception:
        return None
    return {"state": out[0].strip(), "is_pr": out[1].strip() == "true", "labels": out[2].strip().split(",") if len(out) > 2 else []}

def implements_ruled(body, lookup):
    """Open, jon-ruled issues the PR carries out (and closes)."""
    b = re.sub(r"<!--.*?-->", "", body or "", flags=re.S)
    b = re.sub(r"^(```|~~~).*?^\1", "", b, flags=re.S | re.M)
    out = []
    for n in re.findall(r"^[ \t]*Implements #(\d+)[ \t]*\.?[ \t]*$", b, flags=re.M):
        if not re.search(rf"\bCloses #{n}\b", b): continue
        i = lookup(n)
        if i and i["state"] == "open" and not i["is_pr"] and "jon-ruled" in i["labels"]: out.append(n)
    return out

def verdict(base, head, labels, cwd=None, body="", lookup=gh_issue):
    if "jon-approved" in labels: return []
    status = diff_status(base, head, cwd)
    changed = [p for _, p in status]
    why = [f"{p}: guarded (needs jon-approved)" for p in changed if any(re.search(r, p) for r in ALWAYS)]
    if "docs/PLAN.md" in changed and plan_guarded(show(base, "docs/PLAN.md", cwd)) != plan_guarded(show(head, "docs/PLAN.md", cwd)):
        why.append("docs/PLAN.md: Exit criteria or Guardrails changed (needs jon-approved)")
    # Convention: expected values live in oracle/baselines/, not in smoke scripts (new ones included).
    for p in changed:
        if re.search(SMOKE, p) and re.search(r"^\s*(export\s+)?EXPECT\w*=", show(head, p, cwd), flags=re.M):
            why.append(f"{p}: baseline value in a smoke script (move it to oracle/baselines/)")
    # Ground truth: patches, and changing or deleting an existing baseline or smoke script (a smoke
    # script decides what its baseline means). Adding a new baseline or smoke script is allowed:
    # the old ones still run, and the PR's own CI has to reproduce the new value.
    ruled = [p for s, p in status
             if re.search(PATCHES, p) or ((re.search(BASELINES, p) or re.search(SMOKE, p)) and s != "A")]
    if ruled and not ruled_ledger(changed, head, cwd) and not implements_ruled(body, lookup):
        why += [f"{p}: needs a ruled, non-escalated ledger entry, or `Implements #N` for an open jon-ruled issue "
                f"(or jon-approved)" for p in ruled]
    return why

def self_test():
    issues = {"7": {"state": "open", "is_pr": False, "labels": ["jon-ruled"]},
              "8": {"state": "open", "is_pr": False, "labels": ["needs-jon"]},
              "5": {"state": "closed", "is_pr": False, "labels": ["jon-ruled"]},
              "9": {"state": "open", "is_pr": True, "labels": ["jon-ruled"]}}
    lookup = issues.get
    led = lambda r, e: {"ledger/0009-x.md": f"- **ruling:** {r}\n- **escalated:** {e}\n"}
    impl = lambda n: f"Carries out the ruling.\n\nImplements #{n}\nCloses #{n}\n"
    B = "oracle/baselines/headless.txt"
    cases = [  # (files to write on the branch (None deletes), PR body, labels, expect_ok)
        ({"Sources/TwinCityCore/X.swift": "x"}, "", [], True),
        ({"CLAUDE.md": "changed"}, "", [], False),
        ({"CLAUDE.md": "changed"}, "", ["jon-approved"], True),
        ({"CLAUDE.md": "changed"}, impl(7), [], False),                     # a ruling never unlocks ALWAYS paths
        ({".github/workflows/ci.yml": "x"}, impl(7), [], False),
        ({"scripts/check-guarded-paths.py": "x"}, "", [], False),
        ({"scripts/ci-extra.sh": "echo more checks"}, "", [], True),       # the agent-owned CI extension point
        # smoke scripts: new ones allowed, existing ones decide what a baseline means (adversary B1)
        ({"oracle/smoke-new.sh": "cmp $(cat baselines/new.txt)", "oracle/baselines/new.txt": "v"}, "", [], True),
        ({"oracle/smoke-headless.sh": "stricter, same baseline"}, "", [], False),
        ({"oracle/smoke-headless.sh": "cmp $(cat baselines/headless-v2.txt)", "oracle/baselines/headless-v2.txt": "2"}, "", [], False),  # e1
        ({"oracle/smoke-headless.sh": 'want="map=... score=322"'}, "", [], False),                                                 # e2
        ({"oracle/smoke-headless.sh": "want=$a; [ $a = $want ]"}, "", [], False),                                                  # e4
        ({"oracle/smoke-new.sh": "export EXPECT=2"}, "", [], False),                                                               # e3
        ({"oracle/smoke-new.sh": "  EXPECT_LAYOUT=x"}, "", [], False),
        ({"oracle/smoke-headless.sh": "stricter"}, impl(7), [], True),
        ({"oracle/smoke-headless.sh": None}, "", [], False),
        ({"oracle/baselines/new.txt": "v"}, "", [], True),                  # new baseline: CI reproduces it
        ({B: "2"}, "", [], False),                                          # moving existing ground truth
        ({B: None}, "", [], False),                                         # deleting it
        ({B: "2", **led("`pending`", "no")}, "", [], False),
        ({B: "2", **led("reproduce: 0", "yes")}, "", [], False),
        ({B: "2", **led("reproduce: 0", "no")}, "", [], True),
        ({B: "2", **led("reproduce: 0", "yes")}, impl(7), [], True),
        ({B: "2"}, impl(8), [], False),                                     # not jon-ruled
        ({B: "2"}, impl(5), [], False),                                     # ruled but closed: key already used (S3)
        ({B: "2"}, impl(9), [], False),                                     # a PR, not an issue (N6)
        ({B: "2"}, "Implements #7\n", [], False),                           # must also close it
        ({B: "2"}, "Closes #7", [], False),                                 # must say Implements
        ({B: "2"}, "<!--\nImplements #7\nCloses #7\n-->", [], False),     # hidden in a comment (S3)
        ({B: "2"}, "```\nImplements #7\n```\nCloses #7", [], False),      # inside a code block
        ({B: "2"}, "Does not implement it (not Implements #7). Closes #7", [], False),  # not a line of its own
        ({"oracle/patches/0009-x.patch": "p"}, "", [], False),
        ({"oracle/patches/0009-x.patch": "p"}, impl(7), [], True),
        # paths git would quote (adversary B2)
        ({"oracle/patches/0004-caf\u00e9.patch": "p"}, "", [], False),
        ({'oracle/patches/0004-"q".patch': "p"}, "", [], False),
        ({".github/workflows/\u00e9.yml": "x"}, "", [], False),
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
                         B: "1", "docs/PLAN.md": "## Now\nold\n\n**Exit:** a\n\n## Guardrails\ng\n"}.items(): w(p, t)
            git("add", "-A", cwd=d); git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base", cwd=d)
            git("checkout", "-qb", "pr", cwd=d)
            for p, t in files.items(): w(p, t)
            git("add", "-A", cwd=d); git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "pr", cwd=d)
            got = not verdict("main", "pr", labels, cwd=d, body=body, lookup=lookup)
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
