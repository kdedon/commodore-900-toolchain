#!/bin/sh
# addrarray.sh -- `&' of an array.
#
# C89 makes `&a', a an array, a pointer to the array, at the address of its
# first element.  Cast to the element pointer it must compile to the object
# of the decayed `a', for a static, an automatic and a member array (`&p->a',
# `&s.a', offsetof()), a row of a two-dimensional array and a string.  As a
# pointer to the array it steps, compares, dereferences and sizes as one:
# the values are checked against the host compiler's.  offsetof() is an
# integer constant expression, except under -VKR.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

# The address of each array (a.c) and the decayed array (b.c).
cat > "$T/a.c" <<'EOF'
struct S { short a[4]; char c; } s;
struct T { char c; short m[2][3]; };
short b[4];
short m[3][4];
extern clr();
short *f1() { return (short *)&b; }
short *f2(p) struct S *p; { return (short *)&p->a; }
short *f3() { return (short *)&s.a; }
short *f4(i) { return (short *)&m[i]; }
char *f5() { return (char *)&"abc"; }
int f6(i) { short l[4]; l[i] = 3; return clr((char *)&l, sizeof l) + l[0]; }
int f7(p) struct T *p; { return *(short *)&p->m[1]; }
int f8() { return (int)&((struct S *)0)->a; }
char *f9(p) struct S *p; { return (char *)&p->a + 2; }
EOF
sed -e 's/&b;/b;/; s/&p->a;/p->a;/; s/&s\.a/s.a/; s/&m\[i\]/m[i]/; s/&"abc"/"abc"/' \
    -e 's/(char \*)&l,/(char *)l,/; s/&p->m\[1\]/p->m[1]/; s/&((struct S \*)0)->a/((struct S *)0)->a/' \
    -e 's/(char \*)&p->a + 2/(char *)p->a + 2/' "$T/a.c" > "$T/b.c"
if cmp -s "$T/a.c" "$T/b.c"; then
	echo "  addrarray: the decayed source is the same text FAIL"; fail=1
elif "$CCZ" -c -o "$T/a.o" "$T/a.c" >/dev/null 2>&1 && "$CCZ" -c -o "$T/b.o" "$T/b.c" >/dev/null 2>&1; then
	if cmp -s "$T/a.o" "$T/b.o"; then
		echo "  &a cast to the element pointer is a PASS"
	else
		echo "  &a cast to the element pointer: objects differ FAIL"; fail=1
	fi
else
	echo "  addrarray: compile FAIL"; "$CC0" $VAR "$T/a.c" "$T/a.z0" || true; fail=1
fi

cat > "$T/v.c" <<'EOF'
#include <stddef.h>
struct T { char c; short a[3]; char d; short m[2][2]; };
struct S { short a[4]; } s;
short b[4] = { 10, 11, 12, 13 };
short m[3][4];
char buf[6] = "hello";
static size_t om = offsetof(struct T, m);
int clr(p, n) char *p; { int k = 0; while (n-- > 0) { k += *p; *p++ = 0; } return k; }
int f1() { return (char *)(&b + 1) - (char *)b; }
int f2() { return (*&b)[2]; }
int f3() { return (short *)&b == b; }
int f4() { short (*q)[4] = &b; return (*q)[1] + q[0][3]; }
int f5() { return (char *)(&m + 1) - (char *)m; }
int f6() { return &m[1] - &m[0]; }
int f7() { return (char *)(&m[1] + 1) - (char *)m; }
int f8() { return offsetof(struct T, a) * 100 + offsetof(struct T, d) * 10 + offsetof(struct T, m) + om * 1000; }
int f9() { return (short *)&s.a == s.a; }
int f10() { return (*&"abc")[1] + sizeof *&"abc"; }
int f11(p) struct S *p; { return (short *)&p->a == p->a && (char *)(&p->a + 1) - (char *)p == 8; }
int f12() { return clr(&buf, sizeof buf); }
int f13() { short (*rp)[4] = &m[2]; m[2][1] = 7; return (*rp)[1] + (rp == m + 2); }
int f14() { short z[2]; short l[4]; z[0] = 0; return z[0] + ((char *)(&l + 1) - (char *)l) * 10 + (&l == (short (*)[4])l); }
int f15() { return sizeof(&b) == sizeof(short *); }
int f16() { struct T t; t.m[1][0] = 5; return (*&t.m)[1][0]; }
EOF
cat > "$T/main.c" <<'EOF'
extern printf();
struct S { short a[4]; };
extern struct S s;
main() {
	printf("%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n", f1(), f2(), f3(), f4(),
	    f5(), f6(), f7(), f8(), f9(), f10(), f11(&s), f12(), f13(), f14(), f15(), f16());
	return 0;
}
EOF
[ -n "$N2" ] || { echo "  addrarray: no guest runner"; exit 2; }
want=$(gcc -std=gnu89 -w -o "$T/host" "$T/main.c" "$T/v.c" && "$T/host" | tr -d '\r')
if "$CCZ" -o "$T/m" "$T/main.c" "$T/v.c" >/dev/null 2>&1; then
	got=$("$N2" -runexec "$T/m" 2>/dev/null) || true
	if [ "$got" = "$want" ]; then
		echo "  values PASS"
	else
		echo "  values: want [$want] got [$got] FAIL"; fail=1
	fi
