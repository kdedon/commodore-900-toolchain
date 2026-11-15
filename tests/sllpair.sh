#!/bin/sh
# sllpair.sh -- a word shift is not a pair write.
#
# SLL and SDL on a word register write that word only.  The copy-deletion
# liveness scan once took them for pair ops, so `SLL R7,#k' looked like it
# overwrote R8, the even half of RR8.  A pointer copy `LDL RR8,RR10' was then
# deleted although a later `LDL RR6,RR8' still read it.
#
# Each case checks that every register pair a reg-reg LDL reads was loaded
# earlier in the function, then the program runs and prints what it computed.

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
struct s { int a, b; };
sll(p, n, k) register struct s *p; int n, k;
{
	register struct s *q; int r;
	q = p; r = q->a; if (n) r++; r += k << 3; r += q->b; return r;
}
sdl(p, n, k) register struct s *p; int n, k;
{
	register struct s *q; int r;
	q = p; r = q->a; if (n) r++; r += k << n; r += q->b; return r;
}
unsigned srl(p, n, k) register struct s *p; int n; unsigned k;
{
	register struct s *q; unsigned r;
	q = p; r = q->a; if (n) r++; r += k >> 2; r += q->b; return r;
}
EOF
"$CC0" $VAR "$T/f.c" "$T/f.z0" && "$CC1" $VAR "$T/f.z0" "$T/f.z1" &&
"$CC2" 0012 "$T/f.z1" "$T/f.o" "$T/f.scr" 0 || { echo "  sllpair: compile FAIL"; exit 1; }

shape() { # <fn> <shift egrep>
	d=$("$DIS" -v -fn "$1" "$T/f.o" 2>/dev/null)
	if printf '%s\n' "$d" | grep -Eq "$2" && printf '%s\n' "$d" | awk '
		/LDL +RR[0-9]+,RR[0-9]+$/ {
			split($NF, o, ","); if (!(o[2] in set)) bad = 1 }
		/LDL +RR[0-9]+,/ { split($NF, o, ","); set[o[1]] = 1 }
		END { exit bad }'; then
		printf '  %-5s copy kept  PASS\n' "$1"
	else
		printf '  %-5s copy kept  FAIL\n' "$1"
		printf '%s\n' "$d" | sed 's/^/      /'
		fail=1
	fi
}
shape sll_ 'SLL +R[0-9]+,3$'
shape sdl_ 'SDL +R[0-9]+,R[0-9]+$'
shape srl_ 'SLL +R[0-9]+,-2$'

[ -n "$N2" ] || { echo "  sllpair: no guest runner"; exit 2; }
cp "$T/f.c" "$T/r.c"
cat >> "$T/r.c" <<'EOF'
#include <stdio.h>
struct s x = { 1, 20 }, y = { 300, 4000 };
main() {
	register struct s *w; unsigned big;
	w = &y; big = 40000;
	printf("%d %d %d %d %u %u %d\n", sll(&x, 1, 2), sll(&x, 0, 2),
		sdl(&x, 2, 3), sdl(&x, 0, 3), srl(&x, 1, big), srl(&x, 0, 8), w->a);
}
EOF
"$CCZ" -o "$T/r" "$T/r.c" >/dev/null 2>&1 || { echo "  sllpair: link FAIL"; exit 1; }
got=$("$N2" -runexec "$T/r" 2>/dev/null) || true
want="38 37 34 24 10022 23 300"
if [ "$got" = "$want" ]; then
	echo "  values           PASS"
else
	echo "  values           FAIL got=[$got] want=[$want]"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== sllpair: FAIL ==="; exit 1; }
echo "=== sllpair: PASS ==="
