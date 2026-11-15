#!/bin/sh
# condcast.sh -- a cast of a `?:' or a comma converts its value before the
# value is widened.
#
# `(unsigned long)(unsigned short)(c ? a : b)' with short a and b is the
# unsigned short's value, zero-extended: (UL)(US)(c ? -2 : 0) is 65534.  The
# cases cast a `?:' or a comma, its values of other types, to unsigned char,
# unsigned short, signed char, short, unsigned and int, then widen the cast
# to long or unsigned long by a cast, an assignment, a compound assignment,
# the argument of a prototyped function, a return, an int or unsigned cast
# first and a double, or pass it to an unprototyped function, over nested
# `?:', a comma as a value, a comma over a `?:' and casts inside the `?:'.
# The values and the count of side effects are compared with a model of the
# C rules with a 16-bit int, a 32-bit long and the default level's
# unsigned-preserving promotion of an unsigned char.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
T=${CONDCAST_DIR:-$(mktemp -d)}; [ -n "$CONDCAST_DIR" ] || trap 'rm -rf "$T"' EXIT
fail=0

python3 - "$T" <<'EOF'
import sys
T = sys.argv[1]
W = {'c': 8, 'sc': 8, 'uc': 8, 's': 16, 'us': 16, 'i': 16, 'u': 16, 'l': 32, 'ul': 32}
U = {'uc', 'us', 'u', 'ul'}
D = {'c': 'char', 'sc': 'signed char', 'uc': 'unsigned char', 's': 'short',
	'us': 'unsigned short', 'i': 'int', 'u': 'unsigned', 'l': 'long', 'ul': 'unsigned long'}
def wrap(t, v):
	m = 1 << W[t]; v &= m - 1
	return v - m if t not in U and v >= m >> 1 else v
def prom(t):
	return {'c': 'i', 'sc': 'i', 'uc': 'u', 's': 'i', 'us': 'u'}.get(t, t)
def bal(a, b):
	a, b = prom(a), prom(b)
	if 'ul' in (a, b): return 'ul'
	if 'l' in (a, b): return 'l'
	if 'u' in (a, b): return 'u'
	return 'i'
# Expressions: ('v', name), ('q', cond, x, y), ('k', x) for `(k++, x)',
# ('t', type, x) for a cast.
def ty(x, at):
	if x[0] == 'v': return at[x[1]]
	if x[0] == 'q': return bal(ty(x[2], at), ty(x[3], at))
	if x[0] == 'k': return ty(x[1], at)
	return x[1]
def ev(x, at, env, st):
	if x[0] == 'v': return env[x[1]]
	if x[0] == 'q':
		return wrap(ty(x, at), ev(x[2] if env[x[1]] else x[3], at, env, st))
	if x[0] == 'k':
		st[0] += 1
		return ev(x[1], at, env, st)
	return wrap(x[1], ev(x[2], at, env, st))
def src(x):
	if x[0] == 'v': return x[1]
	if x[0] == 'q': return '(%s ? %s : %s)' % (x[1], src(x[2]), src(x[3]))
	if x[0] == 'k': return '(k++, %s)' % src(x[1])
	return '(%s)%s' % (D[x[1]], src(x[2]))
a, b, e = ('v', 'a'), ('v', 'b'), ('v', 'e')
forms = [
	('q', 'c', a, b),
	('q', 'c', ('q', 'd', a, e), b),
	('q', 'c', a, ('q', 'd', e, b)),
	('q', 'c', ('k', a), b),
	('k', ('q', 'c', a, b)),
	('k', a),
	('q', 'c', ('t', 'us', ('q', 'd', a, e)), b),
	('q', 'c', ('t', 's', ('q', 'd', a, e)), b),
	('q', 'c', a, ('k', ('q', 'd', e, b))),
]
casts = ['uc', 'us', 'sc', 's', 'u', 'i']
ctxs = ['cast', 'asg', 'proto', 'ret', 'kr', 'add', 'int', 'uns', 'dbl']
pairs = [('s', 's'), ('i', 'i'), ('us', 'us'), ('u', 'u'), ('c', 'c'), ('uc', 'uc'),
	('s', 'us'), ('i', 'u'), ('c', 'uc'), ('l', 'l'), ('ul', 'ul'), ('i', 'l'),
	('us', 'ul'), ('c', 's'), ('uc', 'i'), ('sc', 'u')]
triples = [('s', 's', 's'), ('i', 'u', 'i'), ('c', 'uc', 's'), ('us', 'us', 'i'), ('l', 'i', 's')]
vals = {'c': [-2, 127], 'sc': [-128, 5], 'uc': [254, 1], 's': [-2, 0x7ffe],
	'us': [65534, 0x8001], 'i': [-2, 300], 'u': [65534, 40000],
	'l': [-70000, 0x12345678], 'ul': [0xFFFFFFFE, 0x10002]}
cases = []
for t in casts:
	for w in ('l', 'ul'):
		for p in pairs:
			for x in ctxs:
				cases.append((forms[0], t, w, x, p + ('i',)))
		for f in forms[1:]:
			for p in triples:
				for x in ('cast', 'asg', 'proto', 'ret'):
					cases.append((f, t, w, x, p))
