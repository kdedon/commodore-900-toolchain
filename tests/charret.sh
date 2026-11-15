#!/bin/sh
# charret.sh -- a function of a char type returns its value narrowed to it.
#
# `unsigned char f() { return i; }' with int i = -2 returns 254: the function
# is compiled as returning unsigned int, so the value is narrowed to unsigned
# char and then widened.  The cases return, from a function of type char,
# signed char or unsigned char, a variable of each integer type (a global, an
# automatic, a register, a parameter, through a pointer), an expression of it
# (an addition, a multiplication, a shift, a `?:', a comma, an assignment, a
# postincrement, a compound assignment, a comparison, a negation), another
# such function's result and constants.  The caller assigns the result to
# long, unsigned long, int and unsigned, casts it to long and unsigned long,
# compares it, passes it to a prototyped and an unprototyped function and
# returns it from an int and a long function.  The values are compared with a
# model of the C rules with a 16-bit int and a 32-bit long; out-of-range
# conversions to a signed type wrap, as gcc's do.  The narrowing and the
# widening that follows it extend the byte once.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
T=${CHARRET_DIR:-$(mktemp -d)}; [ -n "$CHARRET_DIR" ] || trap 'rm -rf "$T"' EXIT
fail=0

python3 - "$T" <<'EOF'
import sys
T = sys.argv[1]
W = {'c': 8, 'sc': 8, 'uc': 8, 's': 16, 'i': 16, 'u': 16, 'l': 32, 'ul': 32}
U = {'uc', 'u', 'ul'}
D = {'c': 'char', 'sc': 'signed char', 'uc': 'unsigned char', 's': 'short',
	'i': 'int', 'u': 'unsigned', 'l': 'long', 'ul': 'unsigned long'}
def wrap(t, v):
	m = 1 << W[t]; v &= m - 1
	return v - m if t not in U and v >= m >> 1 else v
vals = {'c': [-2, -128, 127, 100], 'sc': [-2, -128, 127], 'uc': [254, 255, 1, 128],
	's': [-2, 300, -300, 10000], 'i': [-2, 300, -300, 254, 10000],
	'u': [65534, 300, 254, 40000], 'l': [-2, 70254, -70000, 305419896],
	'ul': [4294967294, 70254, 3000000000]}
lit = {'u': 'U', 'l': 'L', 'ul': 'UL'}
# Each source: the body of f (X is the global of the source type, Y its type)
# and its value from the global's value v.
srcs = {
	'var': ('return X;', lambda t, v: v),
	'auto': ('Y c = X;\n\treturn c;', lambda t, v: v),
	'reg': ('register Y c = X;\n\treturn c;', lambda t, v: v),
	'parm': (None, lambda t, v: v),
	'ptr': ('Y *p = &X;\n\treturn *p;', lambda t, v: v),
	'add': ('return X + 1;', lambda t, v: v + 1),
	'mul': ('return X * 3;', lambda t, v: v * 3),
	'shr': ('return X >> 1;', lambda t, v: v >> 1),
	'quest': ('return gk ? X : 0;', lambda t, v: v),
	'comma': ('return (gk = 1, X);', lambda t, v: v),
	'asg': ('Y c;\n\treturn c = X + 1;', lambda t, v: wrap(t, v + 1)),
	'post': ('Y c = X;\n\treturn c++;', lambda t, v: v),
	'opasg': ('Y c = X;\n\treturn c += 1;', lambda t, v: wrap(t, v + 1)),
	'call': ('return hX();', lambda t, v: v),
	'rel': ('return X > 1;', lambda t, v: int(v > 1)),
	'not': ('return !X;', lambda t, v: int(v == 0)),
	'const': (None, lambda t, v: v),
}
rets = ['c', 'sc', 'uc']
cases = []
for r in rets:
	for t in D:
		for s in srcs:
			if s == 'const':
				if t in ('c', 'sc', 'uc', 's'): continue
				for v in vals[t]: cases.append((r, t, s, v))
			else:
				cases.append((r, t, s, None))
# The caller's uses of f(); w is the value f returns.
ctx = [('long l', 'l = f();', '%ld', 'l', lambda w: w),
	('unsigned long ul', 'ul = f();', '%lu', 'ul', lambda w: w & 0xFFFFFFFF),
	('int i', 'i = f();', '%d', 'i', lambda w: w),
	('unsigned u', 'u = f();', '%u', 'u', lambda w: w & 0xFFFF),
	(None, None, '%ld', '(long)f()', lambda w: w),
	(None, None, '%lu', '(unsigned long)f()', lambda w: w & 0xFFFFFFFF),
	(None, None, '%d', 'f() == w', lambda w: 1),
	(None, None, '%d', 'f() < 0', lambda w: int(w < 0)),
	(None, None, '%d', 'f() > 127', lambda w: int(w > 127)),
	(None, None, '%ld', 'pl(f())', lambda w: w),
	(None, None, '%d', 'pi(f())', lambda w: w),
	(None, None, '%ld', 'pk(f())', lambda w: w),
	(None, None, '%d', 'ri()', lambda w: w),
	(None, None, '%ld', 'rl()', lambda w: w)]
