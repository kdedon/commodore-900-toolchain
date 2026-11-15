#!/bin/sh
# longuns.sh -- `long' with `unsigned int' is long.
#
# With a 16-bit int and a 32-bit long, a long holds every unsigned int, so the
# usual arithmetic conversions make `l op u' a long: C89 3.2.1.5, and K&R
# (Appendix A 6.6), which converts to long before it looks at unsigned.  An
# unsigned short and an unsigned char become unsigned int and int, and so long
# too.  An unsigned long with any int or long is still unsigned long.
#
# Values: about 200 expressions over every operand order of those pairs --
# * / % >> << + - the relations, ?:, compound assignment, folded constants --
# printed by a Z8001 run and compared with the same expressions evaluated with
# a 16-bit int and 32-bit long by a model of C89's rules, at -VC89 and -VC99,
# and of the same rules with MWC's unsigned-preserving promotion, an unsigned
# char becoming unsigned int, at the default level and -VKR.  Shapes: `l / u' is EXTSL and DIVL like `l / 7L', `l < u'
# branches signed, and `ul / i' keeps the unsigned divide.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"; CC1="$BUILD/z8001/cc1-z8001"
CC2="$BUILD/z8001/cc2-z8001"; DIS="$BUILD/tools/loutdis"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

# The cases and their expected values.  t*.c define one function a case; m.c
# runs them over each set of values; want holds what C89 says they print.
python3 - "$T" <<'EOF'
import sys
T = sys.argv[1]
W = {'c': 8, 'uc': 8, 'i': 16, 'u': 16, 'us': 16, 'l': 32, 'ul': 32}
U = {'uc', 'u', 'us', 'ul'}
def wrap(t, v):
	m = 1 << W[t]; v &= m - 1
	return v - m if t not in U and v >= m >> 1 else v
VP = 1				# value-preserving (C89) or MWC's unsigned-preserving
def prom(t):			# C89, int 16 bits: unsigned short becomes unsigned int
	return {'c': 'i', 'uc': VP and 'i' or 'u', 'us': 'u'}.get(t, t)
def bal(a, b):
	a, b = prom(a), prom(b)
	if 'ul' in (a, b): return 'ul'
	if 'l' in (a, b): return 'l'	# a long holds every unsigned int
	if 'u' in (a, b): return 'u'
	return 'i'
def tdiv(a, b):
	q = abs(a) // abs(b)
	return q if (a < 0) == (b < 0) else -q
def ev(e, env):
	"""-> (type, value) of the expression tree e"""
	k = e[0]
	if k == 'v': return env[e[1]]
	if k == 'k': return e[2], e[1]
	if k == '?':
		ct, cv = ev(e[1], env); t = bal(ev(e[2], env)[0], ev(e[3], env)[0])
		return t, wrap(t, ev(e[2] if cv else e[3], env)[1])
	if k == '=':			# compound assignment: x = (type of x)(x op y)
		x = e[2][1]; xt, xv = env[x]
		t, v = binop(e[1], (xt, xv), ev(e[3], env))
		env[x] = (xt, wrap(xt, v))
		return env[x]
	return binop(k, ev(e[1], env), ev(e[2], env))
def binop(op, a, b):
	(at, av), (bt, bv) = a, b
	if op in ('<<', '>>'):
		t = prom(at); v = wrap(t, av); n = wrap('i', bv)
		return t, wrap(t, v << n if op == '<<' else v >> n)
	t = bal(at, bt); x, y = wrap(t, av), wrap(t, bv)
	if op in ('<', '<=', '>', '>=', '==', '!='):
		return 'i', int(eval('x %s y' % op))
	if op == '/': return t, wrap(t, tdiv(x, y))
	if op == '%': return t, wrap(t, x - tdiv(x, y) * y)
	return t, wrap(t, eval('x %s y' % op))
def c(e):
	k = e[0]
	if k == 'v': return e[1]
	if k == 'k': return e[3]
	if k == '?': return '(%s ? %s : %s)' % (c(e[1]), c(e[2]), c(e[3]))
	if k == '=': return '(%s %s= %s)' % (c(e[2]), e[1], c(e[3]))
	return '(%s %s %s)' % (c(e[1]), k, c(e[2]))
V = lambda n: ('v', n)
K = lambda v, t, s: ('k', v, t, s)
decl = {'l': 'long', 'm': 'long', 'u': 'unsigned', 'us': 'unsigned short',
	'uc': 'unsigned char', 'i': 'int', 'ul': 'unsigned long', 'n': 'unsigned', 's': 'long'}
