#!/bin/sh
# calr.sh -- calls to an already-emitted function in range use CALR.
#
# CALR is one word to CALL's three and reaches +-4 KB.  Backward and recursive
# calls go relative; forward, extern and out-of-range calls stay CALL.

set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"; CC1="$BUILD/z8001/cc1-z8001"
CC2="$BUILD/z8001/cc2-z8001"; DIS="$BUILD/tools/loutdis"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

# far_ is pushed out of reach by a filler of ~5 KB of straight-line code.
{
	cat <<'EOF'
extern elsewhere();
int g;
callee(a) { return a + 1; }
backward() { g = callee(1); }
recurse(n) { if (n <= 0) return 0; return recurse(n-1) + 1; }
forward() { g = later(); }
later() { return 7; }
extcall() { g = elsewhere(); }
far0() { return 0; }
filler(a) {
EOF
	i=0
	while [ $i -lt 700 ]; do echo "	a = a * 3 + $i;"; i=$((i+1)); done
	cat <<'EOF'
	return a;
}
beyond() { g = far0(); }
EOF
} > "$T/c.c"

"$CC0" $VAR "$T/c.c" "$T/c.z0" && "$CC1" $VAR "$T/c.z0" "$T/c.z1" &&
"$CC2" 0012 "$T/c.z1" "$T/c.o" "$T/c.scr" 0 || { echo "  calr: compile FAIL"; exit 1; }

want() { # <fn> <CALR|CALL>
	got=$("$DIS" -v -fn "$1" "$T/c.o" 2>/dev/null | grep -oE '\b(CALR|CALL)\b' | head -1)
	if [ "$got" = "$2" ]; then
		printf '  %-12s %s PASS\n' "$1" "$2"
	else
		printf '  %-12s want=%s got=[%s] FAIL\n' "$1" "$2" "$got"; fail=1
	fi
}
want backward_ CALR
want recurse_  CALR
want forward_  CALL
want extcall_  CALL
want beyond_   CALL

# ... and the relative calls go where they say they go.
[ -n "$N2" ] || { echo "  calr: no guest runner"; exit 2; }
cat > "$T/r.c" <<'EOF'
#include <stdio.h>
add3(a) { return a + 3; }
fact(n) { return n <= 1 ? 1 : n * fact(n-1); }
main() {
	int i, s;
	s = 0;
	for (i = 0; i < 5; ++i)
		s = s + add3(i);
	printf("%d %d\n", s, fact(6));
}
EOF
"$CCZ" -o "$T/r" "$T/r.c" >/dev/null 2>&1 || { echo "  calr: link FAIL"; exit 1; }
got=$("$N2" -runexec "$T/r" 2>/dev/null) || true
want="25 720"
if [ "$got" = "$want" ]; then
	echo "  values       PASS"
else
	echo "  values       FAIL got=[$got] want=[$want]"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== calr: FAIL ==="; exit 1; }
echo "=== calr: PASS ==="
