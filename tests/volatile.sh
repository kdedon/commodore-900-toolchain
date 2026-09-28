#!/bin/sh
# volatile.sh -- a volatile local never lives in a register.
#
# Even if declared `register'.  The same local without the qualifier still gets
# one.  Shape cases take no parameter, so the only frame traffic is the local.
# The qualifier is the object's, not a pointee's, and survives a typedef.
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
extern sink();
typedef volatile int vint;
typedef volatile int *vip;
int gn;

vlcl() {			/* the prime candidate, declined */
	volatile int a;
	a = 0;
	while (gn-- > 0) {
		sink();
		a = a + 3;
	}
	return a;
}
vreg() {			/* ... and the source asking does not help */
	register volatile int a;
	a = 0;
	while (gn-- > 0) {
		sink();
		a = a + 3;
	}
	return a;
}
vlong() {			/* ... nor does a pair */
	volatile long a;
	a = 0;
	while (gn-- > 0) {
		sink();
		a = a + 3;
	}
	return (int)a;
}
plain() {			/* the control: still a register */
	int a;
	a = 0;
	while (gn-- > 0) {
		sink();
		a = a + 3;
	}
	return a;
}
vparm(a) register volatile int a; {	/* a parameter asking is refused too */
	while (gn-- > 0) {
		sink();
		a = a + 3;
	}
	return a;
}
parm(a) register int a; {		/* ... where one not qualified is not */
	while (gn-- > 0) {
		sink();
		a = a + 3;
	}
	return a;
}
vpobj() {			/* a volatile pointer */
	int * volatile p;
	p = 0;
	while (gn-- > 0) {
		sink();
		p = p + 3;
	}
	return (int)p;
}
vtdef() {			/* volatile through a typedef */
	vint a;
	a = 0;
	while (gn-- > 0) {
		sink();
		a = a + 3;
	}
	return a;
}
ptov(q) int *q; {		/* a pointer to volatile is not volatile */
	volatile int *p;
	p = q;
	while (gn-- > 0) {
		sink();
		p = p + 3;
	}
	return *p;
}
tptov(q) int *q; {		/* ... nor through a typedef */
	vip p;
	p = q;
	while (gn-- > 0) {
		sink();
		p = p + 3;
	}
	return *p;
}
EOF
"$CC0" $VAR "$T/f.c" "$T/f.z0" && "$CC1" $VAR "$T/f.z0" "$T/f.z1" &&
"$CC2" 0012 "$T/f.z1" "$T/f.o" "$T/f.scr" 0 || { echo "  volatile: compile FAIL"; exit 1; }

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
shape vlcl_ 0
shape vreg_ 0
shape vlong_ 0
shape plain_ 1
shape vpobj_ 0
shape vtdef_ 0

# A register parameter reads its slot once, a volatile one every time: count.
frames() { # <fn> <most|least> <n>
	n=$("$DIS" -v -fn "$1" "$T/f.o" 2>/dev/null |
	    grep -Ec '0x[0-9A-F]+:0x[0-9A-F]+\(R13\)') || n=0
	if [ "$2" = most ]; then
		ok=$([ "$n" -le "$3" ] && echo 1 || echo 0)
	else
		ok=$([ "$n" -ge "$3" ] && echo 1 || echo 0)
	fi
	if [ "$ok" = 1 ]; then
		printf '  %-10s %s %s frame refs (%s) PASS\n' "$1" "$2" "$3" "$n"
	else
		printf '  %-10s want %s %s got=%s FAIL\n' "$1" "$2" "$3" "$n"; fail=1
	fi
}
frames vparm_ least 3
frames parm_  most  1
frames ptov_  most  1
frames tptov_ most  1

# ... and the values.  C cannot observe a stale register without taking the
# address, which already refuses one, so these only show the forms compute.

[ -n "$N2" ] || { echo "  volatile: no guest runner"; exit 2; }
cat > "$T/r.c" <<'EOF'
#include <stdio.h>
int gn;
sink() { }

vlcl()  { volatile int a;  a = 0; while (gn-- > 0) { sink(); a = a + 3; } return a; }
vreg()  { register volatile int a; a = 0; while (gn-- > 0) { sink(); a = a + 3; } return a; }
vlong() { volatile long a; a = 0; while (gn-- > 0) { sink(); a = a + 3; } return (int)a; }
vpar(a, n) volatile int a; int n; { sink(); while (n-- > 0) a = a + 1; return a; }
vrpar(a, n) register volatile long a; int n; { sink(); while (n-- > 0) a = a + 1; return (int)a; }
typedef volatile int vint;
typedef volatile int *vip;
int arr[16] = { 0, 0, 0, 5, 0, 0, 7 };
vpobj() { int * volatile p; p = arr; while (gn-- > 0) { sink(); p = p + 3; } return *p; }
vtdef() { vint a; a = 0; while (gn-- > 0) { sink(); a = a + 3; } return a; }
ptov()  { volatile int *p; p = arr; while (gn-- > 0) { sink(); p = p + 3; } return *p; }
tptov() { vip p; p = arr; while (gn-- > 0) { sink(); p = p + 3; } *p = *p + 1; return *p; }

main() {
	int p, q, r, s, t, u, v;
	gn = 4; p = vlcl();
	gn = 4; q = vreg();
	gn = 4; r = vlong();
	gn = 1; s = vpobj();
	gn = 4; t = vtdef();
	gn = 2; u = ptov();
	gn = 2; v = tptov();
	printf("%d %d %d %d %d %d %d %d %d\n", p, q, r, vpar(10, 5), vrpar(20L, 5),
	    s, t, u, v);
}
EOF
"$CCZ" -o "$T/r" "$T/r.c" >/dev/null 2>&1 || { echo "  volatile: link FAIL"; exit 1; }
got=$("$N2" -runexec "$T/r" 2>/dev/null) || true
want="12 12 12 15 25 5 12 7 8"
if [ "$got" = "$want" ]; then
	echo "  values     PASS"
else
	echo "  values     FAIL got=[$got] want=[$want]"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== volatile: FAIL ==="; exit 1; }
echo "=== volatile: PASS ==="