typ = {'l': 'l', 'm': 'l', 'u': 'u', 'us': 'us', 'uc': 'uc', 'i': 'i', 'ul': 'ul', 'n': 'u', 's': 'l'}
# l, m: longs; u, us, uc: the unsigned divisors; n, s: shift counts.
sets = [
	dict(l=-100, m=-1, u=49, us=65000, uc=200, i=-3, ul=0x80000010, n=3, s=2),
	dict(l=-70000, m=70000, u=65535, us=7, uc=3, i=5, ul=7, n=1, s=4),
	dict(l=123457, m=-2, u=3, us=40000, uc=255, i=-1, ul=100000, n=15, s=17),
]
cases = []
ar = ['*', '/', '%', '+', '-', '<', '<=', '>', '>=', '==', '!=']
pairs = [('l', 'u'), ('l', 'us'), ('l', 'uc'), ('m', 'u'),
	('ul', 'i'), ('ul', 'l'), ('ul', 'u'), ('ul', 'uc'),
	('uc', 'i'), ('uc', 'u'), ('uc', 'us')]	# unsigned char's promotion
for a, b in pairs:
	for x, y in ((a, b), (b, a)):
		for op in ar:
			cases.append((op, V(x), V(y)))
		for op in ('+', '-', '*'):	# the result's signedness, seen by / and <
			cases.append(('/', (op, V(x), V(y)), K(3, 'l', '3L')))
			cases.append(('<', (op, V(x), V(y)), K(0, 'i', '0')))
			cases.append(('>>', (op, V(x), V(y)), K(1, 'i', '1')))
		cases.append(('?', V('i'), V(x), V(y)))
		cases.append(('/', ('?', V('i'), V(x), V(y)), K(3, 'l', '3L')))
		cases.append(('<', ('?', V('i'), V(x), V(y)), K(0, 'i', '0')))
for x in ('l', 'm', 'ul', 'u', 'us'):
	for y in ('n', 's'):
		if y == 'n' or x in ('l', 'm', 'ul'):
			for op in ('>>', '<<'):
				cases.append((op, V(x), V(y)))
# Compound assignment, each operand order.  A quotient or remainder whose
# operands balance to a type other than the left's -- `u /= l', `i /= ul',
# `l /= ul' -- is another matter and is not checked here.
for x, y in (('l', 'u'), ('l', 'us'), ('l', 'uc'), ('u', 'l'), ('us', 'l'),
		('ul', 'i'), ('i', 'ul'), ('ul', 'l'), ('l', 'ul'), ('u', 'm')):
	for op in ('/', '%', '*', '+', '-'):
		if op in '/%' and x in ('u', 'us', 'i') + (y == 'ul') * ('l',):
			continue
		cases.append(('=', op, V(x), V(y)))
	cases.append(('=', '>>', V(x), V('n')))
	cases.append(('=', '<<', V(x), V('n')))
