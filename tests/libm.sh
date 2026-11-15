#!/bin/sh
# libm.sh -- modf, floor, ceil and the functions built on modf, executed
# against the real target libc and libm.
#
# modf returns the fraction and stores the integral part, both with the sign of
# the argument (ANSI 7.5.4.6, as the manual says).  It once stored the floor
# and, between -1 and 0, returned 1 - x, so exp(-0.5) came out as exp(0.5) and
# tan(-0.5) lost its sign.  floor and ceil step a negative or positive fraction.
H="$(cd "$(dirname "$0")/.." && pwd)"
B="${C900_TC_BUILD:-$H/host/build}"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
[ -n "$N2" ] || exit 2
LIBM="$B/libm-z8001/libm-z8001.a"
[ -f "$LIBM" ] || { echo "libm.sh: no $LIBM (make libm)"; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
chk() {	# "<label>" "<full C source with main()>" "<expected stdout>"
	printf '%s\n' "$2" > "$T/p.c"
	"$CCZ" -o "$T/p" "$T/p.c" "$LIBM" >/dev/null 2>&1 \
		|| { echo "  FAIL(build) $1"; fail=$((fail+1)); return; }
	got=$("$N2" -runexec "$T/p" 2>/dev/null | grep -v '^\[exit')
	if [ "$got" = "$3" ]; then
		pass=$((pass+1)); printf '  %-46s PASS\n' "$1"
	else
		printf '  %-46s FAIL got=[%s] want=[%s]\n' "$1" "$got" "$3"; fail=$((fail+1))
	fi
}

# Each value is printed as 4 * itself, so every case is an exact integer.
chk 'floor and ceil' '#include <stdio.h>
	#include <math.h>
	double v[] = { 2.5, -2.5, -0.5, 0.5, -0.25, -3.75, -7.0, 7.0, -1.0, 0.0 };
	main() {
		int i;
		for (i = 0; i < 10; i++)
			printf("%d %d ", (int)floor(v[i]), (int)ceil(v[i]));
		printf("\n");
		return 0;
	}' '2 3 -3 -2 -1 0 0 1 -1 0 -4 -3 -7 -7 7 7 -1 -1 0 0 '

chk 'modf has the sign of its argument' '#include <stdio.h>
	#include <math.h>
	double v[] = { 2.5, -2.5, -0.5, 0.75, -0.25, -3.75, -7.0 };
	main() {
		int i;
		double f, ip;
		for (i = 0; i < 7; i++) {
			f = modf(v[i], &ip);
			printf("%d %d ", (int)(4.0 * ip), (int)(4.0 * f));
		}
		printf("\n");
		return 0;
	}' '8 2 -8 -2 0 -2 0 3 0 -1 -12 -3 -28 0 '

chk 'exp, tan and cos below zero' '#include <stdio.h>
	#include <math.h>
	main() {
		printf("%ld %ld %ld %ld\n", (long)(exp(-0.5) * 1e6),
		    (long)(tan(-0.5) * 1e6), (long)(cos(-1.0) * 1e6),
		    (long)(exp(-2.25) * 1e6));
		return 0;
	}' '606530 -546302 540302 105399'

# Signed zeros, infinities and NaN, as bits: floor(-0.0) and ceil of -1 < x <= 0
# are -0.0, modf(-0.0) stores -0.0, and inf and NaN come back unchanged.
chk 'signed zero, inf and NaN' '#include <stdio.h>
	#include <math.h>
	union u { double d; unsigned long l[2]; };
	unsigned long v[][2] = { {0x80000000L,0}, {0xbfe00000L,0},
		{0x7ff00000L,0}, {0xfff00000L,0}, {0x7ff80000L,0} };
	main() {
		union u a, r;
		double ip;
		int i;
		for (i = 0; i < 5; i++) {
			a.l[0] = v[i][0]; a.l[1] = v[i][1];
			r.d = floor(a.d); printf("%08lx ", r.l[0] | r.l[1]);
			r.d = ceil(a.d); printf("%08lx ", r.l[0] | r.l[1]);
			modf(a.d, &r.d); printf("%08lx ", r.l[0] | r.l[1]);
		}
		printf("\n");
		return 0;
	}' '80000000 80000000 80000000 bff00000 80000000 80000000 7ff00000 7ff00000 7ff00000 fff00000 fff00000 fff00000 7ff80000 7ff80000 7ff80000 '

echo "=== libm: $pass passed, $fail failed ==="
[ "$fail" = 0 ]
