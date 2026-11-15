#!/bin/sh
# bytearg.sh -- a byte constant argument is pushed as the int it promotes to.
#
# `f(p, (unsigned char)5, q)' folds to a byte constant, and so do the arms
# of `(unsigned char)(c ? 5 : 0)' and `(unsigned char)!c', where the cast is
# carried into them.  Pushed from the literal pool it took a one-byte entry
# there, and every pool entry after it sat at an odd address: a far pointer
# with a relocation that a loader refuses, a double read from the wrong word.
# The constant is pushed as an immediate, zero- or sign-extended by its type,
# so the pool holds no byte and every word or long it holds is word-aligned.
# A zero was never pooled and keeps its CLR, unless it is an arm of a
# conditional whose arms are all constants.  Each case checks the shape and
# runs.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"; CC1="$BUILD/z8001/cc1-z8001"
CC2="$BUILD/z8001/cc2-z8001"; DIS="$BUILD/tools/loutdis"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

# Each function pools a pointer after its byte constant, so an odd entry
# shows as an odd operand in the same function.
cat > "$T/f.c" <<'EOF'
extern f();
extern int pf(char *, unsigned char, char *);
char b1[4], b2[4], b3[4];
long lg;
u_arg()  { f(b1, (unsigned char)0xAA, b2); f(b3, &lg); }
c_arg()  { f(b1, (char)-3, b2); f(b3, &lg); }
s_arg()  { f(b1, (signed char)0xAA, b2); f(b3, &lg); }
many()   { f((unsigned char)1, (unsigned char)0xFF, (signed char)-1, (char)0x80, b1); f(b3, &lg); }
comma(x) { f(b1, (x, (unsigned char)4), b2); f(b3, &lg); }
proto()  { pf(b1, (unsigned char)0xAA, b2); f(b3, &lg); }
zero()   { f(b1, (unsigned char)0, b2); f(b3, &lg); }
q_u(x)   { f(b1, (unsigned char)(x ? 5 : 0), b2); f(b3, &lg); }
q_c(x)   { f(b1, (char)(x ? -3 : 7), b2); f(b3, &lg); }
q_s(x)   { f(b1, (signed char)(x ? 0xAA : 9), b2); f(b3, &lg); }
q_nest(x, y) { f(b1, (unsigned char)(x ? (y ? 1 : 0xFF) : 3), b2); f(b3, &lg); }
q_mix(x, p) unsigned char *p; { f(b1, (unsigned char)(x ? 5 : *p), b2); f(b3, &lg); }
q_comma(x) { f(b1, (unsigned char)(x ? (lg++, 4) : 0), b2); f(b3, &lg); }
q_outer(x) { f(b1, (lg++, (unsigned char)(x ? 4 : 6)), b2); f(b3, &lg); }
q_proto(x) { pf(b1, (unsigned char)(x ? 0xAA : 0), b2); f(b3, &lg); }
q_truth(x, y) { f(b1, (unsigned char)!x, (char)(x > y), b2); f(b3, &lg); }
q_lvo(x) { (*(void (*)())(b1 - 342))(b1, b2, (unsigned char)(x ? 5 : 0));
	(*(void (*)())(b1 - 30))(b1, "xy", "zw"); }
EOF
"$CC0" $VAR "$T/f.c" "$T/f.z0" && "$CC1" $VAR "$T/f.z0" "$T/f.z1" &&
"$CC2" 0012 "$T/f.z1" "$T/f.o" "$T/f.scr" 0 || { echo "  bytearg: compile FAIL"; exit 1; }

shape() { # <fn> <immediate>...
	fn=$1; shift
	d=$("$DIS" -v -fn "$fn" "$T/f.o" 2>/dev/null) || true
	[ -n "$d" ] || { echo "  $fn: no disassembly FAIL"; fail=1; return; }
	why=""
	printf '%s\n' "$d" | grep -Eq 'LDB +RL[0-7],0x[0-9A-F]+:0x' &&
		why="byte read from the pool"
	odd=$(printf '%s\n' "$d" | grep -E '0x[0-9A-F]+:0x[0-9A-F]*[13579BDF]\b' |
		grep -Ev '^ +[0-9a-f]+: +LDB ' | head -1)
	[ -z "$odd" ] || why="${why:+$why; }odd pool entry [$odd]"
	for k in "$@"; do
		printf '%s\n' "$d" | grep -Eq "PUSH +@R15,#$k\$" ||
			why="${why:+$why; }no PUSH #$k"
	done
	if [ -z "$why" ]; then
		printf '  %-8s immediate, pool aligned PASS\n' "$fn"
	else
		printf '  %-8s FAIL: %s\n' "$fn" "$why"
		printf '%s\n' "$d" | sed 's/^/      /'
		fail=1
	fi
}
shape u_arg_ 0x00AA
shape c_arg_ 0xFFFD
shape s_arg_ 0xFFAA
shape many_ 0x0001 0x00FF 0xFFFF 0xFF80
shape comma_ 0x0004
shape proto_ 0x00AA
shape q_u_ 0x0005 0x0000
shape q_c_ 0xFFFD 0x0007
shape q_s_ 0xFFAA 0x0009
shape q_nest_ 0x0001 0x00FF 0x0003
shape q_mix_ 0x0005
shape q_comma_ 0x0004 0x0000
shape q_outer_ 0x0004 0x0006
shape q_proto_ 0x00AA 0x0000
shape q_truth_ 0x0001 0x0000
shape q_lvo_ 0x0005 0x0000
if "$DIS" -v -fn zero_ "$T/f.o" 2>/dev/null | grep -A1 -E 'CLR +R0$' | grep -Eq 'PUSH +@R15,R0$'; then
	echo "  zero_    cleared in a register PASS"