N = 16
want = []
for q in range(0, len(cases), N):
	with open('%s/t%02d.c' % (T, q // N), 'w') as fo:
		fo.write('extern printf();\nextern int gk;\nlong pl(long x);\nint pi(int x);\nlong pk();\n')
		for t in D:
			fo.write('extern %s g_%s;\n%s h_%s();\n' % (D[t], t, D[t], t))
		for n in range(q, min(q + N, len(cases))):
			r, t, s, v = cases[n]
			R, Y, X = D[r], D[t], 'g_' + t
			if s == 'parm':
				fo.write('%s f%d(%s c) {\n\treturn c;\n}\n' % (R, n, Y))
				call = 'f%d(%s)' % (n, X)
			else:
				if s == 'const':
					body = 'return %d%s;' % (v, lit.get(t, ''))
				else:
					body = srcs[s][0].replace('hX', 'h_' + t).replace('X', X).replace('Y', Y)
				fo.write('%s f%d() {\n\t%s\n}\n' % (R, n, body))
				call = 'f%d()' % n
			fo.write('int ri%d() { return %s; }\nlong rl%d() { return %s; }\n' % (n, call, n, call))
			fo.write('c%d(w)\nint w;\n{\n\tlong l; unsigned long ul; int i; unsigned u;\n\n' % n)
			for dcl, asg, f, e, m in ctx:
				e = e.replace('f()', call).replace('ri()', 'ri%d()' % n).replace('rl()', 'rl%d()' % n)
				if asg:
					fo.write('\t%s printf("%s\\n", %s);\n' % (asg.replace('f()', call), f, e))
				else:
					fo.write('\tprintf("%s\\n", %s);\n' % (f, e))
			fo.write('}\n')
		fo.write('r%d() {\n' % (q // N))
		for n in range(q, min(q + N, len(cases))):
			r, t, s, v = cases[n]
			for x in ([v] if s == 'const' else vals[t]):
				w = wrap(r, srcs[s][1](t, x))
				fo.write('\tg_%s = %d%s; c%d(%d);\n' % (t, x, lit.get(t, ''), n, w))
				want.extend('%d' % m(w) for dcl, asg, f, e, m in ctx)
		fo.write('}\n')
nch = (len(cases) + N - 1) // N
G = 3
for g in range(0, nch, G):
	with open('%s/m%02d.c' % (T, g // G), 'w') as fo:
		fo.write('int gk = 1;\n')
		for t in D:
			fo.write('%s g_%s;\n%s h_%s() { return g_%s; }\n' % (D[t], t, D[t], t, t))
		fo.write('long pl(long x) { return x; }\nint pi(int x) { return x; }\n'
			'long pk(x)\nint x;\n{\n\treturn x;\n}\n')
		fo.write('main() {\n' + ''.join('\tr%d();\n' % q for q in range(g, min(g + G, nch))) + '\treturn 0;\n}\n')
	lo = sum(len(ctx) * (1 if cases[n][2] == 'const' else len(vals[cases[n][1]])) for n in range(0, g * N))
	hi = sum(len(ctx) * (1 if cases[n][2] == 'const' else len(vals[cases[n][1]])) for n in range(0, min((g + G) * N, len(cases))))
	open('%s/want%02d' % (T, g // G), 'w').write('\n'.join(want[lo:hi]) + '\n')
open(T + '/cases', 'w').write(''.join('%d %s f() returning %s by %s%s\n' % (n, D[c[0]], D[c[1]], c[2],
	'' if c[3] is None else ' %d' % c[3]) for n, c in enumerate(cases)))
EOF

[ -n "$N2" ] || { echo "  charret: no guest runner"; exit 2; }
: > "$T/want"; : > "$T/got"
for m in "$T"/m[0-9][0-9].c; do
	g=$(basename "$m" .c); g=${g#m}
	cat "$T/want$g" >> "$T/want"
	set --
	for q in $(sed -n 's/^\tr\([0-9]*\)();$/\1/p' "$m"); do set -- "$@" "t$(printf %02d "$q").c"; done
	if (cd "$T" && "$CCZ" -o "$T/m$g" "m$g.c" "$@" >/dev/null 2>&1); then
		"$N2" -runexec "$T/m$g" 2>/dev/null | grep -v '^\[exit' >> "$T/got" || true
	else
		echo "  charret: program $g compile FAIL"; fail=1
	fi
done
if cmp -s "$T/got" "$T/want"; then
	echo "  values ($(wc -l < "$T/want") results, $(wc -l < "$T/cases") cases) PASS"
else
	echo "  values FAIL ($(diff "$T/want" "$T/got" | grep -c '^>') of $(wc -l < "$T/want") wrong)"; fail=1
	diff "$T/want" "$T/got" | sed 5q | sed 's/^/      /'
fi

# A narrowed and widened byte extends once: no EXTSB or CLRB repeated.
DIS="$H/host/build/tools/loutdis"
if [ -x "$DIS" ]; then
	: > "$T/dups"
	for t in "$T"/t[0-9][0-9].c; do
		"$CCZ" -c -o "$T/x.o" "$t" >/dev/null 2>&1 || { echo "  charret: $(basename "$t") compile FAIL"; fail=1; continue; }
		"$DIS" "$T/x.o" -v | sed -n 's/^ *[0-9a-f]*: //p' |
			awk -v f="$(basename "$t")" '$0 == p && ($1 == "EXTSB" || $1 == "CLRB") { print f ": " $0 } { p = $0 }' >> "$T/dups"
	done
	if [ -s "$T/dups" ]; then
		echo "  repeated extension FAIL ($(wc -l < "$T/dups"))"; sed 5q "$T/dups" | sed 's/^/      /'; fail=1
	else
		echo "  one extension per narrowing PASS"
	fi
fi

[ "$fail" = 0 ] || { echo "=== charret: FAIL ==="; exit 1; }
echo "=== charret: PASS ==="
