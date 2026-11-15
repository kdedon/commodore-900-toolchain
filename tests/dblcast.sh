#!/bin/sh
# dblcast.sh -- a cast of a float-to-integer conversion converts the integer,
# not the float.
#
# `(unsigned long)(long)d' with double d = -2.0 is (unsigned long)-2L,
# 4294967294.  The cases convert a double or a float (a variable, a function's
# result or an expression) to an integer type, then cast it to a type of the
# same size and the other signedness (or the same signedness, as a control),
# then widen it to long or unsigned long by a cast, an assignment, a prototyped
# argument or a return, or return the conversion from a function of the cast's
# type (of a 16- or 32-bit type), or cast it to and fro twice.  Each value is in the range of the type it
# is first converted to, so every case is defined.  The values are compared
# with a model of the C rules with a 16-bit int and a 32-bit long.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
T=${DBLCAST_DIR:-$(mktemp -d)}; [ -n "$DBLCAST_DIR" ] || trap 'rm -rf "$T"' EXIT
fail=0

python3 - "$T" <<'EOF'
import sys, math
T = sys.argv[1]
W = {'c': 8, 'sc': 8, 'uc': 8, 's': 16, 'us': 16, 'i': 16, 'u': 16, 'l': 32, 'ul': 32}
U = {'uc', 'us', 'u', 'ul'}
D = {'c': 'char', 'sc': 'signed char', 'uc': 'unsigned char', 's': 'short',
	'us': 'unsigned short', 'i': 'int', 'u': 'unsigned', 'l': 'long', 'ul': 'unsigned long'}
def wrap(t, v):
	m = 1 << W[t]; v &= m - 1
	return v - m if t not in U and v >= m >> 1 else v
# (first type, cast type): the same size, mostly of the other signedness.
pairs = [('c', 'uc'), ('sc', 'uc'), ('uc', 'c'), ('uc', 'sc'), ('s', 'us'), ('us', 's'),
	('i', 'u'), ('u', 'i'), ('s', 'u'), ('i', 'us'), ('l', 'ul'), ('ul', 'l'),
	('s', 'i'), ('u', 'us')]
# Values in range of the first type, exact in a float.
vals = {'c': [-2.0, -128.0, 100.5], 'sc': [-2.5, 127.0], 'uc': [254.0, 1.0],
	's': [-2.0, -32768.0, 30000.75], 'i': [-2.0, -32768.0, 30000.75],
	'us': [65534.0, 40000.5, 1.0], 'u': [65534.0, 40000.5, 1.0],
	'l': [-2.0, -70000.5, 16777216.0, -2147483648.0],
	'ul': [4294967040.0, 3000000000.0, 2.0]}
# Sources: x is the expression the first conversion applies to.
srcs = {'dv': 'gd', 'fv': 'gf', 'dfn': 'fd()', 'ffn': 'ff()', 'dexp': '(gd * 1.0)'}
ctxs = ['none', 'cast', 'asg', 'proto', 'ret', 'retc', 'chain']
cases = []
for p in pairs:
	for s in srcs:
		for x in ctxs:
			# A function of a char type returns its value unnarrowed, a
			# separate defect: `unsigned char f() { return i; }'.
			if x == 'retc' and W[p[1]] == 8: continue
			for w in (['o'] if x == 'none' else ['l', 'ul']):
				cases.append((p, s, x, w))
N = 24
want = []
for q in range(0, len(cases), N):
	with open('%s/t%02d.c' % (T, q // N), 'w') as fo:
		fo.write('extern printf();\nextern double gd; extern float gf;\n'
			'double fd(); float ff();\n'
			'long pl(long x);\nunsigned long pul(unsigned long x);\n')
		for n in range(q, min(q + N, len(cases))):
			(i, o), s, x, w = cases[n]
			I, O, X = D[i], D[o], srcs[s]
			R = D[o] if w == 'o' else D[w]
			E = '(%s)(%s)%s' % (O, I, X)
			if x == 'retc':
				fo.write('%s c%d() { return (%s)%s; }\n' % (O, n, I, X))
			fo.write('%s e%d() {\n\t%s r;\n' % (R, n, R))
			fo.write('\t' + {'none': 'r = %s;' % E, 'cast': 'r = (%s)%s;' % (R, E),
				'asg': 'r = %s;' % E, 'proto': 'r = p%s(%s);' % (w, E),
				'ret': 'return %s;' % E, 'retc': 'r = c%d();' % n,
				'chain': 'r = (%s)(%s)(%s)%s;' % (R, O, I, E)}[x] + '\n')
			fo.write('\treturn r;\n}\n')
		fo.write('r%d() {\n' % (q // N))
		for n in range(q, min(q + N, len(cases))):
			(i, o), s, x, w = cases[n]
			R = o if w == 'o' else w
			for v in vals[i]:
				g = 'gf' if s in ('fv', 'ffn') else 'gd'
				r = wrap(R, wrap(o, int(math.trunc(v))))
				f = '%lu' if R in U else '%ld'
				fo.write('\t%s = %r; printf("%s\\n", (%s)e%d());\n'
					% (g, v, f, 'unsigned long' if R in U else 'long', n))
				want.append('%d' % r)
		fo.write('}\n')
nch = (len(cases) + N - 1) // N
for g in range(0, nch, 4):
	with open('%s/m%02d.c' % (T, g // 4), 'w') as fo:
		fo.write('double gd; float gf;\ndouble fd() { return gd; }\nfloat ff() { return gf; }\n'
			'long pl(long x) { return x; }\n'
			'unsigned long pul(unsigned long x) { return x; }\n')
		fo.write('main() {\n' + ''.join('\tr%d();\n' % q for q in range(g, min(g + 4, nch))) + '\treturn 0;\n}\n')
	lo = sum(len(vals[cases[n][0][0]]) for n in range(0, g * N))
	hi = sum(len(vals[cases[n][0][0]]) for n in range(0, min((g + 4) * N, len(cases))))
	open('%s/want%02d' % (T, g // 4), 'w').write('\n'.join(want[lo:hi]) + '\n')
open(T + '/cases', 'w').write(''.join('%d (%s)(%s) of %s by %s to %s\n' % (n, D[c[0][1]], D[c[0][0]], c[1], c[2], c[3]) for n, c in enumerate(cases)))
EOF

[ -n "$N2" ] || { echo "  dblcast: no guest runner"; exit 2; }
: > "$T/want"; : > "$T/got"
for m in "$T"/m[0-9][0-9].c; do
	g=$(basename "$m" .c); g=${g#m}
	cat "$T/want$g" >> "$T/want"
	set --
	for q in $(sed -n 's/^\tr\([0-9]*\)();$/\1/p' "$m"); do set -- "$@" "t$(printf %02d "$q").c"; done
	if (cd "$T" && "$CCZ" -o "$T/m$g" "m$g.c" "$@" >/dev/null 2>&1); then
		"$N2" -runexec "$T/m$g" 2>/dev/null | grep -v '^\[exit' >> "$T/got" || true
	else
		echo "  dblcast: program $g compile FAIL"; fail=1
	fi
done
if cmp -s "$T/got" "$T/want"; then
	echo "  values ($(wc -l < "$T/want") results, $(wc -l < "$T/cases") cases) PASS"
else
	echo "  values FAIL ($(diff "$T/want" "$T/got" | grep -c '^>') of $(wc -l < "$T/want") wrong)"; fail=1
	diff "$T/want" "$T/got" | sed 5q | sed 's/^/      /'
fi

[ "$fail" = 0 ] || { echo "=== dblcast: FAIL ==="; exit 1; }
echo "=== dblcast: PASS ==="
