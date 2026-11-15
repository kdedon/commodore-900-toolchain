#!/bin/sh
# structinit.sh -- an automatic structure initialized from a structure expression.
#
# `struct R o = e;' with e a structure or union of the same type -- `*p', another
# local, a function's value, a conditional -- is the assignment `o = e' and must
# compile to the same object as `struct R o; o = e;'.  So must a member of a
# brace list initialized from such an expression.  The brace-less list of
# members (`struct R o = 1, 2;') and every brace initializer keep the code they
# had, as do static structures.  A structure of another type is a type clash.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

# Initialization (i.c) and the assignments it means (a.c), function by function.
cat > "$T/i.c" <<'EOF'
typedef struct R { short a, b; } RT;
union U { long l; short h; };
struct O { int k; struct R r; };
struct R gr;
struct R mk(a) { struct R t; t.a = a; t.b = -a; return t; }
int f1(p) struct R *p; { struct R o = *p; return o.a; }
int f2(p) struct R *p; { struct R q; q = *p; { struct R o = q; return o.b; } }
int f3(n) { struct R o = mk(n); return o.a - o.b; }
int f4(c, x, y) struct R *x, *y; { struct R o = c ? *x : *y; return o.b; }
int f5() { struct R o = gr, o2 = o; return o2.a; }
int f6(p) RT *p; { RT o = *p; struct R o2 = o; return o2.a + o2.b; }
long f7(p) union U *p; { union U u = *p; return u.l; }
int f8(n, p) struct R *p; { struct O o = { n, *p }; return o.k + o.r.b; }
int f9(p) struct R *p; { register struct R o = *p; return o.b; }
EOF
cat > "$T/a.c" <<'EOF'
typedef struct R { short a, b; } RT;
union U { long l; short h; };
struct O { int k; struct R r; };
struct R gr;
struct R mk(a) { struct R t; t.a = a; t.b = -a; return t; }
int f1(p) struct R *p; { struct R o; o = *p; return o.a; }
int f2(p) struct R *p; { struct R q; q = *p; { struct R o; o = q; return o.b; } }
int f3(n) { struct R o; o = mk(n); return o.a - o.b; }
int f4(c, x, y) struct R *x, *y; { struct R o; o = c ? *x : *y; return o.b; }
int f5() { struct R o, o2; o = gr; o2 = o; return o2.a; }
int f6(p) RT *p; { RT o; struct R o2; o = *p; o2 = o; return o2.a + o2.b; }
long f7(p) union U *p; { union U u; u = *p; return u.l; }
int f8(n, p) struct R *p; { struct O o; o.k = n; o.r = *p; return o.k + o.r.b; }
int f9(p) struct R *p; { register struct R o; o = *p; return o.b; }
EOF
# The older forms: a brace-less member list, brace lists, statics.
cat > "$T/l.c" <<'EOF'
struct R { short a, b; };
struct B { unsigned x:3, y:5; int z; };
struct O { int k; struct R r; char s[4]; };
struct P { char *p; int n; };
int l1() { struct R o = 1; return o.a; }
int l2() { struct R o = 1, 2; return o.b; }
int l3() { struct B b = 3, 4, 5; return b.z + b.y; }
int l4(n) { struct O o = { n, 2, 3, "ab" }; return o.r.b + o.s[1]; }
int l5(n) { struct O o = { n, { 2, 3 }, 'x' }; return o.r.b + o.s[0]; }
int l6() { struct P p = "abc", 4; return p.n + p.p[1]; }
int l7(n) { struct { struct R r; int z; } o = { n, n+1, n+2 }; return o.r.a + o.r.b + o.z; }
static struct R sr = { 1, 2 };
int l8() { static struct R s = { 5, 6 }; return s.a + sr.b; }
EOF
cat > "$T/la.c" <<'EOF'
struct R { short a, b; };
struct B { unsigned x:3, y:5; int z; };
struct O { int k; struct R r; char s[4]; };
struct P { char *p; int n; };
int l1() { struct R o; o.a = 1; return o.a; }
int l2() { struct R o; o.a = 1; o.b = 2; return o.b; }
EOF

# Same object: each initialization and its assignment.
same() { # <what> <a.c> <b.c>
	"$CCZ" -c -o "$T/a.o" "$2" >/dev/null 2>&1 && "$CCZ" -c -o "$T/b.o" "$3" >/dev/null 2>&1 ||
		{ echo "  $1: compile FAIL"; fail=1; return; }
	if cmp -s "$T/a.o" "$T/b.o"; then echo "  $1 PASS"; else echo "  $1: objects differ FAIL"; fail=1; fi
}
same "initialization = assignment" "$T/i.c" "$T/a.c"
sed -n 1,6p "$T/l.c" > "$T/l12.c"
same "member list = member assignments" "$T/l12.c" "$T/la.c"

# Values: the initializations against the host.
cat > "$T/main.c" <<'EOF'
extern printf();
struct R { short a, b; };
union U { long l; short h; };
extern struct R gr;
extern long f7();
main() {
	struct R x, y; union U u;
	x.a = 3; x.b = 4; y.a = 7; y.b = 8; gr.a = 11; gr.b = 12; u.l = 0x12345678L;
	printf("%d %d %d %d %d %d %d %ld %d %d\n", f1(&x), f2(&y), f3(5),
	    f4(1, &x, &y), f4(0, &x, &y), f5(), f6(&y), f7(&u), f8(100, &x), f9(&y));
	printf("%d %d %d %d %d %d %d %d\n", l1(), l2(), l3(), l4(10), l5(10), l6(), l7(20), l8());
	return 0;
}
EOF
[ -n "$N2" ] || { echo "  structinit: no guest runner"; exit 2; }
# The member lists are not C89, so the second line is the compiler's own.
echo 'l1(){return 0;} l2(){return 0;} l3(){return 0;} l4(){return 0;}
l5(){return 0;} l6(){return 0;} l7(){return 0;} l8(){return 0;}' > "$T/stub.c"
want=$(gcc -std=gnu89 -w -o "$T/host" "$T/main.c" "$T/i.c" "$T/stub.c" && "$T/host" | sed 1q)
want="$want
1 2 9 101 123 102 63 7"
if "$CCZ" -o "$T/m" "$T/main.c" "$T/i.c" "$T/l.c" >/dev/null 2>&1; then
	got=$("$N2" -runexec "$T/m" 2>/dev/null) || true
	if [ "$got" = "$want" ]; then
		echo "  values PASS"
	else
		echo "  values: want [$want] got [$got] FAIL"; fail=1
	fi
else
	echo "  structinit: compile FAIL"; fail=1
fi

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
diag 'type clash' 'struct R { short a, b; }; struct S { short a, b; };
f(p) struct S *p; { struct R o = *p; return o.a; }'
diag 'type clash' 'struct R { short a, b; }; struct O { struct R r; int k; };
f(p) struct O *p; { struct R o = *p; return o.a; }'

[ "$fail" = 0 ] || { echo "=== structinit: FAIL ==="; exit 1; }
echo "=== structinit: PASS ==="
