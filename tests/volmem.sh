#!/bin/sh
# volmem.sh -- a volatile object in memory is accessed as the source wrote it.
#
# Two reads load twice, a dead store stands, and two volatile objects keep
# their order.  Each case has an unqualified twin that must still be optimized.
# Includes the device-register form, `*(volatile char *)0xF000'.
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
struct s { int a; int b; };
struct m { volatile int a; int b; };
volatile int vg, vg2;
int ng;
volatile struct s vs;
struct s ns;
struct m vm;
volatile int va[4];
int na[4];

vread()  { return vg + vg; }			/* a global */
nread()  { return ng + ng; }
vlcl()   { volatile int a; a = 1; sink(&a); return a + a; }
nlcl()   { int a; a = 1; sink(&a); return a + a; }
vobj()   { return vs.a + vs.a; }		/* a field of a volatile struct */
nobj()   { return ns.a + ns.a; }
vfld()   { return vm.a + vm.a; }		/* ... and a volatile field */
nfld()   { return vm.b + vm.b; }
velt()   { return va[1] + va[1]; }		/* an array element */
nelt()   { return na[1] + na[1]; }
vptr(p) volatile char *p; { return *p + *p; }	/* through a pointer */
nptr(p) char *p; { return *p + *p; }
vdev()   { return *(volatile char *)0x7000 + *(volatile char *)0x7000; }
vstore() { vg = 1; vg = 2; }			/* neither store is read */
vorder() { return vg + vg2 + vg; }
EOF
"$CC0" $VAR "$T/f.c" "$T/f.z0" && "$CC1" $VAR "$T/f.z0" "$T/f.z1" &&
"$CC2" 0012 "$T/f.z1" "$T/f.o" "$T/f.scr" 0 || { echo "  volmem: compile FAIL"; exit 1; }

dis() { "$DIS" -v -fn "$1_" "$T/f.o" 2>/dev/null; }

# An absolute operand `0x<seg>:0x<offset>': a global, or a call's callee.
direct() { dis "$1" | grep -Ev 'CALL|JR|JP' | grep -Ec '0x[0-9A-F]+:0x[0-9A-F]+([^(]|$)' || true; }
# A frame slot.
frame()  { dis "$1" | grep -Ec '0x[0-9A-F]+:0x[0-9A-F]+\(R13\)' || true; }
# A byte load through a pointer pair.
deref()  { dis "$1" | grep -Ec 'LDB +RL[0-9],@R' || true; }

count() { # <fn> <counter> <want> <what>
	n=$($2 "$1")
	if [ "$n" = "$3" ]; then
		printf '  %-8s %s %s PASS\n' "$1" "$3" "$4"
	else
		printf '  %-8s want %s %s got=%s FAIL\n' "$1" "$3" "$4" "$n"
		dis "$1" | sed 's/^/      /'
		fail=1
	fi
}

count vread  direct 2 "loads of the global"
count nread  direct 1 "load of the global"
count vlcl   frame  4 "frame references"
count nlcl   frame  3 "frame references"
count vobj   direct 2 "loads of the field"
count nobj   direct 1 "load of the field"
count vfld   direct 2 "loads of the field"
count nfld   direct 1 "load of the field"
count velt   direct 2 "loads of the element"
count nelt   direct 1 "load of the element"
count vptr   deref  2 "loads through the pointer"
count nptr   deref  2 "loads through the pointer"
count vdev   deref  2 "loads of the device register"
count vstore direct 2 "stores kept"

# Two volatile objects in one expression keep their order.
ord=$(dis vorder | grep -Ev 'CALL|JR|JP' |
      sed -n 's/.*\(0x[0-9A-F]*:0x[0-9A-F]*\)$/\1/p' | tr '\n' ' ')
set -- $ord
if [ $# = 3 ] && [ "$1" = "$3" ] && [ "$1" != "$2" ]; then
	printf '  %-8s %s PASS\n' vorder "in order"
else
	printf '  %-8s want a b a got=[%s] FAIL\n' vorder "$ord"; fail=1
fi

# ... and the values.

[ -n "$N2" ] || { echo "  volmem: no guest runner"; exit 2; }
cat > "$T/r.c" <<'EOF'
#include <stdio.h>
struct m { volatile int a; int b; };
volatile int vg;
volatile struct m vm;
volatile int va[4];
sink(p) int *p; { }

vread()  { return vg + vg; }
vlcl()   { volatile int a; a = 1; sink(&a); return a + a; }
vfld()   { vm.a = 3; return vm.a + vm.a; }
velt()   { va[1] = 4; return va[1] + va[1]; }
vptr(p) volatile char *p; { return *p + *p; }

main() {
	char c;

	vg = 7;
	c = 5;
	printf("%d %d %d %d %d\n", vread(), vlcl(), vfld(), velt(), vptr(&c));
}
EOF
"$CCZ" -o "$T/r" "$T/r.c" >/dev/null 2>&1 || { echo "  volmem: link FAIL"; exit 1; }
got=$("$N2" -runexec "$T/r" 2>/dev/null) || true
want="14 2 6 8 10"
if [ "$got" = "$want" ]; then
	echo "  values   PASS"
else
	echo "  values   FAIL got=[$got] want=[$want]"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== volmem: FAIL ==="; exit 1; }
echo "=== volmem: PASS ==="
