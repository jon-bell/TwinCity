#!/bin/sh
# code-of.sh OBJ: what an object file does, minus line info. Used by run-detect.sh to prove the
# compiled-out rewrite inert. Prints the disassembly with text relocations, every relocation in
# every non-debug section (offset, type, symbol+addend), and the bytes of every non-debug
# section that holds data. Sections are listed with readelf, which (unlike objdump -h) also
# lists relocation sections. --self-test: two objects that differ only in a pointer table's
# relocations must differ, and the same object must equal itself.
set -eu
if [ "${1:-}" = --self-test ]; then
  T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
  printf 'int a, b; int *const p[] = { &a, &b }; int f(int i) { return *p[i]; }\n' > "$T/x1.c"
  printf 'int a, b; int *const p[] = { &b, &a }; int f(int i) { return *p[i]; }\n' > "$T/x2.c"
  printf 'int a, b; int *p[] = { &a, &b }; int f(int i) { return *p[i]; }\n' > "$T/y1.c"
  printf 'int a, b; int *p[] = { &b, &a }; int f(int i) { return *p[i]; }\n' > "$T/y2.c"
  for f in x1 x2 y1 y2; do gcc -c -O0 -fPIC "$T/$f.c" -o "$T/$f.o"; done
  me="$0"; fail=0
  for p in x y; do
    [ "$("$me" "$T/${p}1.o" | md5sum)" != "$("$me" "$T/${p}2.o" | md5sum)" ] || { echo "code-of self-test: FAIL ${p}: swapped pointer table not seen"; fail=1; }
    [ "$("$me" "$T/${p}1.o" | md5sum)" = "$("$me" "$T/${p}1.o" | md5sum)" ] || { echo "code-of self-test: FAIL ${p}: not deterministic"; fail=1; }
  done
  [ $fail = 0 ] && echo "code-of self-test: ok (pointer-table relocations in .data.rel.ro and .data.rel are compared)"
  exit $fail
fi
o="$1"
objdump -dr "$o" | tail -n +4
readelf -rW "$o" | awk '/^Relocation section/ { s = $3; skip = (s ~ /debug/ || s ~ /^.\.rela\.text/); next }
  !skip && NF >= 5 && $1 ~ /^[0-9a-f]+$/ { $2 = ""; $4 = ""; print s, $0 }'
for s in $(readelf -SW "$o" | sed -n 's/^ *\[ *[0-9]*\] \([^ ]*\) .*/\1/p'); do
  case $s in .text*|.rela*|.debug*|.comment|.note*|.group|.symtab|.strtab|.shstrtab|.bss*) ;;
    *) objdump -s -j "$s" "$o" | tail -n +4 ;; esac
done
