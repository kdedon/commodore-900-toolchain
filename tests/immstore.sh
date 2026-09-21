#!/bin/sh
# immstore.sh -- a constant stored through a far pointer goes through a
# register, so the field offset rides in the store's displacement.
#
# The Z8000 has no immediate store to k(RRn).  Loading the constant costs a
# word (LDK where it fits) and saves the address arithmetic.  Not taken where
# it loses: a constant past LDK against an offset INC can reach, a zero (CLR),
# or a long.  Each case checks the shape and runs.

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
struct s { int a; int b; long c; char d; char e; int f; int g[20]; int h; };
st_small(p) struct s *p; { p->f = 7; }		/* LDK constant */
st_byte(p)  struct s *p; { p->e = 7; }
st_far(p)   struct s *p; { p->h = 300; }	/* offset past INC's 16 */
st_near(p)  struct s *p; { p->b = 300; }	/* neither: keep the INC */
st_zero(p)  struct s *p; { p->f = 0; }		/* CLR */
st_long(p)  struct s *p; { p->c = 7L; }
EOF
"$CC0" $VAR "$T/f.c" "$T/f.z0" && "$CC1" $VAR "$T/f.z0" "$T/f.z1" &&
"$CC2" 0012 "$T/f.z1" "$T/f.o" "$T/f.scr" 0 || { echo "  immstore: compile FAIL"; exit 1; }

shape() { # <fn> <want-through-a-register 1|0>
	d=$("$DIS" -v -fn "$1" "$T/f.o" 2>/dev/null)
	got=1
	printf '%s\n' "$d" | grep -Eq '^\s+[0-9a-f]+:\s+(INC|ADD)\s+R1[01]' && got=0
	printf '%s\n' "$d" | grep -Eq '(LD|LDB)\s+0x[0-9A-F]{4}\(R10\),R' || got=0
	if [ "$got" = "$2" ]; then
		printf '  %-10s %s PASS\n' "$1" "$([ "$2" = 1 ] && echo register || echo immediate)"
	else
		printf '  %-10s want=%s got=%s FAIL\n' "$1" "$2" "$got"
		printf '%s\n' "$d" | sed 's/^/      /'
		fail=1
	fi
}
shape st_small_ 1
shape st_byte_ 1
shape st_far_ 1
shape st_near_ 0
shape st_zero_ 0
shape st_long_ 0

# ... and the values the folded stores write.
[ -n "$N2" ] || { echo "  immstore: no guest runner"; exit 2; }
cat > "$T/r.c" <<'EOF'
#include <stdio.h>
struct s { int a; int b; long c; char d; char e; int f; int g[20]; int h; };
struct s v;
main() {
	struct s *p;
	p = &v;
	v.a = -1; v.d = -2;
	p->f = 7; p->e = 7; p->h = 300; p->b = 300; p->c = 9L;
	printf("%d %d %d %d %d %ld %d\n",
		p->a, p->b, (int)p->d, (int)p->e, p->f, p->c, p->h);
}
EOF
"$CCZ" -o "$T/r" "$T/r.c" >/dev/null 2>&1 || { echo "  immstore: link FAIL"; exit 1; }
got=$("$N2" -runexec "$T/r" 2>/dev/null) || true
want="-1 300 -2 7 7 9 300"
if [ "$got" = "$want" ]; then
	echo "  values     PASS"
else
	echo "  values     FAIL got=[$got] want=[$want]"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== immstore: FAIL ==="; exit 1; }
echo "=== immstore: PASS ==="
