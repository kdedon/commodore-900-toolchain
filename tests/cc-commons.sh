#!/bin/sh
# cc-commons.sh -- tentative definitions, compiled and linked.
#
# Under -VCOMM, the driver's default, an uninitialised file-scope `int foo;' is
# a common: a sized undefined external that ld merges into one object.  Each
# case links two objects and runs the result.

set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
B="${C900_TC_BUILD:-$H/host/build}"
O="$B/z8001"; AS="$B/as-z8001"; LD="$B/ld-z8001"
N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=802000020800		# as above, plus VCOMM
PEEP=0010
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '\t.globl\tSS\nSS = 0\n' > "$T/ss.s"; "$AS" -o "$T/ss.o" "$T/ss.s" 2>/dev/null
pass=0; fail=0

cc() {	# name source
	printf '%s\n' "$2" > "$T/$1.c"
	"$O/cc0-z8001" $VAR "$T/$1.c" "$T/$1.z0" 2>/dev/null \
	&& "$O/cc1-z8001" $VAR "$T/$1.z0" "$T/$1.z1" 2>/dev/null \
	&& "$O/cc2-z8001" $PEEP "$T/$1.z1" "$T/$1.o" "$T/scr" 0 2>/dev/null
}
r1() { "$N2" -runobjint "$1" 2>/dev/null | grep -oE 'R1 = -?[0-9]+' | grep -oE '\-?[0-9]+$'; }

run() {	# label want srcA srcB
	if ! cc a "$3" || ! cc b "$4"; then
		echo "  FAIL(compile) [$1]"; fail=$((fail+1)); return
	fi
	if ! "$LD" -R 0x200 -e f_ -o "$T/out" "$T/a.o" "$T/b.o" "$T/ss.o" 2>"$T/lderr"; then
		echo "  FAIL(link) [$1]: $(cat "$T/lderr")"; fail=$((fail+1)); return
	fi
	v=$(r1 "$T/out")
	if [ "$v" = "$2" ]; then pass=$((pass+1))
	else echo "  FAIL got=[$v] want $2 [$1]"; fail=$((fail+1)); fi
}

# a tentative definition against a real one elsewhere: one object, initialised
run 'tentative vs definition' 42 \
	'int shared; int f(){ return shared + 2; }' \
	'int shared = 40;'

# two tentative definitions of the same name: both must name the same object
run 'two tentatives' 42 \
	'int shared; int g(); int f(){ shared = 7; return shared + g(); }' \
	'int shared; int g(){ return shared * 5; }'

# a tentative definition with nothing else: still allocated, still zero
run 'tentative alone' 42 \
	'int solo; int f(){ if (solo != 0) return 0; solo = 21; return solo * 2; }' \
	'int other() { return 0; }'

# the same name declared common at two sizes: the larger wins, so writing the
# whole of the larger must not reach the common laid down next to it
run 'size mismatch' 42 \
	'char big[64]; char *tail(); int f(){ int i; char *t; t = tail();
	 for (i = 0; i < 64; i++) big[i] = 1;
	 for (i = 0; i < 8; i++) if (t[i] != 0) return 0;
	 return 42; }' \
	'char big[8]; char after[8]; char *tail(){ return after; }'

# ...and the image must actually reserve the larger size
bss=$("$B/tools/loutid" -s "$T/out" 2>/dev/null | grep -c '^  BSSD .* big_$' || true)
python3 - "$T/out" <<'PY' && pass=$((pass+1)) || { echo "  FAIL bss too small for the larger common"; fail=$((fail+1)); }
import sys
b = open(sys.argv[1], 'rb').read()
pdp = lambda o: (b[o] | b[o+1] << 8) << 16 | (b[o+2] | b[o+3] << 8)
sys.exit(0 if pdp(8 + 4*5) >= 64 + 8 else 1)		# L_BSSD
PY
[ "$bss" = 1 ] || { echo "  FAIL big not in the linked symbol table"; fail=$((fail+1)); }

echo "=== compiled commons: $pass passed, $fail failed ==="
[ "$fail" = 0 ]
