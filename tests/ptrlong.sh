#!/bin/sh
# ptrlong.sh -- an address cast to long in a static initializer.
#
# A far pointer and a long are the same two words, so `(unsigned long)a',
# `(long)&s.f', `(long)fn' and `(unsigned long)a + 4' initialize a long with
# the relocated pointer, exactly as `char *p = a' (+ 4) does: the objects must
# be identical, and the values must equal the same casts evaluated at run time.
# An address cut to a word or a byte is not a constant and stays an error.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"; CC1="$BUILD/z8001/cc1-z8001"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/l.c" <<'EOF'
static char a[] = "xyzw";
struct S { int i; long l; char c[3]; } s;
int fn();
unsigned long t[] = { (unsigned long)a, (long)&s.c[1], (long)fn, (unsigned long)a + 4,
    (unsigned long)(a + 2), (long)&s, (long)(unsigned long)&s.l };
long v = (long)&s.l;
unsigned long w = (unsigned long)fn + 2;
EOF
cat > "$T/p.c" <<'EOF'
static char a[] = "xyzw";
struct S { int i; long l; char c[3]; } s;
int fn();
char *t[] = { a, &s.c[1], (char *)fn, a + 4,
    a + 2, (char *)&s, (char *)&s.l };
long *v = &s.l;
char *w = (char *)fn + 2;
EOF
"$CCZ" -c -o "$T/l.o" "$T/l.c" >/dev/null 2>&1 && "$CCZ" -c -o "$T/p.o" "$T/p.c" >/dev/null 2>&1 ||
	{ echo "  ptrlong: compile FAIL"; "$CC0" $VAR "$T/l.c" "$T/l.z0" && "$CC1" $VAR "$T/l.z0" "$T/l.z1"; exit 1; }
if cmp -s "$T/l.o" "$T/p.o"; then
	echo "  long initializers = pointer initializers PASS"
else
	echo "  long initializers = pointer initializers: objects differ FAIL"; fail=1
fi

# Values: each datum against the cast done at run time.
cat > "$T/main.c" <<'EOF'
extern printf();
extern char a[];
struct S { int i; long l; char c[3]; };
extern struct S s;
extern unsigned long t[];
extern long v;
extern unsigned long w;
fn() { return 0; }
char *ap() { return a; }
main() {
	int bad = 0;
	char *x = ap();
	if (t[0] != (unsigned long)x) bad |= 1;
	if (t[1] != (unsigned long)&s.c[1]) bad |= 2;
	if (t[2] != (unsigned long)fn) bad |= 4;
	if (t[3] != (unsigned long)x + 4) bad |= 8;
	if (t[4] != (unsigned long)(x + 2)) bad |= 16;
	if (t[5] != (unsigned long)&s) bad |= 32;
	if (t[6] != (unsigned long)&s.l) bad |= 64;
	if (v != (long)&s.l) bad |= 128;
	if (w != (unsigned long)fn + 2) bad |= 256;
	if (*(char *)t[0] != 'x' || *(char *)t[4] != 'z') bad |= 512;
	printf("%d\n", bad);
	return 0;
}
EOF
sed 's/^static char a/char a/' "$T/l.c" > "$T/lg.c"
[ -n "$N2" ] || { echo "  ptrlong: no guest runner"; exit 2; }
if "$CCZ" -o "$T/m" "$T/main.c" "$T/lg.c" >/dev/null 2>&1; then
	got=$("$N2" -runexec "$T/m" 2>/dev/null) || true
	if [ "$got" = 0 ]; then
		echo "  values PASS"
	else
		echo "  values: mismatch mask [$got] FAIL"; fail=1
	fi
else
	echo "  ptrlong: link FAIL"; fail=1
fi

# Not constants.  <initializer>
diag() {
	printf 'static char a[] = "x";\n%s;\n' "$1" > "$T/d.c"
	if "$CC0" $VAR "$T/d.c" "$T/d.z0" > "$T/d.err" 2>&1 &&
	   "$CC1" $VAR "$T/d.z0" "$T/d.z1" >> "$T/d.err" 2>&1; then
		echo "  diag \"$1\": compiled FAIL"; fail=1
	elif grep -q "initializer too complex" "$T/d.err"; then
		echo "  diag \"$1\" PASS"
	else
		echo "  diag \"$1\": FAIL"; cat "$T/d.err"; fail=1
	fi
}
diag 'int t = (int)a'
diag 'char t = (char)a'
diag 'long t = (long)(unsigned)a'
diag 'long t = -(long)a'
diag 'long t = (long)a * 2'

[ "$fail" = 0 ] || { echo "=== ptrlong: FAIL ==="; exit 1; }
echo "=== ptrlong: PASS ==="
