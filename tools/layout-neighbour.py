#!/usr/bin/env python3
"""Which object does an out-of-bounds element land in?

    tools/layout-neighbour.py BINARY SYMBOL INDEX ELEMSIZE [SYMBOL INDEX ELEMSIZE ...]

For each triple, computes &SYMBOL[INDEX] from `nm -n -S BINARY` and prints the symbol
whose [addr, addr+size) contains it, with the offset into that symbol, or `padding` if no
sized symbol covers the address. Used for layout-perturbation tables in ledger/.
"""
import subprocess
import sys


def symbols(binary):
    out = subprocess.run(["nm", "-n", "-S", binary], check=True, capture_output=True, text=True).stdout
    syms = []
    for line in out.splitlines():
        f = line.split()
        if len(f) == 4 and f[2] in "bBdDCgGsS":
            syms.append((int(f[0], 16), int(f[1], 16), f[3]))
    return syms


def neighbour(syms, symbol, index, elemsize):
    base = [s for s in syms if s[2] == symbol]
    if len(base) != 1:
        raise SystemExit(f"{symbol}: expected one sized data symbol, found {len(base)}")
    addr = base[0][0] + index * elemsize
    for a, size, name in syms:
        if a <= addr < a + size:
            return f"{symbol}[{index}] -> {name}+{addr - a} (0x{addr:x})"
    return f"{symbol}[{index}] -> padding (0x{addr:x})"


def main(argv):
    if len(argv) < 5 or (len(argv) - 2) % 3:
        raise SystemExit(__doc__)
    syms = symbols(argv[1])
    for i in range(2, len(argv), 3):
        print(neighbour(syms, argv[i], int(argv[i + 1]), int(argv[i + 2])))


if __name__ == "__main__":
    main(sys.argv)