# The reported forms, and constants (some folded by cc0).
cases += [
	('/', ('*', V('l'), K(0xFFFF, 'u', '0xFFFF')), K(7, 'l', '7L')),
	('/', ('*', K(0xFFFF, 'u', '0xFFFF'), V('m')), K(7, 'l', '7L')),
	('/', V('l'), K(49, 'u', '49u')), ('%', V('l'), K(49, 'u', '49u')),
	('/', K(-100, 'l', '-100L'), V('u')), ('<', V('l'), K(65535, 'u', '65535u')),
	('/', K(-100, 'l', '-100L'), K(49, 'u', '49u')),
	('%', K(-100, 'l', '-100L'), K(49, 'u', '49u')),
	('<', K(65535, 'u', '65535u'), K(-1, 'l', '-1L')),
	('<', K(-1, 'l', '-1L'), K(1, 'u', '1u')),
	('/', ('-', K(1, 'u', '1u'), K(2, 'l', '2L')), K(3, 'l', '3L')),
	('/', K(0x80000000, 'ul', '0x80000000'), K(-2, 'i', '-2')),
	('<', K(-1, 'i', '-1'), K(1, 'ul', '1ul')),
	('/', ('*', K(0xFFFF, 'u', '0xFFFF'), K(-1, 'l', '-1L')), K(7, 'l', '7L')),
	('?', K(1, 'i', '1'), K(-1, 'l', '-1L'), K(1, 'u', '1u')),
]
N = 25				# cases a file: cc2 bounds an object's relocations
for p in range(0, len(cases), N):
	with open(T + '/t%02d.c' % (p // N), 'w') as f:
		f.write('extern printf();\n')
		f.write(''.join('%s %s %s;\n' % (p and 'extern' or '', decl[v], v) for v in decl))
		for n in range(p, min(p + N, len(cases))):
			e = cases[n]
			if e[0] == '=':		# the assigned variable is put back
				x = e[2][1]
				f.write('long e%d() { %s t; long r; t = %s; r = (long)%s; %s = t; return r; }\n'
					% (n, decl[x], x, c(e), x))
			else:
				f.write('long e%d() { return (long)%s; }\n' % (n, c(e)))
		f.write('r%d() {\n' % (p // N))
		for n in range(p, min(p + N, len(cases))):
			f.write('\tprintf("%%ld\\n", e%d());\n' % n)
		f.write('}\n')
with open(T + '/m.c', 'w') as f:
	f.write(''.join('extern %s %s;\n' % (decl[v], v) for v in decl))
	f.write('set(a, b, c, d, e, g, h, j, k) long a, b; unsigned c, d; unsigned char e; int g; unsigned long h; unsigned j; long k;\n')
	f.write('{ l = a; m = b; u = c; us = d; uc = e; i = g; ul = h; n = j; s = k; }\n')
	f.write('main() {\n')
	want = []; wantu = []
	for st in sets:
		f.write('\tset(%dL, %dL, %du, %du, %d, %d, %dL, %du, %dL);\n' % tuple(
			wrap(typ[v] if v != 'ul' else 'l', st[v]) for v in ('l', 'm', 'u', 'us', 'uc', 'i', 'ul', 'n', 's')))
		f.write(''.join('\tr%d();\n' % q for q in range((len(cases) + N - 1) // N)))
		for n, e in enumerate(cases):
			env = {v: (typ[v], wrap(typ[v], st[v])) for v in st}
			want.append(str(wrap('l', ev(e, env)[1])))
			VP = 0
			env = {v: (typ[v], wrap(typ[v], st[v])) for v in st}
			wantu.append(str(wrap('l', ev(e, env)[1])))
			VP = 1
	f.write('\treturn 0;\n}\n')
open(T + '/want', 'w').write('\n'.join(want) + '\n')
open(T + '/wantu', 'w').write('\n'.join(wantu) + '\n')
open(T + '/names', 'w').write(''.join('e%d %s\n' % (n, c(e)) for n, e in enumerate(cases)) * len(sets))
EOF

[ -n "$N2" ] || { echo "  longuns: no guest runner"; exit 2; }
run() { # <what> <level> <want>
	if (cd "$T" && CCZ_LEVEL=$2 "$CCZ" -o "$T/m" m.c t*.c >/dev/null 2>&1); then
		"$N2" -runexec "$T/m" > "$T/got" 2>/dev/null || true
		if cmp -s "$T/got" "$T/$3"; then
			echo "  $1 values ($(wc -l < "$T/$3") results) PASS"
		else
			echo "  $1 values FAIL:"; fail=1
			paste -d' ' "$T/names" "$T/$3" "$T/got" | awk '$(NF-1) != $NF' | sed 5q |
				sed 's/^/      /; s/ \([^ ]*\) \([^ ]*\)$/  want \1 got \2/'
		fi
	else
		echo "  $1: compile FAIL"; fail=1
	fi
}
run "default level" "" wantu
run "-VKR" KR wantu
run "-VC89" C89 want
run "-VC99" C99 want

# Shapes.  <fn> <pattern that must occur> <pattern that must not>
cat > "$T/s.c" <<'EOF'
long h(dx, c) long dx; unsigned c; { return dx / c; }
long d7(dx) long dx; { return dx / 7L; }
long m(dx) long dx; { return (dx * 0xFFFF) / 7L; }
lt(l, u) long l; unsigned u; { return l < u; }
long ud(ul, i) unsigned long ul; { return ul / i; }
long ad(l, u) long l; unsigned u; { l /= u; return l; }
EOF
"$CC0" $VAR "$T/s.c" "$T/s.z0" && "$CC1" $VAR "$T/s.z0" "$T/s.z1" &&
"$CC2" 0012 "$T/s.z1" "$T/s.o" "$T/s.scr" 0 || { echo "  longuns: shapes compile FAIL"; exit 1; }
shape() {
	d=$("$DIS" -v -fn "$1" "$T/s.o" 2>/dev/null) || true
	if printf '%s\n' "$d" | grep -Eq "$2" && ! printf '%s\n' "$d" | grep -Eq "$3"; then
		printf '  %-4s %s PASS\n' "$1" "$4"
	else
		printf '  %-4s FAIL: want %s\n' "$1" "$4"; printf '%s\n' "$d" | sed 's/^/      /'; fail=1
	fi
}
shape h_ ' EXTSL ' ' TESTL | JR +ULT' "signed divide"
shape d7_ ' EXTSL ' ' TESTL ' "signed divide"
shape m_ ' EXTSL ' ' SUBL +RR0,RR0' "signed divide"
shape lt_ ' JR +(LT|LE|GT|GE),' ' JR +U' "signed branch"
shape ud_ ' TESTL ' ' EXTSL ' "unsigned divide"
shape ad_ ' EXTSL ' ' TESTL ' "signed divide"

[ "$fail" = 0 ] || { echo "=== longuns: FAIL ==="; exit 1; }
echo "=== longuns: PASS ==="
