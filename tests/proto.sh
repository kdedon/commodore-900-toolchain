#!/bin/sh
# proto.sh -- function prototypes and ANSI definitions.
#
# A call through a prototype converts each fixed argument to its parameter's
# promoted type, as assignment would; the arguments matching `...' keep the
# default promotions.  The callee sees the K&R calling convention either way,
# so an object compiled with prototypes links against one compiled without:
# the program below mixes K&R definitions called through prototypes and ANSI
# definitions called without one.  An ANSI definition compiles to exactly the
# object of its K&R form, and a call whose arguments already have the
# parameters' types is the same with or without the prototype.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/kr.c" <<'EOF'
long lsum(a, b, c) long a; char *b; long c; { return a + c + (b == 0 ? 1000 : 2000); }
unsigned long ulid(u) unsigned long u; { return u; }
int cid(c) char c; { return c; }
double dmul(x, y) float x; double y; { return x * y; }
int isnull(p) char *p; { return p == 0; }
long vsum(n, a) int n; long a; { long *p, s; s = 0; for (p = &a; n-- > 0; ++p) s += *p; return s; }
EOF
cat > "$T/ansi.c" <<'EOF'
long lsum(long a, char *b, long c) { return a + c + (b == 0 ? 1000 : 2000); }
unsigned long ulid(unsigned long u) { return u; }
int cid(char c) { return c; }
double dmul(float x, double y) { return x * y; }
int isnull(char *p) { return p == 0; }
long vsum(int n, long a) { long *p, s; s = 0; for (p = &a; n-- > 0; ++p) s += *p; return s; }
EOF
cat > "$T/ansicallee.c" <<'EOF'
struct P { int x, y; };
long amix(int a, long b, char *s, int c) { return a * 100L + b * 10 + c + (s != 0); }
int apt(struct P p, int k) { return p.x * k + p.y; }
double ahalf(float f) { return f / 2; }
EOF
cat > "$T/main.c" <<'EOF'
#include <stdio.h>
extern long lsum(long a, char *b, long c);
extern unsigned long ulid(unsigned long);
extern int cid(char);
extern double dmul(float, double);
extern int isnull(char *);
extern long vsum(int n, ...);
struct P { int x, y; };
typedef long (*LF)(long, char *, long);
struct ops { LF f; unsigned long (*u)(unsigned long); } ops = { lsum, ulid };
long amix();
extern int apt();
double ahalf();
int ptr(int (*f)(char), int v) { return f(v); }
main() {
	int i, m;
	unsigned u;
	struct P p;
	i = -2; m = 3; u = 0xFFFF;
	printf("%ld %ld\n", lsum(1, 0, 2), lsum(i, "x", m));
	printf("%lx %lx %lx\n", ulid(i), ulid(u), ulid(0x12345678L));
	printf("%d %d\n", cid(300), cid('a'));
	printf("%d\n", (int)dmul(3, 2.5));
	printf("%d %d\n", isnull(0), isnull("s"));
	printf("%ld\n", vsum(3, 1L, 20L, (long)300));
	printf("%ld %lx\n", (*ops.f)(i, 0, 1), (*ops.u)(-1));
	printf("%ld\n", ((long (*)(long, char *, long))lsum)(5, 0, 5));
	printf("%d\n", ptr(cid, 0x141));
	printf("%ld\n", amix(1, 2L, "s", 3));
	p.x = 4; p.y = 5;
	printf("%d %d\n", apt(p, 10), (int)ahalf(9.0));
	return 0;
}
EOF
cat > "$T/want" <<'EOF'
1003 2001
fffffffe ffff 12345678
44 97
7
1 0
321
999 ffffffff
1010
65
124
45 4
EOF

[ -n "$N2" ] || { echo "  proto: no guest runner"; exit 2; }
for callee in kr ansi; do
	if "$CCZ" -o "$T/m" "$T/main.c" "$T/$callee.c" "$T/ansicallee.c" >/dev/null 2>&1 &&
	   "$N2" -runexec "$T/m" > "$T/got" 2>/dev/null && cmp -s "$T/want" "$T/got"; then
		echo "  mixed calls, $callee callee PASS"
	else
		echo "  mixed calls, $callee callee FAIL"; diff "$T/want" "$T/got" || true; fail=1
	fi
done

# Same object: ANSI and K&R definitions; a call with and without a prototype
# when every argument already has its parameter's type.
same() { # <what> <a.c> <b.c>
	"$CCZ" -c -o "$T/a.o" "$2" >/dev/null 2>&1 && "$CCZ" -c -o "$T/b.o" "$3" >/dev/null 2>&1 ||
		{ echo "  $1: compile FAIL"; fail=1; return; }
	if cmp -s "$T/a.o" "$T/b.o"; then echo "  $1 PASS"; else echo "  $1: objects differ FAIL"; fail=1; fi
}
same "ANSI definitions = K&R" "$T/ansi.c" "$T/kr.c"
cat > "$T/c1.c" <<'EOF'
extern long f(long, char *, double, ...);
g(i) { char *p; f(1L, p, 2.0, i); f((long)i, (char *)0, (double)i); }
EOF
sed 1d "$T/c1.c" > "$T/c2.c"
same "matching call = unprototyped" "$T/c1.c" "$T/c2.c"

