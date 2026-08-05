#!/bin/sh
# regclob.sh [cc2-peep-flags] -- does a `register' variable survive a call?
# Compiles a two-function program through cc0->cc1->cc2-z8001, links it, and
# runs it; R1 holds f()'s return value.
set -u
H=$(cd "$(dirname "$0")/.." && pwd)
B="${C900_BUILD:-$H/host/build}"	# the lane's build dir; see host/publish.sh
O="$B/z8001"; AS="$B/as-z8001"
LD="$B/ld-z8001"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000000800; PEEP="${1:-0010}"
# Every case's verdict has to reach the exit status.  Both bad paths below --
# a build that did not produce a binary, and a binary that returned the wrong
# value -- used to be a bare `echo', and `return' with no argument yields the
# status of that echo, which is 0.  The script's own status was then whatever
# the LAST run() left behind, so six register-clobber assertions could all
# report WRONG and the caller (tests/check.sh) would read a pass.
FAIL=0
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '\t.globl\tSS\nSS = 0\n' > "$T/ss.s"; "$AS" -o "$T/ss.o" "$T/ss.s" 2>/dev/null

run() {	# run <name> <expected> <source>
	name=$1; want=$2; src=$3
	printf '%s' "$src" > "$T/t.c"
	"$O/cc0-z8001" $VAR "$T/t.c" "$T/t.z0" 2>/dev/null &&
	"$O/cc1-z8001" $VAR "$T/t.z0" "$T/t.z1" 2>/dev/null &&
	"$O/cc2-z8001" $PEEP "$T/t.z1" "$T/t.o" "$T/scr" 0 2>/dev/null &&
	"$LD" -R 0x200 -e f_ -o "$T/a" "$T/t.o" "$T/ss.o" 2>/dev/null || {
		echo "  $name: BUILD FAILED"; FAIL=$((FAIL+1)); return; }
	got=$("$N2" -runobjint "$T/a" 2>/dev/null | grep -oE 'R1 = -?[0-9]+' | grep -oE '\-?[0-9]+$')
	if [ "$got" = "$want" ]; then echo "  $name: ok ($got)"
	else echo "  $name: WRONG got=$got want=$want"; FAIL=$((FAIL+1)); fi
}

echo "cc2 peep flags $PEEP:"

run "register int across a call" 5 '
int g();
int f()
{
	register int x;
	x = 5;
	g();
	return x;
}
int g()
{
	register int y;
	y = 99;
	return y;
}
'

run "register struct ptr across a call" 2 '
struct systab { char a; char t; int (*fn)(); };
struct systab tab[4];
int g();
int f()
{
	register struct systab *p;
	tab[1].t = 2;
	p = &tab[1];
	g();
	return p->t;
}
int g()
{
	register struct systab *q;
	q = &tab[3];
	q->t = 99;
	return 0;
}
'

run "two register vars across a call" 12 '
int g();
int f()
{
	register int a, b;
	a = 5; b = 7;
	g();
	return a + b;
}
int g()
{
	register int y, z;
	y = 99; z = 98;
	return y + z;
}
'

run "register int across an INDIRECT call" 5 '
int g();
int (*fp)();
int f()
{
	register int x;
	x = 5;
	fp = g;
	(*fp)();
	return x;
}
int g()
{
	register int y;
	y = 99;
	return y;
}
'

run "regvar across indirect call THROUGH a struct field" 2 '
struct systab { char a; char t; int (*fn)(); };
struct systab tab[4];
int g();
int f()
{
	register struct systab *p;
	tab[1].t = 2;
	tab[1].fn = g;
	p = &tab[1];
	(*p->fn)(1, 2, 3, 4, 5, 6);
	return p->t;
}
int g()
{
	register struct systab *q;
	q = &tab[3];
	q->t = 99;
	return 0;
}
'

run "regvar + 23 params + indirect call (trap() shape)" 2 '
struct systab { char a; char t; int (*fn)(); };
struct systab tab[4];
int args[6];
int g();
int t(e, o, sp, r0,r1,r2,r3,r4,r5,r6,r7, sig, id, fcw, pc)
unsigned e, o; char *sp, *pc; unsigned sig, id, fcw;
{
	register struct systab *stp;
	register int n;

	n = 1;
	stp = &tab[n];
	(*stp->fn)(args[0],args[1],args[2],args[3],args[4],args[5]);
	switch (stp->t) {
	case 2:  return 2;
	default: return 77;
	}
}
int f()
{
	tab[1].t = 2;
	tab[1].fn = g;
	return t(0,0,0, 0,0,0,0,0,0,0,0, 7, 11, 0, 0);
}
int g()
{
	register struct systab *q;
	q = &tab[3];
	q->t = 99;
	return 0;
}
'

if [ "$FAIL" != 0 ]; then
	echo "regclob: FAIL -- $FAIL of the register-clobber cases did not hold"
	exit 1
fi
echo "regclob: OK -- every case held"
