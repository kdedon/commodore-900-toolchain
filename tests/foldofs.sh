#!/bin/sh
# foldofs.sh -- a constant field offset on a far pointer belongs in the
# Z8000 base-displacement operand, not in an ADD of its own.
#
# Loads and stores address `k(RRn)'; only arithmetic, compare, inc-dec and
# bit-field ops must build p + k first.  A CONVERT or CAST between the deref
# and its user is transparent.  Each case checks the shape and runs.
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
struct s { int a; int b; long c; char d; char e; int f; };
long gl; int gi; char gc;
ld_int(p)  struct s *p; { gi = p->f; }
st_int(p)  struct s *p; { p->f = gi; }
ld_long(p) struct s *p; { gl = p->c; }
st_long(p) struct s *p; { p->c = gl; }
ld_byte(p) struct s *p; { gc = p->e; }
st_byte(p) struct s *p; { p->e = gc; }
wide_byte(p) struct s *p; { gi = p->e; }	/* CONVERT between deref and store */
wide_int(p)  struct s *p; { gl = p->b; }	/* ... widening to long */
add_int(p)   struct s *p; { gi = p->f + 1; }	/* ADD: no memory displacement form */
inc_fld(p)   struct s *p; { p->f++; }		/* inc-dec addresses memory itself */
zero_st(p)   struct s *p; { p->f = 0; }		/* CLR has no displacement form */
EOF
"$CC0" $VAR "$T/f.c" "$T/f.z0" && "$CC1" $VAR "$T/f.z0" "$T/f.z1" &&
"$CC2" 0012 "$T/f.z1" "$T/f.o" "$T/f.scr" 0 || { echo "  foldofs: compile FAIL"; exit 1; }

# Folded: a displacement off the loaded pair, no ADD/INC.

shape() { # <fn> <want-folded 1|0>
	d=$("$DIS" -v -fn "$1" "$T/f.o" 2>/dev/null)
	got=1
	printf '%s\n' "$d" | grep -Eq '^\s+[0-9a-f]+:\s+(INC|ADD|ADDL)\s+RR?1[01]' && got=0
	printf '%s\n' "$d" | grep -Eq '0x[0-9A-F]{4}\(R10\)' || got=0
	if [ "$got" = "$2" ]; then
		printf '  %-14s %s PASS\n' "$1" "$([ "$2" = 1 ] && echo folded || echo materialized)"
	else
		printf '  %-14s want=%s got=%s FAIL\n' "$1" "$2" "$got"
		printf '%s\n' "$d" | sed 's/^/      /'
		fail=1
	fi
}
for f in ld_int st_int ld_long st_long ld_byte st_byte wide_byte wide_int; do
	shape "${f}_" 1
done
shape add_int_ 0
shape inc_fld_ 0
shape zero_st_ 0

# ... and the values the folded operands read and write.
[ -n "$N2" ] || { echo "  foldofs: no guest runner"; exit 2; }
cat > "$T/r.c" <<'EOF'
#include <stdio.h>
struct s { int a; int b; long c; char d; char e; int f; };
struct s v;
main() {
	struct s *p; long l;
	p = &v;
	v.a = 1; v.b = -2; v.c = 0x12345678L; v.d = 3; v.e = -4; v.f = 5;
	p->f = p->f + 100;
	p->c = p->c + 1;
	p->e = 9;
	l = p->b;
	printf("%d %ld %d %d %ld\n", p->f, p->c, p->e, (int)p->d, l);
}
EOF
"$CCZ" -o "$T/r" "$T/r.c" >/dev/null 2>&1 || { echo "  foldofs: link FAIL"; exit 1; }
got=$("$N2" -runexec "$T/r" 2>/dev/null) || true
want="105 305419897 9 3 -2"
if [ "$got" = "$want" ]; then
	echo "  values         PASS"
else
	echo "  values         FAIL got=[$got] want=[$want]"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== foldofs: FAIL ==="; exit 1; }
echo "=== foldofs: PASS ==="
