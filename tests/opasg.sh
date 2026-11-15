#!/bin/sh
# opasg.sh -- `x /= y' and `x %= y' divide in the type x and y balance to.
#
# C89 3.3.16.2: `x op= y' is `x = x op y' with x evaluated once, so the
# usual arithmetic conversions pick the divide: `i /= u' is
# `i = (int)((unsigned)i / u)', and -3 /= 2u stores 32766.  The cases pair
# each integer type on the left with right operands that balance to another
# type, a long right operand over a word or byte (`30000 /= 70000L' stores
# 0), and some that do not, for `/=' and `%=', with the left operand a
# global, a local, a register, `*p' and `*p++'.  The stored value, the value
# of the expression, and where p ends are compared with a model of C89 with a
# 16-bit int and a 32-bit long.  Shapes: a balanced pair compiles as before.
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
W = {'c': 8, 'uc': 8, 's': 16, 'us': 16, 'i': 16, 'u': 16, 'l': 32, 'ul': 32}
U = {'uc', 'us', 'u', 'ul'}
D = {'c': 'char', 'uc': 'unsigned char', 's': 'short', 'us': 'unsigned short',
	'i': 'int', 'u': 'unsigned', 'l': 'long', 'ul': 'unsigned long'}
def wrap(t, v):
	m = 1 << W[t]; v &= m - 1
	return v - m if t not in U and v >= m >> 1 else v
def prom(t):
	return {'c': 'i', 'uc': 'i', 's': 'i', 'us': 'u'}.get(t, t)
def bal(a, b):
	a, b = prom(a), prom(b)
	if 'ul' in (a, b): return 'ul'
	if 'l' in (a, b): return 'l'
	if 'u' in (a, b): return 'u'
	return 'i'
def tdiv(a, b):
	q = abs(a) // abs(b)
	return q if (a < 0) == (b < 0) else -q
def opasg(op, xt, x, yt, y):
	t = bal(xt, yt); a, b = wrap(t, x), wrap(t, y)
	r = tdiv(a, b) if op == '/' else a - tdiv(a, b) * b
	return wrap(xt, wrap(t, r))
# Pairs the divide's type differs from the left's in, and controls.
pairs = [('i', 'u'), ('s', 'us'), ('i', 'us'), ('c', 'u'), ('uc', 'u'), ('l', 'ul'),
	('u', 'i'), ('i', 'i'), ('l', 'l'), ('ul', 'l'), ('l', 'u'), ('us', 'i')]
# A long right operand over a word or byte: the divide is long.
pairs += [('i', 'l'), ('u', 'l'), ('i', 'ul'), ('u', 'ul'), ('c', 'l'), ('us', 'l'),
	('s', 'ul'), ('uc', 'l')]
xv = {'c': [-3, 100], 'uc': [200, 7], 's': [-3, -32768], 'us': [65000, 9],
	'i': [-3, 32767, -32768], 'u': [65535, 9], 'l': [-100, 0x7fffffff], 'ul': [0xFFFFFF9C, 12]}
yv = {'u': [2, 7, 40000], 'us': [2, 0x8000], 'i': [-2, 3], 'l': [-100, 7, 70000],
	'ul': [7, 0x80000010, 3], 'uc': [3]}
forms = ['g', 'a', 'r', 'p', 'q']
cases = []
for xt, yt in pairs:
	for op in '/%':
		for f in forms:
			cases.append((xt, yt, op, f))
N = 20
want = []
for p in range(0, len(cases), N):
	with open('%s/t%02d.c' % (T, p // N), 'w') as fo:
		fo.write('extern printf();\n')
		for n in range(p, min(p + N, len(cases))):
			xt, yt, op, f = cases[n]
			X = D[xt]
			fo.write('%s g%d;\n' % (X, n))
			fo.write('e%d(a, b) %s a; %s b; {\n' % (n, X, D[yt]))
			fo.write('\t%s v[3], *p; register %s x; %s y; long r, k;\n' % (X, X, X))
			fo.write('\tv[0] = v[2] = 0; v[1] = a; p = &v[1]; x = a; y = a; g%d = a; k = 0;\n' % n)
			lv = {'g': 'g%d' % n, 'a': 'y', 'r': 'x', 'p': '*p', 'q': '*p++'}[f]
			st = {'g': 'g%d' % n, 'a': 'y', 'r': 'x', 'p': 'v[1]', 'q': 'v[1]'}[f]
			fo.write('\tr = (long)(%s %s= b);\n' % (lv, op))
			fo.write('\tk = p - v;\n')
			fo.write('\tprintf("%%ld %%ld %%ld\\n", r, (long)%s, k);\n}\n' % st)
		fo.write('r%d() {\n' % (p // N))
		for n in range(p, min(p + N, len(cases))):
			xt, yt, op, f = cases[n]
			for x in xv[xt]:
				for y in yv[yt]:
					fo.write('\te%d((%s)%dL, (%s)%dL);\n' % (n, D[xt], wrap('l', x), D[yt], wrap('l', y)))
					r = opasg(op, xt, wrap(xt, x), yt, wrap(yt, y))
					want.append('%d %d %d' % (r, r, 2 if f == 'q' else 1))
		fo.write('}\n')
with open(T + '/m.c', 'w') as fo:
	fo.write('main() {\n' + ''.join('\tr%d();\n' % q for q in range((len(cases) + N - 1) // N)) + '\treturn 0;\n}\n')
open(T + '/want', 'w').write('\n'.join(want) + '\n')
EOF

[ -n "$N2" ] || { echo "  opasg: no guest runner"; exit 2; }
if (cd "$T" && "$CCZ" -o "$T/m" m.c t*.c >/dev/null 2>&1); then
	"$N2" -runexec "$T/m" > "$T/got" 2>/dev/null || true
	if cmp -s "$T/got" "$T/want"; then
		echo "  values ($(wc -l < "$T/want") results) PASS"
	else
		echo "  values FAIL ($(diff "$T/want" "$T/got" | grep -c '^>') wrong):"; fail=1
		diff "$T/want" "$T/got" | sed 5q | sed 's/^/      /'
	fi
else
	echo "  opasg: compile FAIL"; fail=1
fi

# A pair that balances to the left's own type compiles as before: one DIV or
# DIVL in the compound form, nothing extra.
cat > "$T/s.c" <<'EOF'
int i, j; unsigned u, w; long l, m;
f1() { i /= j; }
f2() { u /= w; }
f3() { l /= m; }
f4() { l %= u; }
EOF
(cd "$T" && "$CCZ" -c -o "$T/s.o" s.c >/dev/null 2>&1) || { echo "  opasg: shapes compile FAIL"; exit 1; }
shape() {
	d=$("$DIS" -v -fn "$1" "$T/s.o" 2>/dev/null) || true
	n=$(printf '%s\n' "$d" | grep -Ec "$2" || true)
	nb=$(printf '%s\n' "$d" | sed -n '1s/.*(\([0-9]*\) bytes).*/\1/p')
	if [ "$n.$nb" = "1.$3" ]; then
		printf '  %-3s %s bytes PASS\n' "$1" "$3"
	else
		printf '  %-3s FAIL: want one %s, %s bytes\n' "$1" "$2" "$3"; printf '%s\n' "$d" | sed 's/^/      /'; fail=1
	fi
}
shape f1_ " DIV " 22
shape f2_ " DIVL " 42
shape f3_ ' DIVL ' 22
shape f4_ " DIVL " 40

[ "$fail" = 0 ] || { echo "=== opasg: FAIL ==="; exit 1; }
echo "=== opasg: PASS ==="
