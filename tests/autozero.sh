#!/bin/sh
# autozero.sh -- an automatic aggregate's members left out of its initializer are zero.
#
# `struct N n[] = { { 1, (char *)10, 0, 3 }, { 2 } };' must leave n[1].l, .k
# and .f zero, as a static's are (C89 3.5.7, and K&R's rule for the
# aggregates it let be initialized).  So must the rest of a structure, the
# elements an array's list stops short of, the bytes after a string's NUL, a
# member union, nested aggregates and the elements of an array sized by its
# initializer, at every level.  The gaps are cleared after the stores, a word
# CLR each, or past five words one CLR and an LDIR; when clearing the whole
# object first is the shorter code, the clear comes first and the stores of a
# constant 0 go.  A fully initialized aggregate compiles as before.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"; CC1="$BUILD/z8001/cc1-z8001"
CC2="$BUILD/z8001/cc2-z8001"; DIS="$BUILD/tools/loutdis"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/h.h" <<'EOF'
struct N { unsigned char t; char *l; char *k; short f; };
struct R { short a, b; };
struct O { int k; struct R r; char s[5]; long z; };
struct B { unsigned x:3, y:5; int z; unsigned w:4; };
union U { long l; short h[2]; };
struct V { char c; struct R r[2]; union U u; };
struct G { int a[20]; char c; };
struct M { unsigned char t; char *l; char *k; unsigned short f; long m; char *d; };
extern long hN(), hR(), hO(), hB(), hV(), hG(), hM(), hs(), ha(), hl();
EOF
# K&R: bounded aggregates only.
cat > "$T/k.c" <<'EOF'
#include "h.h"
long k1() { struct R r = {1}; return hR(&r, 1); }
long k2() { struct O o = { 1, { 2 } }; return hO(&o); }
long k3() { struct O o = { 1, 2, 3, "ab" }; return hO(&o); }
long k4() { int a[7] = { 1, 2 }; return ha(a, 7); }
long k5() { char s[8] = "ab"; return hs(s, 8); }
long k6() { char s[40] = "x"; return hs(s, 40); }
long k7() { struct V v = { 'v' }; return hV(&v); }
long k8() { struct V v = { 'v', { { 1 } } }; return hV(&v); }
long k9() { struct B b = { 1, 2 }; return hB(&b); }
long k10() { int m[3][4] = { { 1 }, { 2, 3 } }; return ha(m, 12); }
long k11() { struct G g = { { 1 } }; return hG(&g); }
long k12() { struct G g = { { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 } }; return hG(&g); }
long k13() { char c = 1; char s[5] = "a"; char d = 2; return hs(s, 5) + c + d; }
long k14() { char c = 1; char s[30] = "a"; return hs(s, 30) + c; }
long k15() { char a[2][5] = { "x", "yz" }; return hs(a, 10); }
long k16() { register struct R r = { 4 }; return r.a * 5 + r.b; }
long k17() { volatile struct R r = { 0 }; return hR(&r, 1); }
long k18(n) { int i = n; { struct O o = { i }; return hO(&o); } }
long k19() { struct M m[4] = { { 1, "a", "b", 0, 0, 0 }, { 2, 0 }, { 3 }, { 4, "c" } }; return hM(m, 4); }
long k20() { char c = 3; char s[7] = { 'p' }; struct { char a; char b[4]; } q = { 1, { 2 } }; return hs(s, 7) + q.a * 7 + hs(q.b, 4) + c; }
long k21() { char s[3] = "abc"; return hs(s, 3); }
EOF
# C89: arrays sized by their initializer and structures from an expression.
cat > "$T/c.c" <<'EOF'
#include "h.h"
long c1() { struct N n[] = { {1, (char *)10, 0, 3}, {2} }; return hN(n, 2); }
long c2(p) struct R *p; { struct R r[3] = { *p }; return hR(r, 3); }
long c3(p) struct R *p; { struct R r[] = { { 9 }, *p, { 7 } }; return hR(r, 3); }
long c4(n) { long a[] = { n, 0, n }; struct R r[2] = { { n, 0 } }; return hl(a, 3) + hR(r, 2); }
long c5() { struct N n[] = { {1, (char *)10, 0, 3}, {2}, {3}, {4}, {5}, {6, 0, 0, 7} }; return hN(n, 6); }
long c6() { char s[] = "abc"; int a[] = { 1, 2 }; struct R r = { 1, 2 }; return hs(s, 4) + ha(a, 2) + hR(&r, 1); }
long c7() { struct R r = { }; return hR(&r, 1); }
EOF
cat > "$T/main.c" <<'EOF'
#include "h.h"
extern printf();
long mix(h, v) long h, v; { return (h * 31 + v) & 0xFFFFFFL; }
long hp(p) char *p; { return p == 0 ? 0 : (unsigned long)p < 256 ? (long)p : 1000 + *p; }
long hN(p, n) struct N *p; { long h = 0; for (; n-- > 0; p++) h = mix(mix(mix(mix(h, (long)p->t), hp(p->l)), hp(p->k)), (long)p->f); return h; }
long hR(p, n) struct R *p; { long h = 0; for (; n-- > 0; p++) h = mix(mix(h, (long)p->a), (long)p->b); return h; }
long hs(p, n) char *p; { long h = 0; while (n-- > 0) h = mix(h, (long)*p++); return h; }
long ha(p, n) int *p; { long h = 0; while (n-- > 0) h = mix(h, (long)*p++); return h; }
long hl(p, n) long *p; { long h = 0; while (n-- > 0) h = mix(h, *p++); return h; }
long hO(p) struct O *p; { return mix(mix(mix((long)p->k, hR(&p->r, 1)), hs(p->s, 5)), p->z); }
long hB(p) struct B *p; { return mix(mix(mix((long)p->x, (long)p->y), (long)p->z), (long)p->w); }
long hV(p) struct V *p; { return mix(mix((long)p->c, p->u.l), hR(p->r, 2)); }
long hG(p) struct G *p; { return mix(ha(p->a, 20), (long)p->c); }
long hM(p, n) struct M *p; { long h = 0; for (; n-- > 0; p++) h = mix(mix(mix(mix(mix(mix(h, (long)p->t), hp(p->l)), hp(p->k)), (long)p->f), p->m), hp(p->d)); return h; }
dirty() { unsigned char b[600]; int i; for (i = 0; i < 600; i++) b[i] = 0xA5 + i; return b[3]; }
extern long k1(), k2(), k3(), k4(), k5(), k6(), k7(), k8(), k9(), k10(), k11();
extern long k12(), k13(), k14(), k15(), k16(), k17(), k18(), k19(), k20(), k21();
#define T(e) (dirty(), e)
pk() {
	printf("%ld %ld %ld %ld %ld %ld %ld %ld %ld %ld %ld\n", T(k1()), T(k2()), T(k3()), T(k4()),
	    T(k5()), T(k6()), T(k7()), T(k8()), T(k9()), T(k10()), T(k11()));
	printf("%ld %ld %ld %ld %ld %ld %ld %ld %ld %ld\n", T(k12()), T(k13()), T(k14()), T(k15()),
	    T(k16()), T(k17()), T(k18(6)), T(k19()), T(k20()), T(k21()));
}
EOF
cat > "$T/mk.c" <<'EOF'
main() { pk(); return 0; }
EOF
cat > "$T/mc.c" <<'EOF'
#include "h.h"
extern printf();
extern long c1(), c2(), c3(), c4(), c5(), c6(), c7();
#define T(e) (dirty(), e)
main() {
	struct R x;
	x.a = 3; x.b = 4;
	pk();
	printf("%ld %ld %ld %ld %ld %ld %ld\n", T(c1()), T(c2(&x)), T(c3(&x)), T(c4(5)),
	    T(c5()), T(c6()), T(c7()));
	return 0;
}
EOF

