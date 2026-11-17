#!/bin/sh
# relax.sh -- ld shortens the text of an LF_RELAX object.
#
# A data operand below offset 256 of its segment takes the one-word short
# form; one above keeps the long form.  A CALL whose target is in its segment
# and in reach becomes CALR, forward or into another object; one out of reach
# stays CALL.  Symbols, branches, compiler CALRs and function pointers across
# the cuts still land, beside an object in the old format (no LF_RELAX, LR_LONG
# only) and one from the assembler.  `ld -r' writes only the old records.

set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"; CC1="$BUILD/z8001/cc1-z8001"
CC2="$BUILD/z8001/cc2-z8001"; AS="$BUILD/as-z8001"; LD="$BUILD/ld-z8001"
N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
ok()  { printf '  %-46s PASS\n' "$1"; }
bad() { printf '  %-46s FAIL %s\n' "$1" "$2"; fail=1; }

# Linked -i, the data starts its own segment: b.o's table, then lo_ at 8 and
# hi_ at 410.  c.o puts ~8 KB of filler before distant_.
cat > "$T/a.c" <<'EOF'
extern int bnear(), oldf(), distant(), (*tab[])();
int lo;
int pad[200];
int hi;
int (*fp)();
setlo() { lo = 7; }
sethi() { hi = 9; }
near1(x) { return x + 1; }
fwd(x) { return near2(x) + 1; }
near2(x) { return x * 2; }
back(x) { lo = lo + 1; return near1(x) + lo; }
xcall(x) { return bnear(x) + 2; }
loop(n) { int i, s; s = 0; for (i = 0; i < n; i++) { if (i & 1) s += lo; else s += hi; } return s; }
farcall(x) { return distant(x); }
sw(x)
{
	switch (x) {
	case 0: return lo;
	case 1: return hi;
	case 2: return near1(x);
	case 3: return lo + hi;
	case 4: return fwd(x);
	case 5: return 5;
	case 6: return lo * 3;
	case 7: return 7;
	}
	return -1;
}
f(a, b)
{
	int s, i;
	setlo(); sethi();
	s = 0;
	for (i = -1; i < 9; i++)
		s += sw(i) * (i + 2);
	fp = bnear;
	s += fwd(a);
	s += back(b);
	s += xcall(a);
	s += loop(5);
	s += farcall(b);
	s += (*fp)(b);
	s += (*tab[0])(a);
	s += (*tab[1])(b);
	s += oldf(a);
	return s + lo + hi;
}
EOF
cat > "$T/b.c" <<'EOF'
extern int near1(), near2();
bnear(x) { return near1(x) * 3; }
bnext(x) { return x; }
int (*tab[2])() = { near2, bnear };
EOF
cat > "$T/old.c" <<'EOF'
extern int near1(), fwd(), hi;
oldf(x) { if (x > 1) return near1(x) + fwd(x) + hi; return 0; }
EOF
{
	echo "filler(a) {"
	i=0
	while [ $i -lt 1500 ]; do echo "	a = a ^ $i;"; i=$((i+1)); done
	echo "	return a;"
	echo "}"
	echo "distant(x) { return x - 3; }"
} > "$T/c.c"
printf '\t.globl\tSS\nSS = 0\n' > "$T/ss.s"
"$AS" -o "$T/ss.o" "$T/ss.s"
for s in a b old c; do
	"$CC0" $VAR "$T/$s.c" "$T/$s.z0" && "$CC1" $VAR "$T/$s.z0" "$T/$s.z1" &&
	"$CC2" 0012 "$T/$s.z1" "$T/$s.o" "$T/$s.scr" 0 ||
		{ echo "  relax: compile FAIL"; exit 1; }
done

# old.o as the previous compiler wrote it: no LF_RELAX, each record LR_LONG on
# an address, no branch records.
python3 - "$T/old.o" <<'PY'
import sys
p = sys.argv[1]; b = bytearray(open(p, 'rb').read())
pdp = lambda o: (b[o] | b[o+1] << 8) << 16 | (b[o+2] | b[o+3] << 8)
tb = b[6] | b[7] << 8; ss = [pdp(8 + 4*i) for i in range(9)]
rel = tb + ss[0] + ss[1] + ss[3] + ss[4] + ss[6] + ss[7]
out = bytearray(); q = rel
while q < rel + ss[8]:
	op = b[q]; addr = pdp(q + 1); n = 7 if op & 0o17 == 7 else 5
	rec = bytearray(b[q:q+n]); q += n
	kind = op & 0o340
	if kind == 0o300:
		continue
	if kind in (0o200, 0o240):
		if kind == 0o240:
			addr += 2
		rec[0] = op & 0o37 | 0o100
		rec[1:5] = bytes([addr >> 16 & 0xFF, addr >> 24 & 0xFF, addr & 0xFF, addr >> 8 & 0xFF])
	out += rec
