#!/bin/sh
# Execution regression for cc2-z8001: compile a no-argument f() through cc0 -> cc1 ->
# cc2-z8001, link with ld, run it, and require the result to equal a FIXED expected value.
# Every want below was cross-checked against gcc compiling the same body with 16-bit ints
# (short) -- an independent oracle, which is what this gate used to lack: it compared cc2
# against a second implementation of the same backend, so a shared misunderstanding of the
# language would have agreed with itself.  The bodies are chosen to exercise the peephole's
# transforms (store/reload, self-copy, held-operand substitution), which is where an
# encoder-only gate is blind.
H="$(cd "$(dirname "$0")/.." && pwd)"
B="${C900_BUILD:-$H/host/build}"	# the lane's build dir; see host/publish.sh
O="$B/z8001"; AS="$B/as-z8001"
LD="$B/ld-z8001"; N2="${N2:-$(sh "$H/host/runner.sh")}"; VAR=800000000800; PEEP=0010
# No runner, no gate: runner.sh has said why on stderr, and running the cases
# against an empty one scores each missing result as a wrong answer.
[ -n "$N2" ] || exit 2
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '\t.globl\tSS\nSS = 0\n' > "$T/ss.s"; "$AS" -o "$T/ss.o" "$T/ss.s" 2>/dev/null
# soft-float runtime (for the double-return tests, vendored in tests/rt): the routines
# a double program calls -- dadd/drsub, dmul, ddiv, int<->double (itod=diflt, dtoi=dfix).
mkdir -p "$T/fl"
for s in dadd dmul ddiv dcmp itod dtoi ftod dtof; do
	"$AS" -o "$T/fl/$s.o" "$H/tests/rt/$s.s" 2>/dev/null
done
pass=0; fail=0
r1() { "$N2" -runobjint "$1" 2>/dev/null | grep -oE 'signed -?[0-9]+' | grep -oE '\-?[0-9]+'; }
chk() {	# "<function body>" want
	printf 'int f(){ %s }\n' "$1" > "$T/f.c"
	"$O/cc0-z8001" $VAR "$T/f.c" "$T/f.z0" 2>/dev/null
	"$O/cc1-z8001" $VAR "$T/f.z0" "$T/f.z1" 2>/dev/null || { echo "  FAIL(cc1) [$1]"; fail=$((fail+1)); return; }
	"$O/cc2-z8001" $PEEP "$T/f.z1" "$T/c.o" "$T/scr" 0 2>/dev/null || { echo "  FAIL(cc2) [$1]"; fail=$((fail+1)); return; }
	"$LD" -R 0x200 -e f_ -o "$T/ca" "$T/c.o" "$T/ss.o" 2>/dev/null || { echo "  FAIL(ld) [$1]"; fail=$((fail+1)); return; }
	c=$(r1 "$T/ca")
	if [ "$c" = "$2" ]; then pass=$((pass+1))
	else echo "  FAIL [$1] ->[$c] want $2"; fail=$((fail+1)); fi
}

# arithmetic + immediates
chk 'return 5;' 5
chk 'int a,b; a=7; b=3; return a+b;' 10
chk 'int a,b; a=7; b=3; return a-b;' 4
chk 'int a,b; a=6; b=7; return a*b;' 42
chk 'int a,b; a=40; b=6; return a/b;' 6
chk 'int a,b; a=40; b=6; return a%b;' 4
chk 'int a; a=5; return -a;' -5
chk 'int a,b; a=0xF0; b=0x33; return a&b;' 48
chk 'int a,b; a=0xF0; b=0x0F; return a|b;' 255
chk 'int a; a=3; return a<<4;' 48
# peephole-exercising (store/reload, self-copy, held-operand substitution)
chk 'int x,a; x=5; a=x; x=a+1; return a+x;' 11
chk 'int c,x,y; x=8; y=3; c=x; x=y; y=c; return (x-y)&0xFFFF;' -5
chk 'int a,b; a=4; b=5; a=a+b; b=a+4; return a+b;' 22
chk 'int p; p=7; p=p+p; return p;' 14
# control flow
chk 'int a; a=5; if(a>0) return 1; return 0;' 1
chk 'int i,s; s=0; for(i=0;i<5;i=i+1) s=s+i; return s;' 10
chk 'int a; a=10; while(a>3) a=a-1; return a;' 3
chk 'int n; n=4; return n<2 ? n : n*10;' 40
# arrays / pointers / structs
chk 'int a[4],i,s; for(i=0;i<4;i=i+1)a[i]=i*i; s=0; for(i=0;i<4;i=i+1)s=s+a[i]; return s;' 14
chk 'int a[3]; int *p; a[1]=42; p=a; return p[1];' 42
chk 'struct S{int a,b;} s; s.a=3; s.b=4; return s.a+s.b;' 7
# char / mixed width
chk 'char c; c=65; return c+1;' 66
chk 'int a; char b; a=300; b=a; return b&0xFF;' 44
# long (32-bit)
chk 'long x; x=100000L; return (int)(x/7L);' 14285

