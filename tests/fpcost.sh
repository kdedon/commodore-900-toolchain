#!/bin/sh
# fpcost.sh -- what a soft-float operation or libm call costs, in guest
# instructions per call, held under a ceiling so speed cannot regress unseen.
#
# Each expression runs 4 arguments x 25 times; the same program with no
# iterations is subtracted, so the call, its argument loads and the store of
# the result are counted.  Counts come from bisecting $N2BUDGET.  Ceilings sit
# near the costs of the old truncating routines.
H="$(cd "$(dirname "$0")/.." && pwd)"
B="${C900_TC_BUILD:-$H/host/build}"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
[ -n "$N2" ] || exit 2
LIBM="$B/libm-z8001/libm-z8001.a"
[ -f "$LIBM" ] || { echo "fpcost.sh: no $LIBM (make libm)"; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0

count() {	# BINARY -> instructions to exit, or nothing
	lo=0; hi=4000000
	N2QUIET=1 N2BUDGET=$hi "$N2" -runexec "$1" >/dev/null 2>&1 || return
	while [ $((hi - lo)) -gt 1 ]; do
		mid=$(((lo + hi) / 2))
		if N2QUIET=1 N2BUDGET=$mid "$N2" -runexec "$1" >/dev/null 2>&1
		then hi=$mid; else lo=$mid; fi
	done
	echo $hi
}

cost() {	# "<expression>" ceiling
	for r in 0 25; do
		cat > "$T/t$r.c" <<-EOF
		#include <math.h>
		double p[] = { 2.5, 0.75, 7.0, 123.25 };
		double n[] = { -2.5, -0.75, -7.0, -123.25 };
		double a[] = { 1.0, 0.1, 3.7, 123.456 };
		double b[] = { 0.9, 3.0, 1.3, 7.89 };
		double sink, ip;
		main() {
			register int i, j;
			for (j = 0; j < 4; j++) for (i = 0; i < $r; i++) sink = $1;
			return 0;
		}
		EOF
		"$CCZ" -o "$T/t$r" "$T/t$r.c" "$LIBM" >/dev/null 2>&1 \
			|| { echo "  FAIL(build) $1"; fail=$((fail+1)); return; }
	done
	c0=$(count "$T/t0"); c1=$(count "$T/t25")
	[ -n "$c0" ] && [ -n "$c1" ] \
		|| { echo "  FAIL(run)   $1"; fail=$((fail+1)); return; }
	n=$(((c1 - c0 + 50) / 100))
	if [ $n -le $2 ]; then
		pass=$((pass+1)); printf '  %-22s %5d <= %5d  PASS\n' "$1" $n $2
	else
		fail=$((fail+1)); printf '  %-22s %5d >  %5d  FAIL\n' "$1" $n $2
	fi
}

cost 'a[j] + b[j]'	92
cost 'a[j] - b[j]'	98
cost 'a[j] * b[j]'	164
cost 'a[j] / b[j]'	170
cost 'floor(p[j])'	158
cost 'floor(n[j])'	350
cost 'ceil(p[j])'	226
cost 'ceil(n[j])'	285
cost 'modf(p[j], &ip)'	139
cost 'modf(n[j], &ip)'	255
cost 'cos(p[j])'	4007

echo "=== fpcost: $pass passed, $fail failed ==="
[ "$fail" = 0 ]