# Conversions at a call: int to long extends, 0 to a pointer is 32 bits.
cat > "$T/w.c" <<'EOF'
extern f(long, char *);
g(i) { f(i, 0); }
EOF
cat > "$T/w2.c" <<'EOF'
g(i) { f((long)i, (char *)0); }
EOF
same "f(i, 0) = f((long)i, (char *)0)" "$T/w.c" "$T/w2.c"

# Diagnostics.  <want-message> <source>
diag() {
	printf '%s\n' "$2" > "$T/d.c"
	if "$CC0" $VAR "$T/d.c" "$T/d.z0" > "$T/d.err" 2>&1; then
		echo "  diag \"$1\": compiled FAIL"; fail=1
	elif grep -q "$1" "$T/d.err"; then
		echo "  diag \"$1\" PASS"
	else
		echo "  diag \"$1\": FAIL"; cat "$T/d.err"; fail=1
	fi
}
diag "wrong number of arguments" 'int f(int, long); g() { f(1); }'
diag "wrong number of arguments" 'int f(void); g() { f(1); }'
diag "wrong number of arguments" 'int f(char *, ...); g() { f(); }'
diag "argument 2 is not a pointer" 'int f(int, char *); g() { f(1, 2); }'
diag "argument 1 is not arithmetic" 'int f(long); g() { char *p; f(p); }'
diag "argument 1 is not a structure" 'struct s { int a; }; int f(struct s); g() { f(1); }'
diag "\"f\" is being redeclared" 'int f(long); int f(int);'
diag "\"f\" does not match its prototype" 'int f(long); int f(a) int a; { return a; }'
diag "\"f\" does not match its prototype" 'int f(int, int) { return 0; }'
diag "\"x\" is not defined" 'int f(int x); g() { return x; }'

# Accepted: a K&R definition whose promoted types agree with the prototype,
# `()' against a prototype, and a varargs K&R definition.
ok() { # <what> <source>
	printf '%s\n' "$2" > "$T/o.c"
	if "$CC0" $VAR "$T/o.c" "$T/o.z0" > "$T/o.err" 2>&1; then
		echo "  accepts $1 PASS"
	else
		echo "  accepts $1 FAIL"; cat "$T/o.err"; fail=1
	fi
}
ok "K&R after prototype" 'int f(char, float, long); int f(c, x, l) char c; float x; long l; { return c; }'
ok "() and a prototype" 'int f(); int f(int a); int f(); int f(a) { return a; }'
ok "varargs K&R" 'int p(char *, ...); int p(s, a) char *s; { return a; }'
ok "nested declarators" 'int (*signal(int sig, void (*func)(int)))(int); typedef int (*H)(struct h *, void *); struct t { H h; void (*v)(void); } t; int z = sizeof(int (*)(long));'

# -VSVARG (VMBASE+11) warns of an int in a `...' slot, where a tag list wants
# a long, and nothing else; -VSRTVC (bit 3) warns of a pointer or long as a
# condition and not of the `...' slot.  Neither changes the code.
printf '%s\n' 'int p(char *, ...); char *q; long l; g(i) { p("x", i, 1L, (long)i); if (q) i++; while (l) l--; }' > "$T/v.c"
warns() { # <variant> <stem>
	"$CC0" $1 "$T/v.c" "$T/$2.z0" > "$T/$2.err" 2>&1 || true
}
warns $VAR v0
warns 800000020820 va
warns 880000020800 vt
warns 880000020820 vb
nva=$(grep -c "int argument 2 in a variable argument list" "$T/va.err" || true)
nvt=$(grep -c "risky type in truth context" "$T/vt.err" || true)
if [ ! -s "$T/v0.err" ]; then
	echo "  default: no strict warning PASS"
else
	echo "  default: no strict warning FAIL"; cat "$T/v0.err"; fail=1
fi
if [ "$nva" = 1 ] && [ $(grep -c . "$T/va.err") = 1 ]; then
	echo "  -VSVARG int in ... PASS"
else
	echo "  -VSVARG int in ... FAIL"; cat "$T/va.err"; fail=1
fi
if [ "$nvt" = 2 ] && [ $(grep -c . "$T/vt.err") = 2 ]; then
	echo "  -VSRTVC truth contexts only PASS"
else
	echo "  -VSRTVC truth contexts only FAIL"; cat "$T/vt.err"; fail=1
fi
if [ $(grep -c . "$T/vb.err") = 3 ]; then
	echo "  -VSRTVC -VSVARG both PASS"
else
	echo "  -VSRTVC -VSVARG both FAIL"; cat "$T/vb.err"; fail=1
fi
if cmp -s "$T/v0.z0" "$T/va.z0"; then
	echo "  -VSVARG same code PASS"
else
	echo "  -VSVARG same code FAIL"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== proto: FAIL ==="; exit 1; }
echo "=== proto: PASS ==="
