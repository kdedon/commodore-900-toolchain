#!/bin/sh
# switch.sh -- dense switches dispatch through a table, sparse ones compare.
#
# Each switch runs over a range of values in the emulator, linked plainly,
# under -VPIC, and placed in the second text segment behind 80 KB of filler;
# every build must print what the host prints.  Then the disassembly shows
# which functions took the table (LDAR) and which kept the compare chain.

set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CCZ="$H/host/ccz"; DIS="$BUILD/tools/loutdis"
N2="${N2:-$(sh "$H/host/runner.sh")}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/sw.c" <<'EOF'
#include <stdio.h>

dense(x) {		/* 0..11 */
	switch (x) {
	case 0: return 10; case 1: return 11; case 2: return 12;
	case 3: return 13; case 4: return 14; case 5: return 15;
	case 6: return 16; case 7: return 17; case 8: return 18;
	case 9: return 19; case 10: return 20; case 11: return 21;
	default: return -1;
	}
}

based(x) {		/* 100..113 with gaps, fallthrough and break */
	int r;
	r = 0;
	switch (x) {
	case 100: r = 1; break;
	case 101: r = 2;
	case 102: r += 3; break;
	case 104: r = 4; break;
	case 105: r = 5; break;
	case 106: r = 6; break;
	case 107: r = 7; break;
	case 109: r = 8; break;
	case 110: r = 9; break;
	case 111: r = 10; break;
	case 113: r = 11; break;
	default: r = -2; break;
	}
	return r * 3;
}

sparse(x) {
	switch (x) {
	case 1: return 1; case 10: return 2; case 100: return 3;
	case 200: return 4; case 300: return 5; case 400: return 6;
	case 500: return 7; case 600: return 8; case 700: return 9;
	case 800: return 10; case -900: return 11; case 1000: return 12;
	default: return 0;
	}
}

neg(x) {		/* -6..5 */
	switch (x) {
	case -6: return 60; case -5: return 50; case -4: return 40;
	case -3: return 30; case -2: return 20; case -1: return 10;
	case 0: return 0; case 1: return -10; case 2: return -20;
	case 3: return -30; case 4: return -40; case 5: return -50;
	default: return 99;
	}
}

chr(c) char c; {	/* 'a'..'l' */
	switch (c) {
	case 'a': return 1; case 'b': return 2; case 'c': return 3;
	case 'd': return 4; case 'e': return 5; case 'f': return 6;
	case 'g': return 7; case 'h': return 8; case 'i': return 9;
	case 'j': return 10; case 'k': return 11; case 'l': return 12;
	default: return 0;
	}
}

int g;
nodef(x) {		/* 1..12, no default */
	g = -3;
	switch (x) {
	case 1: g = 1; break; case 2: g = 2; break; case 3: g = 3; break;
	case 4: g = 4; break; case 5: g = 5; break; case 6: g = 6; break;
	case 7: g = 7; break; case 8: g = 8; break; case 9: g = 9; break;
	case 10: g = 10; break; case 11: g = 11; break; case 12: g = 12; break;
	}
	return g;
}

near(x) {		/* ten cases over 0..20: just inside the size limit */
	switch (x) {
	case 0: return 1; case 1: return 2; case 2: return 3; case 3: return 4;
	case 4: return 5; case 5: return 6; case 6: return 7; case 7: return 8;
	case 8: return 9; case 20: return 10;
	default: return 0;
	}
}

far(x) {		/* ten cases over 0..21: just outside */
	switch (x) {
	case 0: return 1; case 1: return 2; case 2: return 3; case 3: return 4;
	case 4: return 5; case 5: return 6; case 6: return 7; case 7: return 8;
	case 8: return 9; case 21: return 10;
	default: return 0;
	}
}

main() {
	int x;
	long s;

	for (x = -1100; x <= 1100; ++x) {
		s = dense(x) + 3L*based(x) + 5L*sparse(x) + 7L*neg(x)
		  + 11L*nodef(x) + 13L*near(x) + 17L*far(x);
		if (x >= -128 && x <= 127)
			s += 19L*chr(x);
		if (s != 0)
			printf("%d %ld\n", x, s);
	}
	return 0;
}
EOF
printf '\t.shri\n\t.blkw\t20000\n' > "$T/fill.s"

[ -n "$N2" ] || { echo "  switch: no guest runner"; exit 2; }
want=$(gcc -std=gnu89 -w -o "$T/host" "$T/sw.c" && "$T/host")

run() { # <name> <ccz args...>
	name=$1; shift
	if ! "$CCZ" -o "$T/$name" "$@" >/dev/null 2>&1; then
		echo "  $name: link FAIL"; fail=1; return
	fi
	got=$("$N2" -runexec "$T/$name" 2>/dev/null) || true
	if [ "$got" = "$want" ]; then
		echo "  $name PASS"
	else
		echo "  $name FAIL"; fail=1
	fi
}
run plain "$T/sw.c"
CCZ_VAR=800000020808 run pic "$T/sw.c"
run seg1 -i -L "$T/fill.s" "$T/fill.s" "$T/sw.c"
"$BUILD/tools/loutid" -e -s "$T/seg1" > "$T/syms" 2>/dev/null || true
at=$(awk '$1 == "SHRI" && $3 == "dense_" { print $2 }' "$T/syms")
entry=$(sed -n '1s/.*entry=0x\([0-9a-fA-F]*\).*/\1/p' "$T/syms")
if [ -n "$at" ] && [ -n "$entry" ] && [ $((0x${at#0x} >> 24)) -gt $((0x$entry >> 24)) ]; then
	echo "  seg1 dense_ at $at PASS"
else
	echo "  seg1 dense_ at [$at] FAIL"; fail=1
fi

"$CCZ" -c -o "$T/sw.o" "$T/sw.c" >/dev/null 2>&1 || { echo "  switch: compile FAIL"; exit 1; }
form() { # <fn> <table|chain>
	if "$DIS" -v -fn "$1" "$T/sw.o" 2>/dev/null | grep -qiw ldar; then
		got=table
	else
		got=chain
	fi
	if [ "$got" = "$2" ]; then
		printf '  %-8s %s PASS\n' "$1" "$2"
	else
		printf '  %-8s want=%s got=%s FAIL\n' "$1" "$2" "$got"; fail=1
	fi
}
form dense_ table
form based_ table
form sparse_ chain
form neg_ table
form chr_ table
form nodef_ table
form near_ table
form far_ chain

[ "$fail" = 0 ] || { echo "=== switch: FAIL ==="; exit 1; }
echo "=== switch: PASS ==="
