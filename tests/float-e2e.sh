#!/bin/sh
# End-to-end soft-float: the REAL toolchain, linked and executed.
#   cc0 -> cc1 -> cc2 -> f.o            (float lowering: a OP b => CALL dl{add,sub,mul,div})
#   as tests/rt/*.s -> *.o              (the soft-float routines cc1 emits calls to)
#   as 'SS=0' -> ss.o                   (flat stack-segment symbol)
#   ld -R 0x200 -e f_ ... -> a.out       (link; the float CALLs resolved)
#   n2 -runobj a.out A B WANT           (sim runs f(A,B), checks RQ0 == WANT, IEEE doubles)
# Exercises +, -, *, / and a chained expression (multiple composed soft-float calls).
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
B="${C900_BUILD:-$H/host/build}"	# the lane's build dir; see host/publish.sh
O="$B/z8001"; AS="$B/as-z8001"
LD="$B/ld-z8001"; N2="${N2:-$(sh "$H/host/runner.sh")}"; VAR="${VAR:-800000000800}"; PEEP="${PEEP:-0010}"
# No runner, no gate: runner.sh has said why on stderr, and running the cases
# against an empty one scores each missing result as a wrong answer.
[ -n "$N2" ] || exit 2
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/lib"
for s in dadd dmul ddiv dcmp itod dtoi ftod dtof ldexp frexp modfs; do
	"$AS" -o "$T/lib/$s.o" "$H/tests/rt/$s.s" 2>/dev/null
done
printf '\t.globl\tSS\nSS = 0\n' > "$T/ss.s"; "$AS" -o "$T/ss.o" "$T/ss.s" 2>/dev/null
fail=0
run() { # "<body>" hexA hexB hexWant "<label>"
	printf 'double f(a,b) double a; double b; { %s }\n' "$1" > "$T/f.c"
	"$O/cc0-z8001" $VAR "$T/f.c" "$T/f.z0" 2>/dev/null
	"$O/cc1-z8001" $VAR "$T/f.z0" "$T/f.z1" 2>/dev/null
	"$O/cc2-z8001" $PEEP "$T/f.z1" "$T/f.o" "$T/f.scr" 0 2>/dev/null
	"$LD" -R 0x200 -e f_ -o "$T/a.out" "$T/f.o" "$T"/lib/*.o "$T/ss.o" 2>/dev/null
	r=$("$N2" -runobj "$T/a.out" "$2" "$3" "$4" 2>&1 | grep -oE '(PASS|FAIL)')
	printf '  %-26s %s\n' "$5" "$r"
	[ "$r" = PASS ] || fail=1
}
run 'return a + b;'         0x3FF8000000000000 0x4004000000000000 0x4010000000000000 "1.5 + 2.5 = 4.0"
run 'return a - b;'         0x4014000000000000 0x3FF8000000000000 0x400C000000000000 "5.0 - 1.5 = 3.5"
run 'return a * b;'         0x4000000000000000 0x4008000000000000 0x4018000000000000 "2.0 * 3.0 = 6.0"
run 'return a / b;'         0x4024000000000000 0x4010000000000000 0x4004000000000000 "10.0 / 4.0 = 2.5"
run 'return (a + b) * b;'   0x3FF8000000000000 0x4004000000000000 0x4024000000000000 "(1.5+2.5)*2.5 = 10.0"
run 'double t; t=a*b; return t+a;' 0x4008000000000000 0x4000000000000000 0x4022000000000000 "3*2+3 = 9.0 (store/reload)"
# F32 float<->double conversions: a float local narrows the double on store
# (fdpack) and widens back on load (dfload).  Float-exact values round-trip exactly.
run 'float x; x = a; return x;'         0x4010000000000000 0x4000000000000000 0x4010000000000000 "round-trip 4.0 (narrow+widen)"
run 'float x; x = a + b; return x;'     0x3FF8000000000000 0x4004000000000000 0x4010000000000000 "1.5+2.5 ->flt-> 4.0"
run 'float x; x = a; return x + b;'     0x4000000000000000 0x4008000000000000 0x4014000000000000 "(flt)2.0 + 3.0 = 5.0"

# double GLOBAL store/load: the 8-byte value spans @RR+0 (high pair) and @RR+4 (low
# pair); the low pair needs LDL base+disp (load 0x35 / store 0x37).  Different
# signature, so build the source directly.
rung() { # "<full source>" hexA hexB hexWant "<label>"
	printf '%s\n' "$1" > "$T/f.c"
	"$O/cc0-z8001" $VAR "$T/f.c" "$T/f.z0" 2>/dev/null
	"$O/cc1-z8001" $VAR "$T/f.z0" "$T/f.z1" 2>/dev/null
	"$O/cc2-z8001" $PEEP "$T/f.z1" "$T/f.o" "$T/f.scr" 0 2>/dev/null
	"$LD" -R 0x200 -e f_ -o "$T/a.out" "$T/f.o" "$T"/lib/*.o "$T/ss.o" 2>/dev/null
	r=$("$N2" -runobj "$T/a.out" "$2" "$3" "$4" 2>&1 | grep -oE '(PASS|FAIL)')
	printf '  %-34s %s\n' "$5" "$r"; [ "$r" = PASS ] || fail=1
}
rung 'double dg; double f(a) double a; { dg = a; return dg; }' \
	0x4024000000000000 0 0x4024000000000000 "double global round-trip 10.0"
rung 'double dg; double f(a) double a; { dg = a; return dg + a; }' \
	0x4000000000000000 0 0x4010000000000000 "double global dg+a = 4.0"

[ $fail = 0 ] && echo "float-e2e: ALL PASS" || { echo "float-e2e: FAIL"; exit 1; }
