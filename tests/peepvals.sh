#!/bin/sh
# peepvals.sh -- values through the size peepholes and the x/2 rule, on the target.
#
# Each program in peepvals/ prints what an EXTS/DIV build printed: x/2 for every x in
# eight forms, x % 2^k against constants, TEST after stores, compare chains as DEC,
# folded pushes, memory compares with 0, loads from a holding register, and small long
# constants.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[ -n "$N2" ] || { echo "  peepvals: no guest runner"; exit 2; }
fail=0
for c in "$H"/tests/peepvals/*.c; do
	n=$(basename "$c" .c)
	if ! (cd "$T" && "$CCZ" -o "$T/$n" "$c" >/dev/null 2>&1); then
		echo "  $n compile FAIL"; fail=1; continue
	fi
	"$N2" -runexec "$T/$n" 2>/dev/null | grep -v '^\[exit' > "$T/$n.got" || true
	if cmp -s "$T/$n.got" "$H/tests/peepvals/$n.want"; then
		echo "  $n PASS"
	else
		echo "  $n FAIL:"; diff "$H/tests/peepvals/$n.want" "$T/$n.got" | sed 5q | sed 's/^/      /'; fail=1
	fi
done
[ "$fail" = 0 ] || { echo "=== peepvals: FAIL ==="; exit 1; }
echo "=== peepvals: PASS ==="