flag = b[2] | b[3] << 8
assert flag & 0o1000, "cc2 did not mark old.c LF_RELAX"
flag &= ~0o1000; b[2] = flag & 0xFF; b[3] = flag >> 8
n = len(out); b[40:44] = bytes([n >> 16 & 0xFF, n >> 24 & 0xFF, n & 0xFF, n >> 8 & 0xFF])
open(p, 'wb').write(b[:rel] + out)
PY

"$LD" -i -R 0x200 -e f_ -o "$T/out" "$T/a.o" "$T/b.o" "$T/old.o" "$T/c.o" "$T/ss.o" ||
	{ echo "  relax: link FAIL"; exit 1; }

# Each function's size in its object less its size linked: the bytes cut.
cuts=$(python3 - "$T/out" "$T/a.o" "$T/b.o" <<'PY'
import sys
def syms(p):
	b = open(p, 'rb').read()
	pdp = lambda o: (b[o] | b[o+1] << 8) << 16 | (b[o+2] | b[o+3] << 8)
	tb = b[6] | b[7] << 8; ss = [pdp(8 + 4*i) for i in range(9)]
	o = tb + ss[0] + ss[1] + ss[3] + ss[4] + ss[6]
	t = {}
	for i in range(ss[7] // 22):
		e = b[o + 22*i:o + 22*i + 22]
		if (e[16] | e[17] << 8) & 0o17 == 0:
			t[e[:16].rstrip(b'\0').decode()] = pdp(o + 22*i + 18)
	return t
lt = syms(sys.argv[1])
out = []
for obj in sys.argv[2:]:
	ot = syms(obj)
	names = sorted(ot, key=ot.get)
	for n, m in zip(names, names[1:]):
		out.append("%s=%d" % (n, (ot[m] - ot[n]) - (lt[m] - lt[n])))
print(" ".join(out))
PY
)
want() { # <what> <fn> <cut>
	got=$(echo "$cuts" | tr ' ' '\n' | sed -n "s/^$2=//p")
	if [ "$got" = "$3" ]; then ok "$1"; else bad "$1" "cut=[$got] want $3"; fi
}
want "data at offset 8: short"			setlo_ 2
want "data at offset 410: long"			sethi_ 0
want "short operand inside a loop"		loop_ 2
want "forward CALL in reach: CALR"		fwd_ 4
want "CALL into the next object: CALR"		xcall_ 4
want "CALL back into the previous object: CALR"	bnear_ 4
want "CALL out of reach: CALL"			farcall_ 0

# The same program on the host.
cat > "$T/hm.c" <<'EOF'
#include <stdio.h>
int f();
int main() { printf("%d\n", f(3, 4)); return 0; }
EOF
want=$(gcc -std=gnu89 -w -o "$T/h" "$T/hm.c" "$T/a.c" "$T/b.c" "$T/old.c" "$T/c.c" && "$T/h" | tr -d '\r')
run() { "$N2" -runobjint "$1" 3 4 2>/dev/null | grep -oE 'signed -?[0-9]+' | grep -oE '\-?[0-9]+' || true; }
got=$(run "$T/out")
[ "$got" = "$want" ] && ok "values across the cuts ($got)" ||
	bad "values across the cuts" "got=[$got] want=[$want]"

# ld -r keeps only the records every reader knows, and clears LF_RELAX.
"$LD" -r -R 0 -o "$T/part.o" "$T/a.o" "$T/b.o"
r=$(python3 - "$T/part.o" <<'PY'
import sys
b = open(sys.argv[1], 'rb').read()
pdp = lambda o: (b[o] | b[o+1] << 8) << 16 | (b[o+2] | b[o+3] << 8)
tb = b[6] | b[7] << 8; ss = [pdp(8 + 4*i) for i in range(9)]
p = tb + ss[0] + ss[1] + ss[3] + ss[4] + ss[6] + ss[7]; end = p + ss[8]; kinds = set()
while p < end:
	op = b[p]; kinds.add(op & 0o340); p += 7 if op & 0o17 == 7 else 5
flag = b[2] | b[3] << 8
print("ok" if not flag & 0o1000 and kinds <= {0, 0o40, 0o100} and p == end
      else "flag %o kinds %s" % (flag, sorted(kinds)))
PY
)
"$LD" -i -R 0x200 -e f_ -o "$T/out2" "$T/part.o" "$T/old.o" "$T/c.o" "$T/ss.o"
got=$(run "$T/out2")
[ "$r" = ok ] && [ "$got" = "$want" ] && ok "ld -r writes the old format" ||
	bad "ld -r writes the old format" "$r got=[$got]"

[ "$fail" = 0 ] || { echo "=== relax: FAIL ==="; exit 1; }
echo "=== relax: PASS ==="
