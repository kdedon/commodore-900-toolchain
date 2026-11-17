#!/bin/sh
# lswitch.sh -- switch on long and unsigned long.
#
# Case labels are converted to the controlling type, so the whole 32-bit range
# is usable: AmigaOS tags at TAG_USER (0x80000000) and up, negative longs, and
# values that agree in their low 16 bits.  Each switch runs over a list of
# values in the emulator and must print what the host prints with long at 32
# bits.  A dense range dispatches through a table; sparse values (tags) take
# a binary search of compares.  Duplicates are found after conversion.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"; DIS="$BUILD/tools/loutdis"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/sw.c" <<'EOF'
#ifndef LONG			/* the host check builds with 32-bit int for long */
#define LONG	long
#define ULONG	unsigned long
#endif
#define TAG_USER	((ULONG)0x80000000UL)

tags(t) ULONG t; {	/* sparse tags at TAG_USER + n */
	switch (t) {
	case TAG_USER + 1: return 1;
	case TAG_USER + 0x20: return 2;
	case TAG_USER + 0x1003: return 3;
	case TAG_USER + 0x80000L: return 4;
	case 0: return 5;
	case 0xFFFFFFFFUL: return 6;
	case TAG_USER + 7: return 7;
	case TAG_USER + 0x7FFFFFFEUL: return 8;
	case 1: return 9;
	case TAG_USER: return 10;
	default: return -1;
	}
}

neg(l) LONG l; {		/* negative longs, signed order */
	switch (l) {
	case -1: return 1;
	case -100000L: return 2;
	case (LONG)0x80000000UL: return 3;
	case 0x7FFFFFFFL: return 4;
	case -2: return 5;
	case 40000L: return 6;
	case -40000L: return 7;
	case 0: return 8;
	}
	return 0;
}

low16(l) LONG l; {		/* the same low 16 bits, and fallthrough */
	int r;
	r = 0;
	switch (l) {
	case 5: r = 1; break;
	case 0x10005L: r = 2;
	case 0x20005L: r += 3; break;
	case -0xFFFBL: r = 4; break;	/* 0xFFFF0005 */
	case 0x50005L: r = 5; break;
	case (unsigned short)-1: r = 6; break;	/* 0x0000FFFF */
	case -1: r = 7; break;
	default: r = -9;
	}
	return r;
}

dense(u) ULONG u; {	/* 0x80000010..0x8000001B: a table */
	switch (u) {
	case TAG_USER + 0x10: return 1; case TAG_USER + 0x11: return 2;
	case TAG_USER + 0x12: return 3; case TAG_USER + 0x13: return 4;
	case TAG_USER + 0x14: return 5; case TAG_USER + 0x15: return 6;
	case TAG_USER + 0x17: return 7; case TAG_USER + 0x18: return 8;
	case TAG_USER + 0x19: return 9; case TAG_USER + 0x1A: return 10;
	case TAG_USER + 0x1B: return 11;
	default: return 0;
	}
}

sdense(l) LONG l; {		/* -5..5: a table across zero */
	switch (l) {
	case -5: return 1; case -4: return 2; case -3: return 3;
	case -2: return 4; case -1: return 5; case 0: return 6;
	case 1: return 7; case 2: return 8; case 3: return 9;
	case 4: return 10; case 5: return 11;
	}
	return 0;
}

nest(l, i) LONG l; {		/* an int switch inside a long one */
	switch (l) {
	case 0x12340000L:
		switch (i) {
		case 1: return 1;
		case 2: return 2;
		}
		return 3;
	case 0x56780000L: return 4;
	}
	return 5;
}

LONG v[] = {
	0, 1, 2, 5, 7, -1, -2, -5, 4, 3, 0x10005L, 0x20005L, 0x50005L, -0xFFFBL,
	0xFFFFL, (LONG)0xFFFFFFFEUL, 40000L, -40000L, -100000L, 0x7FFFFFFFL, (LONG)0x80000000UL,
	(LONG)0x80000001UL, (LONG)0x80000007UL, (LONG)0x80000020UL,
	(LONG)0x80001003UL, (LONG)0x80080000UL, (LONG)0x8000000FUL,
	(LONG)0x80000010UL, (LONG)0x80000015UL, (LONG)0x80000016UL,
	(LONG)0x8000001BUL, (LONG)0x8000001CUL, 0x12340000L, 0x56780000L,
	0x00010001L
};

extern printf();
main() {
	int i, n;

	n = sizeof v / sizeof v[0];
	for (i = 0; i < n; ++i)
		printf("%d: %d %d %d %d %d %d %d\n", i, tags(v[i]), neg(v[i]),
		    low16(v[i]), dense(v[i]), sdense(v[i]), nest(v[i], i % 3),
		    nest(v[i], 1));
	return 0;
}
EOF

[ -n "$N2" ] || { echo "  lswitch: no guest runner"; exit 2; }
want=$(gcc -std=gnu89 -w -DLONG=int '-DULONG=unsigned int' -o "$T/host" "$T/sw.c" && "$T/host" | tr -d '\r')
if "$CCZ" -o "$T/sw" "$T/sw.c" >/dev/null 2>&1; then
	got=$("$N2" -runexec "$T/sw" 2>/dev/null) || true
	if [ "$got" = "$want" ]; then
		echo "  values PASS"
	else
		echo "  values FAIL"; printf '%s\n' "$want" > "$T/w"; printf '%s\n' "$got" > "$T/g"
		diff "$T/w" "$T/g" || true; fail=1
	fi
else
	echo "  lswitch: link FAIL"; fail=1
fi

"$CCZ" -c -o "$T/sw.o" "$T/sw.c" >/dev/null 2>&1 || { echo "  lswitch: compile FAIL"; exit 1; }
form() { # <fn> <table|search>
	if "$DIS" -v -fn "$1" "$T/sw.o" 2>/dev/null | grep -qiw ldar; then
		got=table
	else
		got=search
	fi
	if [ "$got" = "$2" ]; then
		printf '  %-8s %s PASS\n' "$1" "$2"
	else
		printf '  %-8s want=%s got=%s FAIL\n' "$1" "$2" "$got"; fail=1
	fi
}
form tags_ search
form neg_ search
form low16_ search
form dense_ table
form sdense_ table

# Duplicates after conversion.  <source>
dup() {
	printf '%s\n' "$1" > "$T/d.c"
	if "$CC0" $VAR "$T/d.c" "$T/d.z0" > "$T/d.err" 2>&1; then
		echo "  duplicate: compiled FAIL ($1)"; fail=1
	elif grep -q "duplicated case constant" "$T/d.err"; then
		echo "  duplicate PASS"
	else
		echo "  duplicate FAIL"; cat "$T/d.err"; fail=1
	fi
}
dup 'f(l) long l; { switch (l) { case 5: case 5L: ; } }'
dup 'f(u) unsigned long u; { switch (u) { case -1: case 0xFFFFFFFF: ; } }'
dup 'f(l) long l; { switch (l) { case 0x80000000: case (long)0x80000000: ; } }'

[ "$fail" = 0 ] || { echo "=== lswitch: FAIL ==="; exit 1; }
echo "=== lswitch: PASS ==="