else
	echo "  addrarray: link FAIL"; fail=1
fi

# offsetof() is an integer constant expression: an array bound, a case label
# and a static initializer, for a member, a nested member, a member array and
# an element of one.  A false bound is still diagnosed.
cat > "$T/o.c" <<'EOF'
#include <stddef.h>
struct I { char k; short v; };
struct S { short x; short a[4]; char c; struct I in; short m[2][3]; };
typedef char t1[offsetof(struct S, a) == 2 ? 1 : -1];
typedef char t2[offsetof(struct S, in.v) == 14 ? 1 : -1];
typedef char t3[offsetof(struct S, m[1][2]) == 26 ? 1 : -1];
char arr[offsetof(struct S, m)];
static size_t om = offsetof(struct S, a[3]);
int sw(i) { switch (i) { case offsetof(struct S, c): return 1; case offsetof(struct S, in): return 2; } return 0; }
int of() { return sizeof arr * 100 + om * 10 + sw(10) + sw(12) * 2; }
EOF
cat > "$T/om.c" <<'EOF'
extern printf();
main() { printf("%d\n", of()); return 0; }
EOF
want=$(gcc -std=gnu89 -w -o "$T/ohost" "$T/om.c" "$T/o.c" && "$T/ohost" | tr -d '\r')
if "$CCZ" -o "$T/om" "$T/om.c" "$T/o.c" >/dev/null 2>&1; then
	got=$("$N2" -runexec "$T/om" 2>/dev/null) || true
	if [ "$got" = "$want" ]; then
		echo "  offsetof() a constant PASS"
	else
		echo "  offsetof() a constant: want [$want] got [$got] FAIL"; fail=1
	fi
else
	echo "  offsetof() a constant: compile FAIL"
	"$CC0" $VAR "$T/o.c" "$T/o.z0" -I"$H/src/include" || true; fail=1
fi
# Under -VKR offsetof() is not a constant, as in the MWC compiler.
if "$CC0" 800000020840 "$T/o.c" "$T/ok.z0" -I"$H/src/include" > "$T/ok.err" 2>&1; then
	echo "  -VKR offsetof() a constant: compiled FAIL"; fail=1
elif grep -q "array bound must be a constant" "$T/ok.err" &&
     grep -q "int constant expression required" "$T/ok.err"; then
	echo "  -VKR offsetof() not a constant PASS"
else
	echo "  -VKR offsetof() FAIL"; cat "$T/ok.err"; fail=1
fi
printf '#include <stddef.h>\nstruct S { short x; char c; };\ntypedef char t[offsetof(struct S, c) == 3 ? 1 : -1];\n' > "$T/ob.c"
if "$CCZ" -c -o "$T/ob.o" "$T/ob.c" > "$T/ob.err" 2>&1; then
	echo "  offsetof() false bound: compiled FAIL"; fail=1
elif grep -q "array bound must be positive" "$T/ob.err"; then
	echo "  offsetof() false bound PASS"
else
	echo "  offsetof() false bound FAIL"; cat "$T/ob.err"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== addrarray: FAIL ==="; exit 1; }
echo "=== addrarray: PASS ==="
