#!/bin/sh
# vdebug.sh -- a program compiled -VDEBUG links and runs.  The object carries no
# debug table; cc2 reads past the records.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

cat > "$T/r.c" <<'EOF'
#include <stdio.h>
struct pt { int x; long y; };
int tab[3] = {1, 2, 3};
sum(p) struct pt *p; {
	int i, s;
	s = 0;
	for (i = 0; i < 3; i++)
		s += tab[i];
	return s + p->x + (int)p->y;
}
main() {
	struct pt a;
	a.x = 10;
	a.y = 100L;
	printf("%d\n", sum(&a));
	return 0;
}
EOF
CCZ_VAR=800010020800 "$CCZ" -o "$T/r" "$T/r.c" >/dev/null 2>&1 ||
	{ echo "=== vdebug: compile FAIL ==="; exit 1; }
[ -n "$N2" ] || { echo "  vdebug: no guest runner"; exit 2; }
got=$("$N2" -runexec "$T/r" 2>/dev/null) || true
if [ "$got" = 116 ]; then
	echo "=== vdebug: PASS ==="
else
	echo "  vdebug: got [$got] want [116]"
	echo "=== vdebug: FAIL ==="; exit 1
fi
