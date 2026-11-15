#!/bin/sh
# intcycles.sh -- what an integer multiply, divide or remainder costs in CPU
# clocks, held at ceilings, with fpcycles.py's estimator.
#
# Each expression is stored to a sink of its type between mark1() and mark2();
# the figure is the mean over 4 operand pairs, signs mixed.  The one-word MULT
# and DIV serve int operands, long products of two 16-bit values and unsigned
# words divided by unsigned words, also through a ?: of such values; an
# unsigned constant over 0x7FFF keeps MULTL.
# A signed long divided by 2^k is a sign test and shifts, its remainder a sign
# test and masks (two of the four dividends negative).
H="$(cd "$(dirname "$0")/.." && pwd)"
B="${C900_TC_BUILD:-$H/host/build}"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
[ -n "$N2" ] || exit 2
DIS="$B/tools/loutdis"
[ -x "$DIS" ] || { echo "intcycles.sh: no $DIS"; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0

cost() {	# type "<expression>" ceiling
	sum=0
	for j in 0 1 2 3; do
		cat > "$T/t.c" <<-EOF
		short sa[] = { 1234, -77, 32767, -32768 };
		short sb[] = { -9, 300, 2, 7 };
		unsigned short ua[] = { 65535, 1234, 40000, 7 };
		unsigned short ub[] = { 3, 50000, 255, 32768 };
		unsigned char cb[] = { 3, 255, 128, 10 };
		long la[] = { 100000L, -77777L, 0x7FFFFFFFL, -5L };
		$1 sink;
		mark1() { }
		mark2() { _exit(0); }
		main() { register int j; j = $j; mark1(); sink = $2; mark2(); return 0; }
		EOF
		"$CCZ" -o "$T/t" "$T/t.c" >/dev/null 2>&1 \
			|| { echo "  FAIL(build) $2"; fail=$((fail+1)); return; }
		c=$(python3 "$H/tests/fpcycles.py" "$N2" "$DIS" "$H/tests/z8000-cycles.tab" "$T/t") \
			|| { echo "  FAIL(run)   $2: $c"; fail=$((fail+1)); return; }
		sum=$((sum + ${c%% *}))
	done
	n=$((sum / 4))
	if [ $n -le $3 ]; then
		pass=$((pass+1)); printf '  %-32s %5d <= %5d  PASS\n' "$2" $n $3
	else
		fail=$((fail+1)); printf '  %-32s %5d >  %5d  FAIL\n' "$2" $n $3
	fi
}

cost int		'sa[j] * sb[j]'				127
cost int		'sa[j] / sb[j]'				177
cost int		'sa[j] % sb[j]'				177
cost unsigned		'ua[j] * ub[j]'				127
cost unsigned		'ua[j] / ub[j]'				146
cost unsigned		'ua[j] % ub[j]'				144
cost unsigned		'ua[j] / cb[j]'				186
cost unsigned		'ua[j] % cb[j]'				186
cost long		'(long)sa[j] * sb[j]'			130
cost long		'(long)sa[j] * 1000'			115
cost long		'(long)sa[j] * cb[j]'			130
cost 'unsigned long'	'(unsigned long)ua[j] * 15'		124
cost 'unsigned long'	'(unsigned long)ua[j] * 80'		125
cost 'unsigned long'	'(unsigned long)ua[j] * cb[j]'		151
cost 'unsigned long'	'(unsigned long)ua[j] * ub[j]'		181
cost long		'(long)sa[j] * ub[j]'			166
cost long		'la[j] / 16'				96
cost long		'la[j] % 16'				87
cost long		'la[j] / 1024'				115
cost long		'la[j] % 512'				87
cost long		'la[j] / 65536L'			134
cost long		'la[j] % 65536L'			87
cost long		'la[j] / 2'				86
cost 'unsigned long'	'(unsigned long)(j & 1 ? sa[j] : sb[j]) * ua[j]' 189
cost long		'(long)(j & 1 ? sa[j] : sb[j]) * sb[j]'	150
cost 'unsigned long'	'(unsigned long)(j & 1 ? ua[j] : ub[j]) * ub[j]' 198
cost long		'(long)(j & 1 ? ua[j] : 7) * sb[j]'	173
cost unsigned		'ua[j] / (j & 1 ? 10 : 300)'		185
cost unsigned		'ua[j] % (j & 1 ? cb[j] : 7)'		195

echo "=== intcycles: $pass passed, $fail failed ==="
[ "$fail" = 0 ]
