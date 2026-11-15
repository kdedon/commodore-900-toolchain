#!/bin/sh
# autoarray.sh -- an automatic array sized by its initializer.
#
# `long a[] = { 1, 2 };' inside a function takes its bound from the initializer,
# as C89 allows, and must compile to the object of `long a[2] = { 1, 2 };': a
# string, an array of structures (with members initialized whole from a
# structure, or brace-elided), nested braces, run-time values and a declaration
# after a statement.  Without an initializer it is still an error.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/a.c" <<'EOF'
struct P { short x, y; };
struct R { short a, b; };
long f1(i) { long a[] = { 1, 2 }; return a[i]; }
int f2(i) { char s[] = "abc"; return s[i]; }
int f3(i) { struct P p[] = { { 1, 2 }, { 3, 4 }, 5, 6 }; return p[i].y; }
int f4(i, j) { int m[][3] = { { 1, 2, 3 }, { 4, 5 } }; return m[i][j]; }
int f5(i) { char *t[] = { "x", "yy", 0 }; return t[i] ? t[i][0] : -1; }
int f6(i, q) struct R *q; { struct R r[] = { *q, { 7, 8 } }; return r[i].b; }
int f7(n) { int a[] = { n, n + 1, n * 2 }; int b = 9; return a[2] + b; }
int f8(i) { static long s[] = { 5, 6 }; return s[i]; }
int f9(n) { n++; register int a[] = { n, 3 }; char z[] = { 'q' }; return a[0] + a[1] + z[0] + sizeof a; }
EOF
sed -e 's/a\[\] = { 1, 2 }/a[2] = { 1, 2 }/; s/s\[\] = "abc"/s[4] = "abc"/; s/p\[\] = /p[3] = /' \
    -e 's/m\[\]\[3\]/m[2][3]/; s/t\[\] = /t[3] = /; s/r\[\] = /r[2] = /; s/int a\[\] = { n, n/int a[3] = { n, n/' \
    -e 's/register int a\[\] = /register int a[2] = /; s/z\[\] = /z[1] = /' "$T/a.c" > "$T/b.c"
if "$CCZ" -c -o "$T/a.o" "$T/a.c" >/dev/null 2>&1 && "$CCZ" -c -o "$T/b.o" "$T/b.c" >/dev/null 2>&1; then
	if cmp -s "$T/a.o" "$T/b.o"; then
		echo "  a[] = sized a[n] PASS"
	else
		echo "  a[] = sized a[n]: objects differ FAIL"; fail=1
	fi
else
	echo "  autoarray: compile FAIL"; "$CC0" $VAR "$T/a.c" "$T/a.z0" || true; fail=1
fi

cat > "$T/main.c" <<'EOF'
extern printf();
struct R { short a, b; };
extern long f1();
main() {
	struct R q;
	q.a = 11; q.b = 12;
	printf("%ld %ld %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n", f1(0), f1(1), f2(1), f2(3),
	    f3(1), f3(2), f4(0, 2), f4(1, 1), f4(1, 0), f5(1), f5(2), f6(0, &q), f6(1, &q),
	    f7(5), f8(1), f9(4));
	return 0;
}
EOF
[ -n "$N2" ] || { echo "  autoarray: no guest runner"; exit 2; }
want=$(gcc -std=gnu89 -w -o "$T/host" "$T/main.c" "$T/a.c" && "$T/host" | sed 's/ [0-9]*$//')
want="$want 125"	# f9: sizeof a is 4 with a 16-bit int
if "$CCZ" -o "$T/m" "$T/main.c" "$T/a.c" >/dev/null 2>&1; then
	got=$("$N2" -runexec "$T/m" 2>/dev/null) || true
	if [ "$got" = "$want" ]; then
		echo "  values PASS"
	else
		echo "  values: want [$want] got [$got] FAIL"; fail=1
	fi
else
	echo "  autoarray: link FAIL"; fail=1
fi

printf 'f() { int a[]; return a[0]; }\n' > "$T/d.c"
if "$CC0" $VAR "$T/d.c" "$T/d.z0" > "$T/d.err" 2>&1; then
	echo "  diag: compiled FAIL"; fail=1
elif grep -q "cannot declare flexible automatic array" "$T/d.err"; then
	echo "  diag \"cannot declare flexible automatic array\" PASS"
else
	echo "  diag: FAIL"; cat "$T/d.err"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== autoarray: FAIL ==="; exit 1; }
echo "=== autoarray: PASS ==="
