#!/bin/sh
# regvar.sh -- which values live in a callee-saved register across statements.
#
# A `register long' gets a pair.  An undeclared local gets a register too,
# unless its address is taken, a long jump can re-enter the function, or it is
# in an inner block.  Parameters never do: a system call's trap frame is a
# parameter list, and a register would not write back to it.
#
# Shape cases take no parameter, so the only frame traffic is the local.  Each
# case checks the shape and runs.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"; CC1="$BUILD/z8001/cc1-z8001"
CC2="$BUILD/z8001/cc2-z8001"; DIS="$BUILD/tools/loutdis"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/f.c" <<'EOF'
extern sink(), use(), setjmp();
int gn, jb[24];

lcl() {				/* a long local: a pair */
	register long a;
	a = 0;
	while (gn-- > 0) {
		sink();
		a = a + 3;
	}
	return (int)a;
}
par(a) register long a; {	/* a long parameter: the frame */
	a = a + 1;
	sink();
	return (int)a;
}
plain() {			/* an undeclared local: a register */
	int a;
	a = 0;
	while (gn-- > 0) {
		sink();
		a = a + 3;
	}
	return a;
}
taken() {			/* ... unless its address is taken, later */
	int a;
	a = 0;
	while (gn-- > 0) {
		sink();
		a = a + 3;
	}
	use(&a);
	return a;
}
jumped() {			/* ... or a long jump can re-enter */
	int a;
	a = 0;
	if (setjmp(jb) == 0)
		a = a + gn;
	sink();
	return a;
}
inner() {			/* an inner block's local keeps the frame */
	int r;
	r = 0;
	if (gn > 0) {
		int a;
		a = gn;
		sink();
		r = a;
	}
	return r;
}
EOF
"$CC0" $VAR "$T/f.c" "$T/f.z0" && "$CC1" $VAR "$T/f.z0" "$T/f.z1" &&
"$CC2" 0012 "$T/f.z1" "$T/f.o" "$T/f.scr" 0 || { echo "  regvar: compile FAIL"; exit 1; }

shape() { # <fn> <want-a-register 1|0>
	d=$("$DIS" -v -fn "$1" "$T/f.o" 2>/dev/null)
	if printf '%s\n' "$d" | grep -Eq '0x[0-9A-F]+:0x[0-9A-F]+\(R13\)'; then
		got=0
	else
		got=1
	fi
	if [ "$got" = "$2" ]; then
		printf '  %-10s %s PASS\n' "$1" "$([ "$2" = 1 ] && echo register || echo frame)"
	else
		printf '  %-10s want=%s got=%s FAIL\n' "$1" "$2" "$got"
		printf '%s\n' "$d" | sed 's/^/      /'
		fail=1
	fi
}
shape lcl_ 1
shape plain_ 1
shape par_ 0
shape taken_ 0
shape jumped_ 0
shape inner_ 0

# ... and the values: a parameter rewritten across a call, an address taken
# after the last plain use, a value across a calling loop, two pairs through
# the RQ0 multiply.

[ -n "$N2" ] || { echo "  regvar: no guest runner"; exit 2; }
cat > "$T/r.c" <<'EOF'
#include <stdio.h>
long acc;
bump(p) long *p; { *p += 100; }
add(p) int *p; { *p += 7; }
sink() { acc += 1; }

parm(a, b) register long a; register int b; {	/* written, read after a call */
	a = a + 1;
	b = b + 1;
	sink();
	return a * 1000 + b;
}
addr(n) int n; {				/* addresses taken, later */
	register long a;
	long z;
	int k;
	a = 5;
	z = a;
	k = n;
	while (n-- > 0)
		k = k + 1;
	bump(&z);
	add(&k);
	return (int)(a + z) + k;
}
prod(x) unsigned x; {				/* two pairs through the multiply */
	register unsigned long a;
	register unsigned long b;
	a = x; a = a * 100000;
	b = x; b = b * 50000;
	return a > b;
}
loop(n) int n; {				/* live across a calling loop */
	register long a;
	register long b;
	int c;
	a = 1; b = 2; c = 0;
	while (n-- > 0) {
		sink();
		a = a + b;
		b = b + 1;
		c = c + 2;
	}
	return (int)(a * 10 + b) + c;
}
main() {
	long p; int q, r, t; unsigned v;
	v = 40000;
	p = parm(7L, 8);
	q = addr(3);
	r = loop(4);
	t = prod(v);
	printf("%ld %d %d %d %ld\n", p, q, r, t, acc);
}
EOF
"$CCZ" -o "$T/r" "$T/r.c" >/dev/null 2>&1 || { echo "  regvar: link FAIL"; exit 1; }
got=$("$N2" -runexec "$T/r" 2>/dev/null) || true
want="8009 123 164 1 5"
if [ "$got" = "$want" ]; then
	echo "  values     PASS"
else
	echo "  values     FAIL got=[$got] want=[$want]"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== regvar: FAIL ==="; exit 1; }
echo "=== regvar: PASS ==="
