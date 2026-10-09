#!/usr/bin/env python3
"""Summarise UB detector logs (run-detect.sh) as one line per site, sorted:

  <src-relative file:line>  <detector>  <kind>  sessions=<s1,s2,...>

detector is asan, ubsan or rowcheck. kind is the sanitizer's error class, or for UBSan its
message with numbers replaced by N, so the line is stable across sessions.
  report.py LOGDIR      reads LOGDIR/<session>.log
"""
import re, sys, pathlib, collections

SRC = re.compile(r"(?:^|/)tree/src/(\S+?):(\d+)")
def rel(path_line):
    m = SRC.search(path_line)
    return f"{m.group(1)}:{m.group(2)}" if m else None

def sites(text):
    out = set(); lines = text.splitlines()
    for i, l in enumerate(lines):
        m = re.match(r"(\S+?):(\d+):\d+: runtime error: (.*)", l)
        if m:
            kind = re.sub(r"-?\b(0x[0-9a-f]+|\d+(\.\d+)?(e[+-]?\d+)?)\b", "N", m.group(3))
            out.add((rel(f"{m.group(1)}:{m.group(2)}") or m.group(1) + ":" + m.group(2), "ubsan", kind)); continue
        m = re.match(r"rowcheck: (\w+)\[-?\d+\]\[-?\d+\] at (\S+:\d+)", l)
        if m:
            out.add((rel(m.group(2)) or m.group(2), "rowcheck", f"{m.group(1)} subscript out of range")); continue
        m = re.search(r"ERROR: AddressSanitizer: (\S+)", l)
        if m:
            site = None
            for f in lines[i+1:i+60]:
                fm = re.match(r"\s+#\d+ 0x[0-9a-f]+ in \S+ (\S+)", f)
                if fm and rel(fm.group(1)): site = rel(fm.group(1)); break
            out.add((site or "?", "asan", m.group(1)))
    return out

if __name__ == "__main__":
    seen = collections.defaultdict(list)
    for p in sorted(pathlib.Path(sys.argv[1]).glob("*.log")):
        for s in sites(p.read_text(errors="replace")): seen[s].append(p.stem)
    key = lambda s: (s[0].rsplit(":", 1)[0], int(s[0].rsplit(":", 1)[1]) if s[0] != "?" else 0, s[1], s[2])
    for s in sorted(seen, key=key):
        print(f"{s[0]}  {s[1]}  {s[2]}  sessions={','.join(seen[s])}")
