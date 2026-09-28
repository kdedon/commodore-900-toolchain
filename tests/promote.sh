#!/bin/sh
# promote.sh -- which undeclared locals the code generator puts in a register.
#
# A word, long or pointer local of the function's own block takes a register
# unless its address is taken, it is accessed volatile, or the function calls
# setjmp.  A pointer to volatile is not itself volatile.  An initialized array
# keeps its elements in memory.  Nothing is promoted under -VDEBUG.
#
# Each function has one local, so any frame access is that local's.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"; CC1="$BUILD/z8001/cc1-z8001"
CC2="$BUILD/z8001/cc2-z8001"; DIS="$BUILD/tools/loutdis"
VAR=800000020800
VDEBUG=800010020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/f.c" <<'EOF'
extern sink(), use(), setjmp();
int gn, gi, jb[24];
typedef volatile int vint;

plain() {
	int a;
	a = gn;
	sink();
	return a;
}
taken() {
	int a;
	a = gn;
	sink();
	use(&a);
	return a;
}
jumped() {
	int a;
	a = gn;
	if (setjmp(jb) == 0)
		sink();
	return a;
}
vlocal() {
	volatile int a;
	a = gn;
	sink();
	return a;
}
vptr() {
	int * volatile p;
	p = &gi;
	sink();
	return *p;
}
ptrvol() {
	volatile int *p;
	p = &gi;
	sink();
	return *p;
}
vtypedef() {
	vint a;
	a = gn;
	sink();
	return a;
}
inblock() {
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
blockonly() {
	if (gn > 0) {
		int a;
		a = gn;
		sink();
		return a;
	}
	return 0;
}
initarr() {
	int a[2] = {1, 2};
	sink();
	return a[1];
}
EOF
"$CC0" $VAR "$T/f.c" "$T/f.z0" && "$CC1" $VAR "$T/f.z0" "$T/f.z1" &&
"$CC2" 0012 "$T/f.z1" "$T/f.o" "$T/f.scr" 0 ||
	{ echo "  promote: compile FAIL"; exit 1; }

# shape <fn> <want-a-register 1|0>
shape() {
	d=$("$DIS" -v -fn "$1" "$T/f.o" 2>/dev/null)
	[ -n "$d" ] || { echo "  $1: no disassembly FAIL"; fail=1; return; }
	if printf '%s\n' "$d" | grep -Eq '0x[0-9A-F]+:0x[0-9A-F]+\(R13\)'; then
		got=0
	else
		got=1
	fi
	if [ "$got" = "$2" ]; then
		printf '  %-10s %s PASS\n' "$1" \
			"$([ "$2" = 1 ] && echo register || echo frame)"
	else
		printf '  %-10s want=%s got=%s FAIL\n' "$1" "$2" "$got"
		printf '%s\n' "$d" | sed 's/^/      /'
		fail=1
	fi
}
shape plain_ 1
shape taken_ 0
shape jumped_ 0
shape vlocal_ 0
shape vptr_ 0
shape ptrvol_ 1
shape vtypedef_ 0
shape inblock_ 0
shape blockonly_ 0

# cc2 takes no debug records, so -VDEBUG is read from the code generator's output.
"$CC0" $VDEBUG "$T/f.c" "$T/g.z0" && "$CC1" $VDEBUG "$T/g.z0" "$T/g.z1" &&
"$BUILD/z8001/cc3-z8001" $VDEBUG "$T/g.z1" "$T/g.z3" ||
	{ echo "  promote: -VDEBUG compile FAIL"; exit 1; }
if sed -n '/plain_:/,/autos/p' "$T/g.z3" | grep -q '(r13)'; then
	echo "  plain_     frame, -VDEBUG PASS"
else
	echo "  plain_     want=frame under -VDEBUG FAIL"; fail=1
fi

# Both initializer stores go to the array.
n=$("$DIS" -v -fn initarr_ "$T/f.o" 2>/dev/null |
	grep -Ec 'LD +0x[0-9A-F]+:0x[0-9A-F]+\(R13\),#0x000[12]$' || true)
if [ "$n" = 2 ]; then
	echo "  initarr_   elements in memory PASS"
else
	echo "  initarr_   $n of 2 element stores in memory FAIL"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== promote: FAIL ==="; exit 1; }
echo "=== promote: PASS ==="