# Cross-translation-unit linkage: a file-scope global defined in one object must be
# EXPORTED so another object's `extern' reference resolves.  This is a correctness class
# the single-object byte-diff cannot see (and that the old Go n2 gets wrong).
chk2() {	# "<defining source>" "<using source, defines f()>" want
	printf '%s\n' "$1" > "$T/a.c"; printf '%s\n' "$2" > "$T/b.c"
	for u in a b; do
		"$O/cc0-z8001" $VAR "$T/$u.c" "$T/$u.z0" 2>/dev/null
		"$O/cc1-z8001" $VAR "$T/$u.z0" "$T/$u.z1" 2>/dev/null || { echo "  FAIL(cc1) [xtu $u]"; fail=$((fail+1)); return; }
		"$O/cc2-z8001" $PEEP "$T/$u.z1" "$T/$u.o" "$T/scr" 0 2>/dev/null || { echo "  FAIL(cc2) [xtu $u]"; fail=$((fail+1)); return; }
	done
	"$LD" -R 0x200 -e f_ -o "$T/xa" "$T/b.o" "$T/a.o" "$T/ss.o" 2>/dev/null || { echo "  FAIL(ld) [xtu]"; fail=$((fail+1)); return; }
	r=$(r1 "$T/xa")
	if [ "$r" = "$3" ]; then pass=$((pass+1)); else echo "  FAIL xtu cc2=[$r] want $3  [$2]"; fail=$((fail+1)); fi
}
chk2 'int g; int setg(){ g = 42; return 0; }' \
     'extern int g; int f(){ setg(); return g; }' 42
chk2 'int gv[4]; void init(){ int i; for(i=0;i<4;i=i+1) gv[i]=i*10; }' \
     'extern int gv[4]; extern void init(); int f(){ init(); return gv[3]; }' 30
chk2 'char gc; int setc(){ gc = 7; return 0; }' \
     'extern char gc; int f(){ setc(); return gc + 1; }' 8

# Double/float soft-float path (regressions: negate, compound-assign, double
# CONSTANT format/byte-order + int<->double conversion, double return through a call).
# The full source defines f() returning an INT (the double is cast back so the result lands
# in R1); it links the soft-float runtime.  Checked against a fixed WANT (true correctness,
# not just cc2==Go).  A double-returning helper is DECLARED so the (int) conversion is emitted.
chkd() {	# "<full source with int f()>" want
	printf '%s\n' "$1" > "$T/d.c"
	"$O/cc0-z8001" $VAR "$T/d.c" "$T/d.z0" 2>/dev/null
	"$O/cc1-z8001" $VAR "$T/d.z0" "$T/d.z1" 2>/dev/null || { echo "  FAIL(cc1) [dbl]"; fail=$((fail+1)); return; }
	"$O/cc2-z8001" $PEEP "$T/d.z1" "$T/d.o" "$T/scr" 0 2>/dev/null || { echo "  FAIL(cc2) [dbl]"; fail=$((fail+1)); return; }
	"$LD" -R 0x200 -e f_ -o "$T/da" "$T/d.o" "$T/ss.o" "$T"/fl/*.o 2>/dev/null || { echo "  FAIL(ld) [dbl]"; fail=$((fail+1)); return; }
	r=$(r1 "$T/da")
	if [ "$r" = "$2" ]; then pass=$((pass+1)); else echo "  FAIL dbl cc2=[$r] want $2  [$1]"; fail=$((fail+1)); fi
}
chkd 'int f(){ double d; d = 2.5; d = d + 1.5; return (int)d; }' 4			# double constant + add
chkd 'int f(){ double d; d = 3.0; d = d * 2.0; return (int)d; }' 6			# double constant *
chkd 'int f(){ double d; int i; i = 7; d = i; d = d / 2.0; return (int)(d * 10.0); }' 35	# int->double, /, back
chkd 'int f(){ double d; d = 5.0; d *= 2.0; return (int)d; }' 10				# compound-assign
chkd 'int f(){ double d; d = 3.0; d = -d; return (int)-d; }' 3				# negate (twice)
chkd 'int f(){ double d; d = 0.1; return (int)(d * 100.0 + 0.5); }' 10			# non-trivial mantissa
chkd 'double g(); int f(){ double d; d = g(); return (int)(d * 2.0); } double g(){ return 2.5; }' 5   # double return through a call

echo "=== cc2 execution regression: $pass passed, $fail failed ==="
[ "$fail" = 0 ]