def ctxval(x, t, w, v):
	if x == 'kr': return wrap(w, wrap(prom(t), v))
	if x == 'add': return wrap(w, 1 + v)
	if x == 'int': return wrap(w, wrap('i', v))
	if x == 'uns': return wrap(w, wrap('u', v))
	return wrap(w, v)
N = 24
want = []
for p in range(0, len(cases), N):
	with open('%s/t%02d.c' % (T, p // N), 'w') as fo:
		fo.write('extern printf();\nextern int k;\n')
		fo.write('long pl(long x);\nunsigned long pul(unsigned long x);\nlong ki(), ku();\n')
		for n in range(p, min(p + N, len(cases))):
			f, t, w, x, at = cases[n]
			A = dict(zip('abe', at))
			E = '(%s)%s' % (D[t], src(f))
			W_ = D[w]
			fo.write('%s e%d(c, d, a, b, e) int c, d; %s a; %s b; %s e; {\n\t%s r; long l;\n'
				% (W_, n, D[at[0]], D[at[1]], D[at[2]], W_))
			fo.write('\t' + {'cast': 'r = (%s)%s;' % (W_, E), 'asg': 'r = %s;' % E,
				'proto': 'r = p%s(%s);' % (w, E), 'ret': 'return %s;' % E,
				'kr': 'r = k%s(%s);' % (prom(t), E), 'add': 'r = 1; r += %s;' % E,
				'int': 'r = (%s)(int)%s;' % (W_, E),
				'uns': 'r = (%s)(unsigned)%s;' % (W_, E),
				'dbl': 'l = (long)(double)%s; r = l;' % E}[x] + '\n')
			fo.write('\treturn r;\n}\n')
		fo.write('r%d() {\n\t%s v; unsigned long u;\n' % (p // N, 'long'))
		for n in range(p, min(p + N, len(cases))):
			f, t, w, x, at = cases[n]
			A = dict(zip('abe', at))
			for j in (0, 1):
				for c, d in ((1, 1), (1, 0), (0, 1)):
					env = {'a': wrap(A['a'], vals[A['a']][j]), 'b': wrap(A['b'], vals[A['b']][j]),
						'e': wrap(A['e'], vals[A['e']][1 - j]), 'c': c, 'd': d}
					st = [0]
					r = ctxval(x, t, w, ev(('t', t, f), A, env, st))
					arg = ', '.join('(%s)%dL' % (D[A[q]], wrap('l', env[q])) for q in 'abe')
					fo.write('\tk = 0; %s = e%d(%d, %d, %s); printf("%s %%d\\n", %s, k);\n'
						% ('v' if w == 'l' else 'u', n, c, d, arg, '%ld' if w == 'l' else '%lu',
						'v' if w == 'l' else 'u'))
					want.append('%d %d' % (r, st[0]))
		fo.write('}\n')
# Four chunks to a program, about 40K of text.
nch = (len(cases) + N - 1) // N
for g in range(0, nch, 4):
	with open('%s/m%02d.c' % (T, g // 4), 'w') as fo:
		fo.write('int k;\nlong pl(long x) { return x; }\n'
			'unsigned long pul(unsigned long x) { return x; }\n'
			'long ki(x) int x; { return x; }\nlong ku(x) unsigned x; { return x; }\n')
		fo.write('main() {\n' + ''.join('\tr%d();\n' % q for q in range(g, min(g + 4, nch))) + '\treturn 0;\n}\n')
	open('%s/want%02d' % (T, g // 4), 'w').write('\n'.join(want[g * N * 6:min(g + 4, nch) * N * 6]) + '\n')
open(T + '/cases', 'w').write(''.join('%d (%s)%s to %s by %s, a b e %s\n' % (n, c[1], src(c[0]), c[2], c[3], ' '.join(c[4])) for n, c in enumerate(cases)))
EOF

[ -n "$N2" ] || { echo "  condcast: no guest runner"; exit 2; }
: > "$T/want"; : > "$T/got"
for m in "$T"/m[0-9][0-9].c; do
	g=$(basename "$m" .c); g=${g#m}
	cat "$T/want$g" >> "$T/want"
	set --
	for q in $(sed -n 's/^\tr\([0-9]*\)();$/\1/p' "$m"); do set -- "$@" "t$(printf %02d "$q").c"; done
	if (cd "$T" && "$CCZ" -o "$T/m$g" "m$g.c" "$@" >/dev/null 2>&1); then
		"$N2" -runexec "$T/m$g" 2>/dev/null | grep -v '^\[exit' >> "$T/got" || true
	else
		echo "  condcast: program $g compile FAIL"; fail=1
	fi
done
if cmp -s "$T/got" "$T/want"; then
	echo "  values ($(wc -l < "$T/want") results, $(wc -l < "$T/cases") cases) PASS"
else
	echo "  values FAIL ($(diff "$T/want" "$T/got" | grep -c '^>') of $(wc -l < "$T/want") wrong)"; fail=1
	diff "$T/want" "$T/got" | sed 5q | sed 's/^/      /'
fi

[ "$fail" = 0 ] || { echo "=== condcast: FAIL ==="; exit 1; }
echo "=== condcast: PASS ==="
