#!/bin/sh
# sbrk.sh -- running out of memory, executed against the real target libc.
#
# sbrk returns (char *)-1 when the break is refused, as malloc expects.  A
# NULL there made malloc take address 0 as a new arena and write through it.
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

chk 'a refused sbrk returns -1, break unchanged' '#include <stdio.h>
	extern char *sbrk();
	extern int errno;
	main() {
		char *p, *before;
		int n;
		for (n = 0; n < 1000; n++) {
			before = sbrk(0);
			if ((p = sbrk(30000)) == (char *)-1)
				break;
			if (p == NULL) {
				printf("NULL\n");
				return 1;
			}
		}
		printf("%s %d %s\n", n < 1000 ? "refused" : "never refused",
			errno, sbrk(0) == before ? "same" : "moved");
		return 0;
	}' 'refused 12 same'

chk 'malloc returns NULL when memory runs out' '#include <stdio.h>
	extern char *malloc();
	main() {
		char *p;
		int n;
		for (n = 0; n < 1000; n++)
			if ((p = malloc(30000)) == NULL)
				break;
		printf("%s\n", n > 0 && n < 1000 ? "NULL" : "wrong");
		return 0;
	}' 'NULL'

echo "=== sbrk: $pass passed, $fail failed ==="
[ "$fail" = 0 ]