else
	echo "  zero_    FAIL: no CLR R0, PUSH R0"
	"$DIS" -v -fn zero_ "$T/f.o" 2>/dev/null | sed 's/^/      /'
	fail=1
fi

# Every word or long operand in the object, pool or not, is at an even address.
[ -x "$DIS" ] || { echo "  bytearg: no $DIS"; exit 2; }
odd=$("$DIS" -v "$T/f.o" 2>/dev/null | grep -E '0x[0-9A-F]+:0x[0-9A-F]*[13579BDF]\b' |
	grep -Ev '^ +[0-9a-f]+: +LDB ' || true)
if [ -z "$odd" ]; then
	echo "  object   no odd word operand PASS"
else
	echo "  object   FAIL: odd word operands"; printf '%s\n' "$odd" | sed 's/^/      /'
	fail=1
fi

# One byte constant alone in its object, as SetAPen(rp, c ? 5 : 0) through
# a `(UBYTE)(pen)' macro spells it, leaves the strings after it odd.
cat > "$T/a.c" <<'EOF'
char *GfxBase;
lvo(rp, c) char *rp; int c;
{
	(*(void (*)())(GfxBase - 342))(GfxBase, rp, (unsigned char)(c ? 5 : 0));
	(*(void (*)())(GfxBase - 30))(GfxBase, "xy", "zw");
}
EOF
"$CC0" $VAR "$T/a.c" "$T/a.z0" && "$CC1" $VAR "$T/a.z0" "$T/a.z1" &&
"$CC2" 0012 "$T/a.z1" "$T/a.o" "$T/a.scr" 0 || { echo "  bytearg: compile FAIL"; exit 1; }
odd=$("$DIS" -v "$T/a.o" 2>/dev/null | grep -E '0x[0-9A-F]+:0x[0-9A-F]*[13579BDF]\b' |
	grep -Ev '^ +[0-9a-f]+: +LDB ' || true)
if [ -z "$odd" ]; then
	echo "  alone    no odd word operand PASS"
else
	echo "  alone    FAIL: odd word operands"; printf '%s\n' "$odd" | sed 's/^/      /'
	fail=1
fi

# ... and the values the callee receives.  A pooled double after each byte
# constant has no relocation; it is read from its entry.
[ -n "$N2" ] || { echo "  bytearg: no guest runner"; exit 2; }
cat > "$T/r.c" <<'EOF'
#include <stdio.h>
char b1[4], b2[4], b3[4];
struct s { char c; long l; char d; char *p; } st = { (unsigned char)5, 70000L, (char)-1, b2 };
unsigned char ua[] = { (unsigned char)1, (unsigned char)0xAA, 3 };
show(p, c, q, d) char *p; int c; char *q; double d;
{
	printf("%d %d %d %ld|", (int)(p - b1), c, (int)(q - b1), (long)(d * 4));
}
show4(a, b, c, d, p) int a, b, c, d; char *p;
{
	printf("%d %d %d %d %d|", a, b, c, d, (int)(p - b1));
}
unsigned char ub = 0xC8;
char cb = -2;
long lg;
quest(x, y) int x, y;
{
	show(b1, (unsigned char)(x ? 0xAA : 0), b2, 1.5);
	show(b2, (char)(x ? -3 : 0x81), b3, 2.25);
	show(b3, (unsigned char)(x ? (y ? 1 : 0xFF) : 3), b1, -0.75);
	show(b1, (unsigned char)(x ? 5 : ub), b2, 0.5);
	show(b2, (char)(x ? cb : -7), b3, 3.0);
	show(b3, (x, (signed char)(y ? 0 : 0xF0)), b1, 1.0);
	show4((unsigned char)!x, (char)(x > y), (unsigned char)(x ? 0 : 0),
		(char)(y ? (x ? 0x80 : 0) : 9), b2);
	lg = (unsigned char)(x ? 200 : 0);
	printf("%ld ", lg);
	lg = (char)(x ? 200 : 1);
	printf("%ld|", lg);
}
main()
{
	int x;
	x = 1;
	quest(1, 0);
	quest(0, 1);
	show(b1, (unsigned char)0xAA, b2, 1.5);
	show(b2, (char)-3, b3, 2.25);
	show(b3, (signed char)0xAA, b1, -0.75);
	show4((unsigned char)1, (unsigned char)0xFF, (signed char)-1, (char)0x80, b3);
	show(b1, (x, (unsigned char)200), b3, 3.0);
	show(b2, (unsigned char)0, b1, 0.5);
	printf("%d %ld %d %d %d %d %d %d\n", st.c, st.l, st.d, (int)(st.p - b1),
		(int)sizeof ua, ua[0], ua[1], ua[2]);
	return 0;
}
EOF
"$CCZ" -o "$T/r" "$T/r.c" >/dev/null 2>&1 || { echo "  bytearg: link FAIL"; exit 1; }
got=$("$N2" -runexec "$T/r" 2>/dev/null) || true
want="0 170 4 6|4 -3 8 9|8 255 0 -3|0 5 4 2|4 -2 8 12|8 -16 0 4|0 1 0 9 4|200 -56|0 0 4 6|4 -127 8 9|8 3 0 -3|0 200 4 2|4 -7 8 12|8 0 0 4|1 0 0 0 4|0 1|0 170 4 6|4 -3 8 9|8 -86 0 -3|1 255 -1 -128 8|0 200 8 12|4 0 0 2|5 70000 -1 4 3 1 170 3"
if [ "$got" = "$want" ]; then
	echo "  values   PASS"
else
	echo "  values   FAIL got=[$got] want=[$want]"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== bytearg: FAIL ==="; exit 1; }
echo "=== bytearg: PASS ==="
