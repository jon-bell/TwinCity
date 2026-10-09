#!/usr/bin/env python3
"""Instrumentation-only source rewrite for the UB detector build (oracle/build-detect.sh).

The sim's 2-D maps are arrays of row pointers into one contiguous block (s_alloc.c:150), so
`Map[x][100]` silently reads `Map[x+1][0]` and ASan can't see it (docs/DESIGN.md, UB table).
This rewrites every two-subscript use `A[i][j]` of those arrays into `TC_AT(A, X, Y, i, j)`,
in place, keeping every newline so `file:line` stays the upstream line. headers/sim.h gains
the TC_AT definitions at its end (again no line shift in any .c file):

  compiled out (no -DTC_DETECT):  TC_AT(A,X,Y,i,j)  ->  A[i][j]          (the original tokens)
  -DTC_DETECT:                    bounds-check i in [0,X) and j in [0,Y), record the site,
                                  then do the original access anyway (oracle/detect/rowcheck.c)

  row-accessor.py SRC_SIM_DIR FILE...     rewrite FILE.c in place; print a summary
Exits 1 if any use can't be rewritten (one subscript outside s_alloc.c, or a top-level comma).
"""
import re, sys, pathlib

ROWS = {"Map": ("WORLD_X", "WORLD_Y")}
ROWS.update({a: ("HWLDX", "HWLDY") for a in
             ["PopDensity", "TrfDensity", "PollutionMem", "LandValueMem", "CrimeMem", "tem", "tem2"]})
ROWS.update({a: ("QWX", "QWY") for a in ["TerrainMem", "Qtem"]})
NAME = re.compile(r"[A-Za-z_]\w*")

def bracket(s, i):
    """s[i] == '['; return index just past the matching ']' (comments/strings inside are rare
    in subscripts and are not expected; a stray one raises)."""
    depth = 0
    for k in range(i, len(s)):
        c = s[k]
        if c in "\"'/": 
            if c == "/" and s[k+1:k+2] not in ("*", "/"): continue
            raise ValueError("comment or literal inside a subscript")
        if c == "[": depth += 1
        elif c == "]":
            depth -= 1
            if depth == 0: return k + 1
    raise ValueError("unbalanced [")

def top_comma(e):
    d = 0
    for c in e:
        if c in "([": d += 1
        elif c in ")]": d -= 1
        elif c == "," and d == 0: return True
    return False

def tail(out):
    """The last two non-blank characters emitted so far (to skip `x.Map` and `x->Map`)."""
    acc = ""
    for piece in reversed(out):
        acc = piece.rstrip() + acc if not acc else piece + acc
        if len(acc.rstrip()) >= 2: break
    return acc.rstrip()[-2:]

def rewrite(s, fname, report):
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if s.startswith("/*", i):
            j = s.index("*/", i + 2) + 2; out.append(s[i:j]); i = j; continue
        if s.startswith("//", i):
            j = s.find("\n", i); j = n if j < 0 else j; out.append(s[i:j]); i = j; continue
        if c in "\"'":
            j = i + 1
            while s[j] != c: j += 2 if s[j] == "\\" else 1
            out.append(s[i:j+1]); i = j + 1; continue
        m = NAME.match(s, i)
        if not m:
            out.append(c); i += 1; continue
        w, j = m.group(), m.end()
        prev = tail(out)
        if w not in ROWS or prev.endswith(".") or prev == "->":
            out.append(w); i = j; continue
        line = s.count("\n", 0, i) + 1
        k = j
        while k < n and s[k] in " \t": k += 1
        if k >= n or s[k] != "[":
            out.append(w); i = j; continue
        e1 = bracket(s, k)
        k2 = e1
        while k2 < n and s[k2] in " \t": k2 += 1
        if k2 >= n or s[k2] != "[":
            report["single"].append(f"{fname}:{line}: {s[i:e1]}")
            out.append(w); i = j; continue
        e2 = bracket(s, k2)
        a, b = s[k+1:e1-1], s[k2+1:e2-1]
        if top_comma(a) or top_comma(b):
            report["bad"].append(f"{fname}:{line}: top-level comma in {s[i:e2]}"); out.append(w); i = j; continue
        X, Y = ROWS[w]
        out.append(f"TC_AT({w},{X},{Y},{rewrite(a, fname, report)},{rewrite(b, fname, report)})")
        report["n"] += 1
        i = e2
    return "".join(out)

HEADER = r"""
/* TwinCity UB detector (oracle/detect/row-accessor.py): bounds-checked row-pointer arrays. */
#ifdef TC_DETECT
void tc_rowcheck(const char *arr, long x, long y, long X, long Y, const char *file, int line);
#define TC_AT(A, X, Y, a, b) (*({ long tc_a_ = (a), tc_b_ = (b); \
    tc_rowcheck(#A, tc_a_, tc_b_, (X), (Y), __FILE__, __LINE__); &A[tc_a_][tc_b_]; }))
#else
#define TC_AT(A, X, Y, a, b) A[a][b]
#endif
"""

if __name__ == "__main__":
    d = pathlib.Path(sys.argv[1]); report = {"n": 0, "single": [], "bad": []}
    per = []
    for f in sys.argv[2:]:
        p = d / f"{f}.c"; t = p.read_text(encoding="latin-1"); before = report["n"]
        r = rewrite(t, p.name, report)
        assert r.count("\n") == t.count("\n"), f"{p.name}: line count moved"
        p.write_text(r, encoding="latin-1"); per.append(f"{f}={report['n']-before}")
    h = d / "headers/sim.h"; h.write_text(h.read_text(encoding="latin-1") + HEADER, encoding="latin-1")
    single = [x for x in report["single"] if not x.startswith("s_alloc.c:")]
    print(f"row-accessor: {report['n']} uses rewritten ({' '.join(x for x in per if not x.endswith('=0'))})")
    for x in report["single"]: print(f"row-accessor: one subscript, unchecked: {x}")
    for x in report["bad"] + single: print(f"row-accessor: FAIL cannot rewrite: {x}")
    sys.exit(1 if report["bad"] or single else 0)
