#!/usr/bin/env python3
"""Summarise UB detector logs (run-detect.sh) as one line per site, sorted:

  <src-relative file:line>  <detector>  <kind>  sessions=<s1,s2,...>

detector is asan, ubsan or rowcheck (an ASan ABRT is a -ftrapv trap, at its first sim frame). kind is the sanitizer's error class, or for UBSan its
message with numbers replaced by N, so the line is stable across sessions.
  report.py LOGDIR      reads LOGDIR/<session>.log
"""
import re, sys, pathlib, collections

SRC = re.compile(r"(?:^|/)tree/src/(\S+?):(\d+)")
def rel(path_line):
    m = SRC.search(path_line)
    return f"{m.group(1)}:{m.group(2)}" if m else None

def sites(text):
    """Every detector line becomes a site: UBSan `runtime error:` lines, `rowcheck:` lines, ASan
    and UBSan `ERROR:` reports, and any other line naming a sanitizer (except SUMMARY lines,
    which repeat an ERROR). A line it can't attribute becomes site `?` (and makes report.py
    exit 1), so a format it doesn't know fails closed instead of vanishing."""
    out = set(); lines = text.splitlines()
    for i, l in enumerate(lines):
        if "runtime error:" in l:
            m = re.match(r"(.*?):(\d+)(?::\d+)?: runtime error: (.*)", l)
            msg = m.group(3) if m else l.split("runtime error:", 1)[1].strip()
            kind = re.sub(r"-?\b(0x[0-9a-f]+|\d+(\.\d+)?(e[+-]?\d+)?)\b", "N", msg)
            out.add(((rel(f"{m.group(1)}:{m.group(2)}") if m else None) or "?", "ubsan", kind)); continue
        if l.startswith("rowcheck:"):
            m = re.match(r"rowcheck: (\w+)\[-?\d+\]\[-?\d+\] at (\S+:\d+)", l)
            out.add(((rel(m.group(2)) if m else None) or "?", "rowcheck",
                     f"{m.group(1) if m else '?'} subscript out of range")); continue
        m = re.search(r"ERROR: (Address|UndefinedBehavior)Sanitizer: (\S+)", l)
        if m:
            site = None
            for f in lines[i+1:i+60]:
                fm = re.match(r"\s+#\d+ 0x[0-9a-f]+ in \S+ (\S+)", f)
                if fm and rel(fm.group(1)): site = rel(fm.group(1)); break
            out.add((site or "?", "asan" if m.group(1) == "Address" else "ubsan", m.group(2))); continue
        # Anything else a sanitizer says (WARNING, CHECK failed, a lone DEADLYSIGNAL, ...) is a
        # finding report.py can't attribute. SUMMARY lines only repeat an error parsed above.
        if "Sanitizer" in l and "SUMMARY:" not in l and not l.startswith("rowcheck"):
            if l.strip().endswith("Sanitizer:DEADLYSIGNAL") and any("ERROR: AddressSanitizer: " in x for x in lines[i+1:i+3]):
                continue
            out.add(("?", "sanitizer", re.sub(r"0x[0-9a-f]+|\d+", "N", l.strip())[:120]))
    return out

if __name__ == "__main__":
    seen = collections.defaultdict(list)
    for p in sorted(pathlib.Path(sys.argv[1]).glob("*.log")):
        for s in sites(p.read_text(errors="replace")): seen[s].append(p.stem)
    key = lambda s: (s[0].rsplit(":", 1)[0], int(s[0].rsplit(":", 1)[1]) if s[0] != "?" else 0, s[1], s[2])
    for s in sorted(seen, key=key):
        print(f"{s[0]}  {s[1]}  {s[2]}  sessions={','.join(seen[s])}")
    sys.exit(1 if any(s[0] == "?" for s in seen) else 0)
