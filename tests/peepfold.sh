#!/bin/sh
# peepfold.sh -- the peephole folds that shorten call sequences and updates.
#
#   LD R0,src ; PUSH R0     -> PUSH src	(and LDL/PUSHL; PUSHL has no immediate)
#   EXTSB Rn ; AND Rn,#k<0x100 -> AND Rn,#k
#   LD R0,M ; INC R0,#n ; LD M,R0 -> INC M,#n	(not for volatile M)
#   INC R15,#a ... INC R15,#b -> ... INC R15,#a+b
#
# Each case checks the shape, then the program runs and prints what it computed.

set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"; CC1="$BUILD/z8001/cc1-z8001"
CC2="$BUILD/z8001/cc2-z8001"; DIS="$BUILD/tools/loutdis"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/f.c" <<'EOF'
int gi = 5; long gl = 70000L; volatile int vi = 9;
int seen[16]; long lseen[16]; int ns, nls;
f1(x) { seen[ns++] = x; }
f2(x) long x; { lseen[nls++] = x; }
pw() { f1(gi); }
px(x) { f1(x); }
pr(x) { register int r; r = x * 3; f1(r); f1(r); }
pl() { f2(gl); }
plx(l) long l; { f2(l); }
pli(p) long *p; { f2(*p); }
pk() { f2(3L); }
ext(c) char c; { return (c & 0xff); }
ext7(c) char c; { return (c & 0x7f); }
incg(p) int *p; { gi += 3; *p -= 2; f1(0); }
volg() { vi += 3; }
pop() { f2(1L); f2(2L); }
id(x) long x; { return ((int)x); }
add3(a, b, c) { return (a*100 + b*10 + c); }
nest() { return (add3(id(1L), id(2L), id(3L))); }	/* args pending across calls */
EOF
"$CC0" $VAR "$T/f.c" "$T/f.z0" && "$CC1" $VAR "$T/f.z0" "$T/f.z1" &&
"$CC2" 0012 "$T/f.z1" "$T/f.o" "$T/f.scr" 0 || { echo "  peepfold: compile FAIL"; exit 1; }

shape() { # <fn> <what> <egrep that must match> <egrep that must not>
	d=$("$DIS" -v -fn "$1" "$T/f.o" 2>/dev/null)
	if printf '%s\n' "$d" | grep -Eq "$3" && ! printf '%s\n' "$d" | grep -Eq "$4"; then
		printf '  %-6s %-14s PASS\n' "$1" "$2"
	else
		printf '  %-6s %-14s FAIL\n' "$1" "$2"
		printf '%s\n' "$d" | sed 's/^/      /'
		fail=1
	fi
}
shape pw_   'push DA'      'PUSH +@R15,0x[0-9A-F]+:0x[0-9A-F]+$' '@R15,R0$'
shape px_   'push X'       'PUSH +@R15,0x[0-9A-F:x]+\(R13\)'    '@R15,R0$'
shape pr_   'push R'       'PUSH +@R15,R([1-9]|1[0-2])$'         '@R15,R0$'
shape pl_   'pushl DA'     'PUSHL +@R15,0x[0-9A-F]+:0x[0-9A-F]+$' 'LDL +RR0'
shape plx_  'pushl X'      'PUSHL +@R15,0x[0-9A-F:x]+\(R13\)'   'LDL +RR0'
shape pli_  'pushl IR'     'PUSHL +@R15,@RR[0-9]+$'             'LDL +RR0,@'
shape pk_   'pushl imm'    'LDL +RR0,#'                         'NEVER'
shape ext_  'extsb/and'    'AND +R[0-9]+,#0x00FF'               'EXTSB'
shape ext7_ 'extsb/and'    'AND +R[0-9]+,#0x007F'               'EXTSB'
shape incg_ 'inc DA'       'INC +0x[0-9A-F]+:0x[0-9A-F]+,#3'    'LD +R0,0x'
shape incg_ 'dec @RR'      'DEC +@RR?[0-9]+,#2'                 'LD +R0,@'
shape volg_ 'volatile'     'LD +R0,0x'                          'INC +0x'
shape pop_  'pop merge'    'INC +R15,#8'                        'INC +R15,#4'

# ... and the values.
[ -n "$N2" ] || { echo "  peepfold: no guest runner"; exit 2; }
cp "$T/f.c" "$T/r.c"
cat >> "$T/r.c" <<'EOF'
#include <stdio.h>
main() {
	long l; int i, a;
	l = 123456L; a = 40;
	pw(); px(-7); pr(4); pl(); plx(-5L); pli(&l); pk();
	i = ext(-3) + ext7(-3);
	incg(&a); volg(); pop();
	printf("%d %d %d %d %d | %ld %ld %ld %ld %ld %ld | %d %d %d %d %d\n",
		seen[0], seen[1], seen[2], seen[3], seen[4],
		lseen[0], lseen[1], lseen[2], lseen[3], lseen[4], lseen[5],
		i, gi, a, vi, nest());
}
EOF
"$CCZ" -o "$T/r" "$T/r.c" >/dev/null 2>&1 || { echo "  peepfold: link FAIL"; exit 1; }
got=$("$N2" -runexec "$T/r" 2>/dev/null) || true
want="5 -7 12 12 0 | 70000 -5 123456 3 1 2 | 378 8 38 12 123"
if [ "$got" = "$want" ]; then
	echo "  values               PASS"
else
	echo "  values               FAIL got=[$got] want=[$want]"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== peepfold: FAIL ==="; exit 1; }
echo "=== peepfold: PASS ==="
