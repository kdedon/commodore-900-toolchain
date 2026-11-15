#!/bin/sh
# mixdecl.sh -- declarations after statements, and `for (T i = e; ...)'.
#
# A declaration may follow statements in a block; its name is in scope from
# its declarator to the end of the block, so an earlier use names the outer
# object, and its initializer runs where it stands.  A `for' declaration is
# scoped to the loop.  A goto may jump past a declaration.  The program must
# print what the host prints.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/m.c" <<'EOF'
extern printf();
typedef long L;
int x = 100;
int f(n) {
	int s;
	s = x;			/* the outer x */
	int x = n * 2;		/* in scope from here */
	s += x;
	L big = 70000L;		/* a typedef name starts a declaration */
	s += (int)(big / 1000);
	for (int x = 0; x < 3; ++x)	/* shadows the block's x */
		s += x;
	s += x;			/* the block's x again */
	{
		s += x;
		int x = 1;	/* nested block */
		s += x;
		register int r = 5;
		s += r;
		char buf[4];
		buf[0] = 'a';
		s += buf[0] - 'a';
	}
	goto skip;
	int y = 7;		/* jumped over */
skip:
	y = 3;
	s += y;
	return s;
}
int g() {
	int t = 0;
	for (int i = 0; i < 4; i++) {
		t += i;
		int sq = i * i;
		t += sq;
	}
	for (int i = 10, j = 1; i < 12; i++, j++)
		t += i * j;
	static int calls;
	return t + ++calls;
}
main() {
	printf("%d %d %d\n", f(10), g(), g());
	return 0;
}
EOF

[ -n "$N2" ] || { echo "  mixdecl: no guest runner"; exit 2; }
want=$(gcc -std=gnu99 -w -o "$T/host" "$T/m.c" && "$T/host")
if "$CCZ" -o "$T/m" "$T/m.c" >/dev/null 2>&1; then
	got=$("$N2" -runexec "$T/m" 2>/dev/null) || true
	if [ "$got" = "$want" ]; then
		echo "  values PASS"
	else
		echo "  values: want [$want] got [$got] FAIL"; fail=1
	fi
else
	echo "  mixdecl: compile FAIL"; fail=1
fi

# Diagnostics.  <want-message> <source>
diag() {
	printf '%s\n' "$2" > "$T/d.c"
	if "$CC0" $VAR "$T/d.c" "$T/d.z0" > "$T/d.err" 2>&1; then
		echo "  diag \"$1\": compiled FAIL"; fail=1
	elif grep -q "$1" "$T/d.err"; then
		echo "  diag \"$1\" PASS"
	else
		echo "  diag \"$1\": FAIL"; cat "$T/d.err"; fail=1
	fi
}
diag '"y" is not defined' 'f() { y = 1; int y; return y; }'
diag '"a" is being redeclared' 'f() { int a; a = 1; long a; return 0; }'
diag '"i" is not defined' 'f() { for (int i = 0; i < 2; i++) ; return i; }'

[ "$fail" = 0 ] || { echo "=== mixdecl: FAIL ==="; exit 1; }
echo "=== mixdecl: PASS ==="
