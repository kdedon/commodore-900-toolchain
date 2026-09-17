#!/bin/sh
# printf.sh -- printf's hex conversions, executed against the real target libc.
#
# COHERENT 3.2 printed every hex digit from one upper-case table, so %x wrote
# A-F.  %x and %lx write lower case, as C's do; %X keeps its COHERENT meaning,
# the long conversion, and stays upper case.
#
# The cases run the whole deliverable pipeline (ccz, then the guest runner), so
# the output comes from the libc archive a program on the machine links against.
H="$(cd "$(dirname "$0")/.." && pwd)"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
[ -n "$N2" ] || exit 2
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
chk() {	# "<label>" "<full C source with main()>" "<expected stdout>"
	printf '%s\n' "$2" > "$T/p.c"
	"$CCZ" -o "$T/p" "$T/p.c" >/dev/null 2>&1 \
		|| { echo "  FAIL(build) $1"; fail=$((fail+1)); return; }
	got=$("$N2" -runexec "$T/p" 2>/dev/null)
	if [ "$got" = "$3" ]; then
		pass=$((pass+1)); printf '  %-46s PASS\n' "$1"
	else
		printf '  %-46s FAIL got=[%s] want=[%s]\n' "$1" "$got" "$3"; fail=$((fail+1))
	fi
}

chk '%x is lower case' '#include <stdio.h>
	main() {
		printf("[%x] [%4x] [%04x]\n", 0xBEEF, 0xAB, 0xC);
		return 0;
	}' '[beef] [  ab] [000c]'

chk '%lx is lower case' '#include <stdio.h>
	main() {
		printf("[%lx] [%10lx]\n", 0xDEADBEEFL, 0xFACEL);
		return 0;
	}' '[deadbeef] [      face]'

chk '%X is long and upper case' '#include <stdio.h>
	main() {
		printf("[%X] [%x]\n", 0xCAFEF00DL, 0xAB);
		return 0;
	}' '[CAFEF00D] [ab]'

echo "=== printf: $pass passed, $fail failed ==="
[ "$fail" = 0 ]
