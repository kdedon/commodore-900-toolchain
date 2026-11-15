#!/bin/sh
# linecomment.sh -- C99 `//' comments.
#
# A `//' outside a string or character constant comments out the rest of the
# line, after code and in a directive, where it ends a #define's body.  A
# backslash-newline inside the comment continues it onto the next line, and
# the line count stays right.  `//*' starts a line comment, as in C99.  The
# standalone preprocessor (cppz), whose input may be assembler, leaves `//'
# alone, as before.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/c.c" <<'EOF'
#include <stdio.h>	// after a directive
#define N 3 // a comment ends the body
#define M(x) ((x) + 1) // and a spliced one \
   goes on here
int a = 4 //**/ 2
;
char *s = "x//y";	// not inside a string
int c = '/';		// nor after a character constant
int lost = 1;
// a spliced comment \
int lost = 2;
int ln = __LINE__;
#if N == 3 // in a condition
int yes = 1;
#else
int yes = 0;
#endif // after #endif
/* a block // comment */ int b = 5;
main() {
	int i;		// in a function
	i = M(N) // the expression goes on
	    * 2;
	printf("%d %s %d %d %d %d %d %d\n", a, s, c, lost, ln, yes, b, i);
	return 0;
}
EOF
want="4 x//y 47 1 12 1 5 8"

[ -n "$N2" ] || { echo "  linecomment: no guest runner"; exit 2; }
if "$CCZ" -o "$T/c" "$T/c.c" >/dev/null 2>&1; then
	got=$("$N2" -runexec "$T/c" 2>/dev/null) || true
	if [ "$got" = "$want" ]; then
		echo "  values PASS"
	else
		echo "  values: want [$want] got [$got] FAIL"; fail=1
	fi
else
	echo "  linecomment: compile FAIL"; "$CCZ" -o "$T/c" "$T/c.c" || true; fail=1
fi

printf 'ld r0, r1 // kept\n#define X 1\nX\n' > "$T/a.s"
got=$(sh "$H/host/cppz" -P "$T/a.s" 2>/dev/null | grep -c '// kept') || true
if [ "$got" = 1 ]; then
	echo "  cppz keeps // PASS"
else
	echo "  cppz keeps //: FAIL"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== linecomment: FAIL ==="; exit 1; }
echo "=== linecomment: PASS ==="
