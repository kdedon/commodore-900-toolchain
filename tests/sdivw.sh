#!/bin/sh
# sdivw.sh -- a signed int divided by a power of two is a sign test and shifts.
#
# `x / 2^k', k = 1..14, adds 2^k-1 to a negative dividend before the SRA; `x % 2^k'
# is x & 0x8000|m, then -(-v & m) for a negative x.  Values over the edges (INT_MIN,
# INT_MAX, -1, 0, 1, each side of 2^k) and a few others, for every k and every form: a
# return, a parameter, register, global and indexed op-assign, ?:, a condition, and a
# quotient converted to unsigned and long; against C's truncating division.  k = 15 is a
# long divide.  Then shapes: no DIV, and the sizes.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
DIS="$BUILD/tools/loutdis"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

python3 - "$T" <<'EOF'
import sys
T = sys.argv[1]
def td(a, b):
	q = abs(a) // abs(b)
	return q if (a < 0) == (b < 0) else -q
K = range(1, 16)
F = ['d', 'r', 'ad', 'ar', 'gd', 'gr', 'xd', 'xr', 'yd', 'yr', 'q', 'ud', 'ur', 'ld', 'f']
with open(T + '/d.c', 'w') as f:
	f.write('int g, a[4], i = 2;\n')
	for k in K:
		c = 1 << k
		f.write('d%d(x) int x; { return x / %d; }\n' % (k, c))
		f.write('r%d(x) int x; { return x %% %d; }\n' % (k, c))
		f.write('ad%d(x) int x; { x /= %d; return x; }\n' % (k, c))
		f.write('ar%d(x) int x; { x %%= %d; return x; }\n' % (k, c))
		f.write('gd%d(x) int x; { g = x; g /= %d; return g; }\n' % (k, c))
		f.write('gr%d(x) int x; { g = x; g %%= %d; return g; }\n' % (k, c))
		f.write('xd%d(x) int x; { a[i] = x; return a[i] /= %d; }\n' % (k, c))
		f.write('xr%d(x) int x; { a[i] = x; a[i] %%= %d; return a[i]; }\n' % (k, c))
		f.write('yd%d(x) int x; { register int y; y = x; y /= %d; return y; }\n' % (k, c))
		f.write('yr%d(x) int x; { register int y; y = x; return (y %%= %d); }\n' % (k, c))
		f.write('q%d(x, c) int x, c; { return c ? x / %d : x %% %d; }\n' % (k, c, c))
		f.write('unsigned ud%d(x) int x; { return x / %d; }\n' % (k, c))
		f.write('unsigned ur%d(x) int x; { return x %% %d; }\n' % (k, c))
		f.write('long ld%d(x) int x; { return x / %d; }\n' % (k, c))
		f.write('f%d(x) int x; { if (x %% %d) return 1; return 0; }\n' % (k, c))
v = [-32768, -32767, 32767, -3, -2, -1, 0, 1, 2, 3, 12345, -12345, 4097, -4097, 21846, -21846]
for k in K:
	v += [(1 << k) - 1, 1 << k, (1 << k) + 1, -(1 << k) + 1, -(1 << k), -(1 << k) - 1]
v = sorted(set(x for x in v if -32768 <= x < 32768))
with open(T + '/m.c', 'w') as f:
	f.write('extern printf();\n')
	for k in K:
		f.write('extern long ld%d();\nextern unsigned ud%d(), ur%d();\n' % (k, k, k))
	f.write('int v[] = {\n' + ',\n'.join('\t%d' % x for x in v) + '\n};\n')
	f.write('main()\n{\n\tint n;\n\tfor (n = 0; n < sizeof v / sizeof v[0]; n++) {\n')
	for k in K:
		for p in F:
			if p == 'q':
				f.write('\t\tprintf("%%d %%d ", q%d(v[n], 1), q%d(v[n], 0));\n' % (k, k))
			elif p == 'ld':
				f.write('\t\tprintf("%%ld ", ld%d(v[n]));\n' % k)
			elif p[0] == 'u':
				f.write('\t\tprintf("%%u ", %s%d(v[n]));\n' % (p, k))
			else:
				f.write('\t\tprintf("%%d ", %s%d(v[n]));\n' % (p, k))
	f.write('\t\tprintf("\\n");\n\t}\n\treturn 0;\n}\n')
with open(T + '/want', 'w') as f:
	for x in v:
		w = []
		for k in K:
			c = 1 << k
			q, r = td(x, c), x - td(x, c) * c
			w += [q, r] * 4 + [q, r, q, r, q & 0xFFFF, r & 0xFFFF, q, int(r != 0)]
		f.write(' '.join(str(n) for n in w) + ' \n')
EOF
[ -n "$N2" ] || { echo "  sdivw: no guest runner"; exit 2; }
if (cd "$T" && "$CCZ" -o "$T/p" m.c d.c >/dev/null 2>&1); then
	"$N2" -runexec "$T/p" > "$T/got" 2>/dev/null || true
	if cmp -s "$T/got" "$T/want"; then
		echo "  values ($(wc -l < "$T/want") dividends x 15 k x 16 forms) PASS"
	else
		echo "  values FAIL:"; diff "$T/want" "$T/got" | sed 5q | cut -c1-200 | sed 's/^/      /'; fail=1
	fi
