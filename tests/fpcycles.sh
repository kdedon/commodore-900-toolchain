#!/bin/sh
# fpcycles.sh -- what a soft-float operation or libm call costs in CPU clocks
# on the stock machine, held at the costs of the truncating routines.
#
# Each expression runs once per argument between mark1() and mark2();
# fpcycles.py sums the Z8001 manual's segmented-mode cycles (z8000-cycles.tab)
# over the path the runner executes, MULTL by its multiplicand's bits, and
# adds DRAM refresh.  The figure is the mean over the 4 arguments.
#
# Checked once against a clock-accurate model of the machine running the
# same expressions, after adding that harness's loop step and soft-float
# dispatch: within 0.2-0.8% for + - * / and cos, 1.4-2.5% low for floor,
# ceil and modf, the same on all three library versions measured.
H="$(cd "$(dirname "$0")/.." && pwd)"
B="${C900_TC_BUILD:-$H/host/build}"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
[ -n "$N2" ] || exit 2
LIBM="$B/libm-z8001/libm-z8001.a"; DIS="$B/tools/loutdis"
[ -f "$LIBM" ] || { echo "fpcycles.sh: no $LIBM (make libm)"; exit 2; }
[ -x "$DIS" ] || { echo "fpcycles.sh: no $DIS"; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0

cost() {	# "<expression>" ceiling
	sum=0
	for j in 0 1 2 3; do
		cat > "$T/t.c" <<-EOF
		#include <math.h>
		double p[] = { 2.5, 0.75, 7.0, 123.25 };
		double n[] = { -2.5, -0.75, -7.0, -123.25 };
		double a[] = { 1.0, 0.1, 3.7, 123.456 };
		double b[] = { 0.9, 3.0, 1.3, 7.89 };
		double sink, ip;
		mark1() { }
		mark2() { _exit(0); }
		main() { register int j; j = $j; mark1(); sink = $1; mark2(); return 0; }
		EOF
		"$CCZ" -o "$T/t" "$T/t.c" "$LIBM" >/dev/null 2>&1 \
			|| { echo "  FAIL(build) $1"; fail=$((fail+1)); return; }
		c=$(python3 "$H/tests/fpcycles.py" "$N2" "$DIS" "$H/tests/z8000-cycles.tab" "$T/t") \
			|| { echo "  FAIL(run)   $1: $c"; fail=$((fail+1)); return; }
		sum=$((sum + ${c%% *}))
	done
	n=$((sum / 4))
	if [ $n -le $2 ]; then
		pass=$((pass+1)); printf '  %-22s %6d <= %6d  PASS\n' "$1" $n $2
	else
		fail=$((fail+1)); printf '  %-22s %6d >  %6d  FAIL\n' "$1" $n $2
	fi
}

cost 'a[j] + b[j]'	752
cost 'a[j] - b[j]'	789
cost 'a[j] * b[j]'	2420
cost 'a[j] / b[j]'	3404
cost 'floor(p[j])'	1643
cost 'floor(n[j])'	4407
cost 'ceil(p[j])'	2289
cost 'ceil(n[j])'	5080
cost 'modf(p[j], &ip)'	1501
cost 'modf(n[j], &ip)'	4266
cost 'cos(p[j])'	54223

echo "=== fpcycles: $pass passed, $fail failed ==="
[ "$fail" = 0 ]