# Values, against the host compiler, with the stack dirtied before each call.
[ -n "$N2" ] || { echo "  autozero: no guest runner"; exit 2; }
want=$(cd "$T" && gcc -std=gnu89 -w -o host main.c mc.c k.c c.c && ./host | tr -d '\r')
wantk=$(printf '%s\n' "$want" | sed 2q)
run() { # <what> <want> <level> <sources...>
	what=$1; w=$2; lv=$3; shift 3
	if (cd "$T" && CCZ_LEVEL=$lv "$CCZ" -o "$T/m" "$@" >/dev/null 2>&1); then
		got=$("$N2" -runexec "$T/m" 2>/dev/null) || true
		if [ "$got" = "$w" ]; then
			echo "  $what values PASS"
		else
			echo "  $what values: want [$w] got [$got] FAIL"; fail=1
		fi
	else
		echo "  $what: compile FAIL"; fail=1
	fi
}
run "default level" "$want" "" main.c mc.c k.c c.c
run "-VKR" "$wantk" KR main.c mk.c k.c
run "-VC89" "$want" C89 main.c mc.c k.c c.c

# Same object: a few gaps are the stores of zero they mean, and a full
# initializer is its assignments.
cat > "$T/i.c" <<'EOF'
struct R { short a, b; };
struct S { char c; long l; char *p; };
extern g();
f1() { struct R r = { 1, 2 }; return g(&r); }
f2() { struct R r = { 1 }; return g(&r); }
f3() { int a[3] = { 5 }; return g(a); }
f4() { struct S s = { 'x' }; return g(&s); }
f5() { struct R r[2] = { { 1 }, { 2 } }; return g(r); }
f6() { struct R r = { }; return g(&r); }
EOF
cat > "$T/a.c" <<'EOF'
struct R { short a, b; };
struct S { char c; long l; char *p; };
extern g();
f1() { struct R r; r.a = 1; r.b = 2; return g(&r); }
f2() { struct R r; r.a = 1; r.b = 0; return g(&r); }
f3() { int a[3]; a[0] = 5; a[1] = 0; a[2] = 0; return g(a); }
f4() { struct S s; s.c = 'x'; s.l = 0; s.p = 0; return g(&s); }
f5() { struct R r[2]; r[0].a = 1; r[0].b = 0; r[1].a = 2; r[1].b = 0; return g(r); }
f6() { struct R r; r.a = 0; r.b = 0; return g(&r); }
EOF
if "$CCZ" -c -o "$T/i.o" "$T/i.c" >/dev/null 2>&1 && "$CCZ" -c -o "$T/a.o" "$T/a.c" >/dev/null 2>&1 &&
   cmp -s "$T/i.o" "$T/a.o"; then
	echo "  initialization = stores of zero PASS"