else
	echo "  sdivw: compile FAIL"; fail=1
fi

# A pointer difference divides exactly, so it is a bare SRA, also where it is
# scaled back or converted; a char difference divided by the program is not.
cat > "$T/pd.c" <<'EOF'
extern printf();
short h[8]; long l[8]; struct { long a, b; } q[8]; struct { char c[6]; } s6[8]; char c[8];
unsigned u;
ph(i, j) { return &h[i] - &h[j]; }
pl(i, j) { return &l[i] - &l[j]; }
pq(i, j) { return &q[i] - &q[j]; }
ps(i, j) { return &s6[i] - &s6[j]; }
pu(i, j) { u = &l[i] - &l[j]; return u; }
pz(i, j) { u = (&l[i] - &l[j]) * sizeof l[0]; return u; }
long pg(i, j) { return &q[i] - &q[j]; }
pc(i, j) { return (&c[i] - &c[j]) / 4; }
main()
{
	int i, j;
	for (i = 0; i < 8; i++)
		for (j = 0; j < 8; j++)
			printf("%d %d %d %d %u %u %ld %d\n", ph(i, j), pl(i, j), pq(i, j),
			    ps(i, j), pu(i, j), pz(i, j), pg(i, j), pc(i, j));
	return 0;
}
EOF
python3 -c '
import sys
for i in range(8):
	for j in range(8):
		d = i - j
		print("%d %d %d %d %d %d %d %d" % (d, d, d, d, d & 0xFFFF, (4 * d) & 0xFFFF, d, int(d / 4)))
' > "$T/pdwant"
if (cd "$T" && "$CCZ" -o "$T/pd" pd.c >/dev/null 2>&1); then
	"$N2" -runexec "$T/pd" > "$T/pdgot" 2>/dev/null || true
	if cmp -s "$T/pdgot" "$T/pdwant"; then
		echo "  pointer differences (64 pairs x 8 forms) PASS"
	else
		echo "  pointer differences FAIL:"; diff "$T/pdwant" "$T/pdgot" | sed 5q | sed 's/^/      /'; fail=1
	fi
else
	echo "  sdivw: pointer differences compile FAIL"; fail=1
fi
(cd "$T" && "$CCZ" -c -o "$T/pd.o" pd.c >/dev/null 2>&1) || true
for f in ph_ pl_ pq_ pu_ pz_; do
	d=$("$DIS" -v -fn $f "$T/pd.o" 2>/dev/null) || true
	if printf '%s\n' "$d" | grep -q ' SRA ' && ! printf '%s\n' "$d" | grep -qE ' (TEST|DIV) '; then
		echo "  $f bare SRA PASS"
	else
		echo "  $f FAIL: not a bare SRA"; printf '%s\n' "$d" | sed 's/^/      /'; fail=1
	fi
done

cat > "$T/s.c" <<'EOF'
int g, a[4];
d8(x) int x; { return x / 8; }
r8(x) int x; { return x % 8; }
d2(x) int x; { return x / 2; }
r2(x) int x; { return x % 2; }
dk(x) int x; { return x / 1024; }
rk(x) int x; { return x % 1024; }
gd() { g /= 16; }
xr(i) int i; { a[i] %= 4; }
EOF
(cd "$T" && "$CCZ" -c -o "$T/s.o" s.c >/dev/null 2>&1) || { echo "  sdivw: shapes compile FAIL"; exit 1; }
shape() { # <fn> <bytes> <what>
	d=$("$DIS" -v -fn "$1" "$T/s.o" 2>/dev/null) || true
	nd=$(printf '%s\n' "$d" | grep -c ' DIV ' || true)
	nb=$(printf '%s\n' "$d" | sed -n '1s/.*(\([0-9]*\) bytes).*/\1/p')
	if [ "$nd.$nb" = "0.$2" ]; then
		printf '  %-4s 0 DIV, %s bytes PASS  (%s)\n' "$1" $2 "$3"
	else
		printf '  %-4s FAIL: %s DIV, %s bytes; want 0, %s (%s)\n' "$1" "$nd" "$nb" $2 "$3"
		printf '%s\n' "$d" | sed 's/^/      /'; fail=1
	fi
}
shape d8_ 16 "TEST JR INC SRA; 12 with the DIV"
shape r8_ 20 "AND JR NEG AND NEG; 14"
shape d2_ 12 "EXTS SUB RRC; 12"
shape r2_ 20 "AND #1; 14"
shape dk_ 18 "ADD #1023; 12"
shape rk_ 20 "AND #1023; 14"
shape gd_ 24 "global op-assign; 20"
shape xr_ 58 "indexed op-assign, the index twice; 42"

[ "$fail" = 0 ] || { echo "=== sdivw: FAIL ==="; exit 1; }
echo "=== sdivw: PASS ==="
