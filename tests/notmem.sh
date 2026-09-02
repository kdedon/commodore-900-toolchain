#!/bin/sh
# notmem.sh -- notmem()'s contract, executed against the real target libc.
#
# notmem() answers "is this pointer a block of the malloc arena that is IN USE",
# so that a caller holding a pointer of unknown provenance can decide whether
# free() is safe.  The COHERENT shell's sfree() is the caller that matters: it
# is called on static strings, on automatics, and on the same pointer twice by
# design, and it frees only what notmem() claims.  A freed block answered "mine"
# is therefore a double free.
#
# The cases run the whole deliverable pipeline: ccz (cc0/cc1/cc2 + ld + crt0 +
# libc-z8001.a) and then the guest runner, so the answers come from the libc
# archive a program on the machine would link against.
H="$(cd "$(dirname "$0")/.." && pwd)"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
[ -n "$N2" ] || exit 2
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
chk() {	# "<label>" "<full C source with main()>" "<expected stdout>"
	printf '%s\n' "$2" > "$T/n.c"
	"$CCZ" -o "$T/n" "$T/n.c" >/dev/null 2>&1 \
		|| { echo "  FAIL(build) $1"; fail=$((fail+1)); return; }
	got=$("$N2" -runexec "$T/n" 2>/dev/null)
	if [ "$got" = "$3" ]; then
		pass=$((pass+1)); printf '  %-46s PASS\n' "$1"
	else
		printf '  %-46s FAIL got=[%s] want=[%s]\n' "$1" "$got" "$3"; fail=$((fail+1))
	fi
}

# The block is in use, then it is not.  Both answers come from one run so the
# arena is the same arena; nothing is allocated between them.
chk 'live block is mine, freed block is not' '#include <stdio.h>
	extern char *malloc();
	main() {
		char *p; int live, dead;
		p = malloc(64);
		live = notmem(p);
		free(p);
		dead = notmem(p);
		printf("live=%d dead=%d\n", live, dead);
		return 0;
	}' 'live=0 dead=1'

# What sfree() is protecting: neither a static string nor an automatic is in the
# arena, and NULL is not either.
chk 'static string, automatic and NULL are not mine' '#include <stdio.h>
	static char s[] = "static";
	main() {
		char a[8];
		printf("s=%d a=%d n=%d\n", notmem(s), notmem(a), notmem((char *)0));
		return 0;
	}' 's=1 a=1 n=1'

# Freeing is idempotent for a caller that asks first: the second question about
# the same pointer answers the same way, so the second free never happens.
chk 'the answer for a freed block is stable' '#include <stdio.h>
	extern char *malloc();
	main() {
		char *p; int d1, d2;
		p = malloc(40);
		free(p);
		d1 = notmem(p);
		d2 = notmem(p);
		printf("d1=%d d2=%d\n", d1, d2);
		return 0;
	}' 'd1=1 d2=1'

# A block that is allocated again after being freed is in use again.
chk 'reallocated storage is mine again' '#include <stdio.h>
	extern char *malloc();
	main() {
		char *p, *q; int before, after;
		p = malloc(32);
		free(p);
		before = notmem(p);
		q = malloc(32);
		after = notmem(q);
		printf("before=%d after=%d same=%d\n", before, after, p == q);
		return 0;
	}' 'before=1 after=0 same=1'

# The arena must still be intact after all of that.
chk 'the arena survives the questioning' '#include <stdio.h>
	extern char *malloc();
	main() {
		char *p, *q;
		p = malloc(100); q = malloc(100);
		free(p); notmem(p); notmem(q); free(q); notmem(q);
		printf("memok=%d\n", memok());
		return 0;
	}' 'memok=1'

echo "=== notmem: $pass passed, $fail failed ==="
[ "$fail" = 0 ]