else
	echo "  initialization = stores of zero: objects differ FAIL"; fail=1
fi

# Shapes.  <fn> <LDIR count> <CLR/CLRB count> <LD count>
cat > "$T/s.c" <<'EOF'
struct N { unsigned char t; char *l; char *k; short f; };
extern g();
odd() { char s[4] = "a"; return g(s); }
inl() { int a[6] = { 1 }; return g(a); }
blk() { int a[20] = { 1, 2 }; return g(a); }
str() { char s[40] = "x"; return g(s); }
whole() { struct N n[] = { {1, (char *)10, 0, 3}, {2}, {3}, {4}, {5}, {6, 0, 0, 7} }; return g(n); }
full() { struct N n[2] = { {1, (char *)10, 0, 3}, {2, 0, 0, 4} }; return g(n); }
EOF
"$CC0" $VAR "$T/s.c" "$T/s.z0" && "$CC1" $VAR "$T/s.z0" "$T/s.z1" &&
"$CC2" 0012 "$T/s.z1" "$T/s.o" "$T/s.scr" 0 || { echo "  autozero: shapes compile FAIL"; exit 1; }
shape() {
	d=$("$DIS" -v -fn "$1" "$T/s.o" 2>/dev/null) || true
	nb=$(printf '%s\n' "$d" | grep -Ec ' LDIR ' || true)
	nc=$(printf '%s\n' "$d" | grep -Ec ' CLRB? ' || true)
	nl=$(printf '%s\n' "$d" | grep -Ec ' LDB? +0x' || true)
	nm=$(printf '%s\n' "$d" | grep -Ec ' LDM ' || true)
	if [ "$nb.$nc.$nl.$nm" = "$2.$3.$4.0" ]; then
		printf '  %-6s %s LDIR, %s CLR, %s stores PASS\n' "$1" $2 $3 $4
	else
		printf '  %-6s FAIL: %s LDIR, %s CLR, %s stores, %s LDM; want %s, %s, %s, 0\n' "$1" $nb $nc $nl $nm $2 $3 $4
		printf '%s\n' "$d" | sed 's/^/      /'; fail=1
	fi
}
shape odd_ 0 2 1	# s[0]; CLRB s[1], CLR s[2..3]
shape inl_ 0 5 1	# five words inline
shape blk_ 1 1 2	# CLR a[2], LDIR a[3..19]
shape str_ 1 1 1	# the whole clear first, then 'x'; its NUL goes
shape whole_ 1 1 10	# the whole clear first; the stores of 0 go
shape full_ 0 6 6	# as before: each member stored, the zeros CLR

[ "$fail" = 0 ] || { echo "=== autozero: FAIL ==="; exit 1; }
echo "=== autozero: PASS ==="
