#!/bin/sh
# sdiv2.sh -- a signed long divided by a power of two is shifts, exactly.
#
# `l / 2' and `l /= 2' round toward zero: EXTSL leaves 0 or -1 in RR0, SUBL adds 1
# to a negative dividend, and SRAL halves it, in the 8 bytes of the EXTSL and DIVL
# they replace.  `l / 2^k', k = 2..30, tests the high word's sign and adds 2^k-1 to
# a negative dividend only before the SRAL; `l % 2^k', k = 1..16, is the low word &
# m for a non-negative dividend and -(-x & m), its high word from SBC, for a negative
# one.  Both are some 700 clocks faster than the DIVL and a few bytes longer.  Values over the edges (LONG_MIN, LONG_MAX, -1, 0, 1, each side of each
# power) and a sweep, for every k, against C's truncating division; shapes.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
DIS="$BUILD/tools/loutdis"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

# One divide and one remainder function a power, compound forms, and a register.
python3 - "$T" <<'EOF'
import sys
T = sys.argv[1]
def td(a, b):
	q = abs(a) // abs(b)
	return q if (a < 0) == (b < 0) else -q
K = range(1, 31)
R = range(1, 17)
with open(T + '/d.c', 'w') as f:
	for k in K:
		f.write('long d%d(x) long x; { return x / %dL; }\n' % (k, 1 << k))
	for k in R:
		f.write('long r%d(x) long x; { return x %% %dL; }\n' % (k, 1 << k))
	f.write('long a4(x) long x; { x /= 4; return x; }\n')
	f.write('long m16(p) long *p; { *p %= 16; return *p; }\n')
	f.write('long g(x) long x; { register long y; y = x; y /= 2; return y + x % 8; }\n')
v = [-2**31, -2**31 + 1, 2**31 - 1, 2**31 - 2, -1, 0, 1]
for k in range(1, 31):
	v += [(1 << k) - 1, 1 << k, (1 << k) + 1, -(1 << k) + 1, -(1 << k), -(1 << k) - 1]
v = [x for x in v if -2**31 <= x < 2**31]
x = -1000003
for i in range(60):
	v.append(x); x = x * 7 // 3 + 12345 if abs(x) < 2**29 else -x // 5
with open(T + '/m.c', 'w') as f:
	f.write('extern printf();\n')
	f.write(''.join('extern long d%d(), r%d();\n' % (k, k) for k in K))
	f.write('extern long a4(), m16(), g();\nlong v[] = {\n')
	f.write(',\n'.join('\t%dL' % x if x != -2**31 else '\t0x80000000L' for x in v) + '\n};\n')
	f.write('main()\n{\n\tint i; long t;\n\tfor (i = 0; i < sizeof v / sizeof v[0]; i++) {\n')
	for k in K:
		f.write('\t\tprintf("%%ld ", d%d(v[i]));\n' % k)
	for k in R:
		f.write('\t\tprintf("%%ld ", r%d(v[i]));\n' % k)
	f.write('\t\tt = v[i];\n\t\tprintf("%ld %ld %ld\\n", a4(v[i]), m16(&t), g(v[i]));\n\t}\n\treturn 0;\n}\n')
with open(T + '/want', 'w') as f:
	for x in v:
		f.write(' '.join(str(td(x, 1 << k)) for k in K) + ' ')
		f.write(' '.join(str(x - td(x, 1 << k) * (1 << k)) for k in R) + ' ')
		f.write('%d %d %d\n' % (td(x, 4), x - td(x, 16) * 16, td(x, 2) + x - td(x, 8) * 8))
EOF
[ -n "$N2" ] || { echo "  sdiv2: no guest runner"; exit 2; }
if (cd "$T" && "$CCZ" -o "$T/p" m.c d.c >/dev/null 2>&1); then
	"$N2" -runexec "$T/p" > "$T/got" 2>/dev/null || true
	if cmp -s "$T/got" "$T/want"; then
		echo "  values ($(wc -l < "$T/want") dividends x 49 forms) PASS"
	else
		echo "  values FAIL:"; diff "$T/want" "$T/got" | sed 5q | sed 's/^/      /'; fail=1
	fi
else
	echo "  sdiv2: compile FAIL"; fail=1
fi

# Shapes: the directory-size forms of the COHERENT tools (dcheck, dump, ls, mkfs,
# tar, unmkfs: `size / sizeof(struct direct)', `size % ...'), with the sizes.
cat > "$T/s.c" <<'EOF'
struct direct { unsigned short d_ino; char d_name[14]; };
long size;
long d2(x) long x; { return x / 2; }
long a2(x) long x; { x /= 2; return x; }
long nd() { return size / sizeof(struct direct); }
odd() { return (size % sizeof(struct direct)) != 0; }
trim() { size -= size % sizeof(struct direct); }
long d1k(x) long x; { return x / 1024; }
long r16k(x) long x; { return x % 65536L; }
EOF
(cd "$T" && "$CCZ" -c -o "$T/s.o" s.c >/dev/null 2>&1) || { echo "  sdiv2: shapes compile FAIL"; exit 1; }
shape() { # <fn> <DIVL count> <bytes> <what>
	d=$("$DIS" -v -fn "$1" "$T/s.o" 2>/dev/null) || true
	nd=$(printf '%s\n' "$d" | grep -c ' DIVL ' || true)
	nb=$(printf '%s\n' "$d" | sed -n '1s/.*(\([0-9]*\) bytes).*/\1/p')
	if [ "$nd.$nb" = "$2.$3" ]; then
		printf '  %-5s %s DIVL, %s bytes PASS  (%s)\n' "$1" $2 $3 "$4"
	else
		printf '  %-5s FAIL: %s DIVL, %s bytes; want %s, %s (%s)\n' "$1" "$nd" "$nb" $2 $3 "$4"
		printf '%s\n' "$d" | sed 's/^/      /'; fail=1
	fi
}
shape d2_ 0 16 "EXTSL SUBL SRAL; 16 bytes with the DIVL"
shape a2_ 0 22 "the same, compound; 22"
shape nd_ 0 24 "TEST JR ADDL SRAL; 18"
shape odd_ 0 40 "TEST JR AND CLR JR | NEG AND NEG SBC; 26"
shape trim_ 0 44 "the same, subtracted; 46"
shape d1k_ 0 22 "k = 10; 16"
shape r16k_ 0 30 "k = 16, the remainder's high word from SBC; 14"

[ "$fail" = 0 ] || { echo "=== sdiv2: FAIL ==="; exit 1; }
echo "=== sdiv2: PASS ==="
