#!/bin/sh
# segrun.sh -- MULTI-SEGMENT execution gate.  Links each program BOTH flat (ld -R 0x200,
# code in segment 0) AND at the real Coherent user base (no -R -> ld userbase = segment 3),
# runs both through the sim (-runobjint), and requires the seg-3 result to equal the flat
# result AND a fixed expected value.  This protects the segmented run path (runsim.go segImage:
# code loaded into its segment, cross-segment CALL from the seg-0 stub, stack in segment 0).
#
# cc2 emits segmented LR_LONG relocations (Phase 2), so globals, cross-function calls, and
# far-pointers-to-global relocate correctly at a nonzero segment: their CALL/data operands
# carry the real segment (e.g. 0x03:...) while frame access stays seg-0 short-form X-mode.
H="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/donor.sh"
B="${C900_BUILD:-$H/host/build}"	# the lane's build dir; see host/publish.sh
O="$B/z8001"; AS="$B/as-z8001"
LD="$B/ld-z8001"; N2="${N2:-$(sh "$H/host/runner.sh")}"; VAR=800000020800; PEEP=0010
# loutdis is RESOLVED, not guessed at: it lives in c900oses/gotools (it decodes
# through the private simulator), and host/loutdis.sh finds or builds it and
# names the variable to set when it cannot.  A hardcoded path to a tool that is
# not there silently empties `es' and fails every case as a wrong ANSWER.
LOUTDIS=$(sh "$H/host/loutdis.sh")
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '\t.globl\tSS\nSS = 0\n' > "$T/ss.s"; "$AS" -o "$T/ss.o" "$T/ss.s" 2>/dev/null
pass=0; fail=0
r1() { "$N2" -runobjint "$1" 2>/dev/null | grep -oE 'R1 = -?[0-9]+' | grep -oE '\-?[0-9]+$'; }
chk() {	# "<function body>" want
	printf 'int f(){ %s }\n' "$1" > "$T/f.c"
	"$O/cc0-z8001" $VAR "$T/f.c" "$T/f.z0" 2>/dev/null
	"$O/cc1-z8001" $VAR "$T/f.z0" "$T/f.z1" 2>/dev/null || { echo "  FAIL(cc1) [$1]"; fail=$((fail+1)); return; }
	"$O/cc2-z8001" $PEEP "$T/f.z1" "$T/c.o" "$T/scr" 0 2>/dev/null || { echo "  FAIL(cc2) [$1]"; fail=$((fail+1)); return; }
	"$LD" -R 0x200 -e f_ -o "$T/flat" "$T/c.o" "$T/ss.o" 2>/dev/null
	"$LD"          -e f_ -o "$T/seg3" "$T/c.o" "$T/ss.o" 2>/dev/null	# no -R -> userbase (seg 3)
	# confirm the seg-3 link really placed the entry in segment 3
	es=$("$LOUTDIS" -hdr "$T/seg3" 2>/dev/null | grep -oE 'entry=0x[0-9a-f]+')
	f=$(r1 "$T/flat"); s=$(r1 "$T/seg3")
	if [ "$es" != "entry=0x3000000" ]; then echo "  FAIL seg-3 link base=[$es] [$1]"; fail=$((fail+1)); return; fi
	if [ -n "$s" ] && [ "$s" = "$f" ] && [ "$s" = "$2" ]; then pass=$((pass+1))
	else echo "  FAIL flat=[$f] seg3=[$s] want $2  [$1]"; fail=$((fail+1)); fi
}

chk 'return 5;' 5
chk 'int a,b; a=7; b=3; return a*b+1;' 22
chk 'int a,b; a=40; b=6; return a/b;' 6
chk 'int i,s; s=0; for(i=0;i<5;i=i+1) s=s+i; return s;' 10
chk 'int a; a=10; while(a>3) a=a-1; return a;' 3
chk 'int n; n=4; return n<2 ? n : n*10;' 40
chk 'int a[4],i,s; for(i=0;i<4;i=i+1)a[i]=i*i; s=0; for(i=0;i<4;i=i+1)s=s+a[i]; return s;' 14
chk 'long x; x=100000L; return (int)(x/7L);' 14285

# Regression: long-CONSTANT stores through a pointer.  The i8086
# word-split used to emit near stores through the far pointer's halves
# (CLR @Rseg twice for 0L; a seg-0 X-mode for other constants) -- correct
# results ONLY under a flat link, silently wrong at seg 3.  These compare
# flat vs seg-3, which is exactly the discriminator.
chk 'long v; long *p; v=1L; p=&v; *p=0L; return (int)v;' 0
chk 'long v; long *p; v=1L; p=&v; *p=5L; return (int)v;' 5
chk 'long a[3]; long *p; int i; for(i=0;i<3;i=i+1)a[i]=1L; p=a; p[1]=7L; p[2]=0L; return (int)(a[0]+a[1]+a[2]);' 8

# (byte-cast-of-regvar + long->byte narrowing are verified end-to-end
# by rogue and tests/curses-games; the -runobjint chk harness mis-handles
# byte globals so they cannot live here.)

# Segmented address operands: globals, a far pointer to a global, and a cross-function call
# (whose CALL/data operands carry the real segment via the LR_LONG relocation).
whole() {	# "<full source with int f() + helpers/globals>" want
	printf '%s\n' "$1" > "$T/w.c"
	"$O/cc0-z8001" $VAR "$T/w.c" "$T/w.z0" 2>/dev/null
	"$O/cc1-z8001" $VAR "$T/w.z0" "$T/w.z1" 2>/dev/null || { echo "  FAIL(cc1) [whole]"; fail=$((fail+1)); return; }
	"$O/cc2-z8001" $PEEP "$T/w.z1" "$T/w.o" "$T/scr" 0 2>/dev/null || { echo "  FAIL(cc2) [whole]"; fail=$((fail+1)); return; }
	"$LD" -R 0x200 -e f_ -o "$T/flat" "$T/w.o" "$T/ss.o" 2>/dev/null
	"$LD"          -e f_ -o "$T/seg3" "$T/w.o" "$T/ss.o" 2>/dev/null
	es=$("$LOUTDIS" -hdr "$T/seg3" 2>/dev/null | grep -oE 'entry=0x3[0-9a-f]+')
	fl=$(r1 "$T/flat"); s=$(r1 "$T/seg3")
	if [ -z "$es" ]; then echo "  FAIL seg-3 entry not in seg 3 [whole]"; fail=$((fail+1)); return; fi
	if [ -n "$s" ] && [ "$s" = "$fl" ] && [ "$s" = "$2" ]; then pass=$((pass+1))
	else echo "  FAIL flat=[$fl] seg3=[$s] want $2  [whole]"; fail=$((fail+1)); fi
}
whole 'int gv; int f(){ gv = 99; return gv + 1; }' 100
whole 'int gv[4]; int addit(x) int x; { return x + gv[3]; }
       int f(){ int i; for(i=0;i<4;i=i+1) gv[i]=i*10; return addit(5); }' 35
whole 'int gv; int *gp; int f(){ gv = 7; gp = &gv; *gp = *gp + 5; return gv; }' 12
whole 'int sq(n) int n; { return n*n; } int f(){ return sq(6) + sq(2); }' 40
# Pointer-to-symbol STATIC INITIALIZERS: must bake the inline far-ptr, not a pooled
# double-pointer.  Covers &data, &initialized-data, and &function initializers.
whole 'int gv; int *gp = &gv; int f(){ gv = 42; return *gp; }' 42
whole 'int gv = 7; int *gp = &gv; int f(){ return *gp + 1; }' 8
whole 'int gg() { return 9; } int (*fpg)() = gg; int f(){ return (*fpg)(); }' 9
whole 'int a[3]; int *ap = a; int f(){ a[1] = 55; return ap[1]; }' 55
# Far-pointer STORE-IMMEDIATE at a nonzero offset: must keep the segment (@RRn),
# not fall to seg-0 X-mode.  Flat-vs-seg3 mismatch caught the segment drop.
whole 'int gv[4]; int f(){ int *p; p=gv; p[1]=42; p[2]=43; return p[1]+p[2]; }' 85
whole 'char gb[4]; int f(){ char *p; p=gb; p[1]=65; p[2]=66; return p[1]+p[2]; }' 131
# char postinc value in a truth test: `if(c++)' promotes the OLD byte to a word,
# so the byte load must extend through the high byte -- else a stale high byte (here from
# the preceding roundup leaving 0x01 in the reg) makes the word TEST spuriously non-zero.
whole 'char sb; int f(){ unsigned s; s=(0x100+15)&~7; if(sb++) return 999; return (int)s; }' 264
# far-pointer ++/-- by an element > 16 bytes: the Z8000 INC/DEC count
# is a 4-bit field (1..16), so `vp++' on a 20-byte struct stepped by count&15
# (INC #4) -- the cc2 incexpand peephole widens a >16 step back to a full ADD/SUB.
# 16 keeps the compact INC (fits the nibble); 20 must widen.  Effect, value-postfix,
# and prefix contexts all share the increment, so all three are covered.
whole 'struct s{char b[16];}; struct s a[3]; struct s *vp; int f(){ vp=a; vp++; return (int)((char*)vp-(char*)a); }' 16
whole 'struct s{char b[20];}; struct s a[3]; struct s *vp; int f(){ vp=a; vp++; return (int)((char*)vp-(char*)a); }' 20
whole 'struct s{char b[20];}; struct s a[3]; struct s *vp,*r; int f(){ vp=a; r=vp++; return (int)((char*)r-(char*)a)*1000+(int)((char*)vp-(char*)a); }' 20
whole 'struct s{char b[40];}; struct s a[3]; struct s *vp; int f(){ vp=&a[2]; --vp; return (int)((char*)vp-(char*)a); }' 40
# aggregate copy from a POINTER-DEREFERENCE source: `dst = q[i]' / `dst = *q'
# copies a struct/union word by word; the per-word re-evaluation of the far-pointer
# source address used to re-deref the base register (reading *q as an address) so only
# the first word was right.  Bind &src into a temp once.  A static array source `arr[i]'
# is addressed by a constant base and is unaffected.  Value here is dst's second word
# (an int at offset 2 after a char*): the miscompile left it 0.
whole 'struct s{char *p; int x;}; struct s dst,a[4],*q; int f(){ a[1].x=77; q=a; dst=q[1]; return dst.x; }' 77
whole 'struct s{char *p; int x;}; struct s dst,a[4],*q; int f(){ a[0].x=55; q=a; dst=*q; return dst.x; }' 55
# store an immediate FAR POINTER at a NEGATIVE index through a register far pointer
# (sh's makargl `app[-1] = p'): the EA-immediate store has no BA form, so genins steps
# the pair's offset register to the operand -- the step can be negative (offset DOWN),
# which irstep used to botch ("@RR+disp step out of range", 575B).  slots[1] gets the
# value stored via slots[2]-relative [-1]; return marks correct placement.
whole 'char *slots[4]; int f(){ register char **p; p=&slots[2]; p[-1]=(char*)0x1234; p[0]=(char*)0x5678; return (slots[1]==(char*)0x1234 && slots[2]==(char*)0x5678)?42:0; }' 42
# a far-pointer REGVAR passed as a call argument: the regvar is already a
# materialized pair, so no PFNARG rule survives outtree for the bare REG leaf --
# output()->outtree derefs its garbage t_lp.  outmch.c outargs PUSHLs the live
# pair directly.  first(q)=77,
# first(q+3)=33 -> 77 + 33*100.
whole 'char buf[8]; int first(p) char *p; { return p[0]; } int f(){ register char *q; int i; q=buf; for(i=0;i<8;i++)q[i]=0; q[0]=77; q[3]=33; return first(q)+first(q+3)*100; }' 3377

# Whole-toolchain at seg 3: a bare f() that calls into the libc archive (cross-object calls +
# string literal in data, all in segment 3).  No crt0/syscalls -- runObjInt calls f() directly.
INC="$Z8001_DONOR/include"; LIBC="$B/libc-z8001"
libc() {	# "<source with int f()>" want
	printf '%s\n' "$1" > "$T/lc.c"
	"$O/cc0-z8001" $VAR "$T/lc.c" "$T/lc.z0" -I"$INC" 2>/dev/null
	"$O/cc1-z8001" $VAR "$T/lc.z0" "$T/lc.z1" 2>/dev/null || { echo "  FAIL(cc1) [libc]"; fail=$((fail+1)); return; }
	"$O/cc2-z8001" $PEEP "$T/lc.z1" "$T/lc.o" "$T/scr" 0 2>/dev/null || { echo "  FAIL(cc2) [libc]"; fail=$((fail+1)); return; }
	"$LD" -R 0x200 -e f_ -o "$T/flat" "$T/lc.o" "$T/ss.o" "$LIBC/libc-z8001.a" 2>/dev/null
	"$LD"          -e f_ -o "$T/seg3" "$T/lc.o" "$T/ss.o" "$LIBC/libc-z8001.a" 2>/dev/null
	es=$("$LOUTDIS" -hdr "$T/seg3" 2>/dev/null | grep -oE 'entry=0x3[0-9a-f]+')
	fl=$(r1 "$T/flat"); s=$(r1 "$T/seg3")
	if [ -z "$es" ]; then echo "  FAIL seg-3 entry not in seg 3 [libc]"; fail=$((fail+1)); return; fi
	if [ -n "$s" ] && [ "$s" = "$fl" ] && [ "$s" = "$2" ]; then pass=$((pass+1))
	else echo "  FAIL flat=[$fl] seg3=[$s] want $2  [libc]"; fail=$((fail+1)); fi
}
if [ -f "$LIBC/libc-z8001.a" ]; then
	libc 'int f(){ char *s; int n; s="hello"; n=strlen(s); if(strcmp(s,"hello")==0) n=n+100; return n; }' 105
	libc 'int f(){ char b[8]; strcpy(b,"abc"); return strlen(b); }' 3
	# float compound-assign: `d *= x' had no F64 rule and no makecall
	# (only binary float ops makecall), so it "no match"ed (EDFA69, hit by printf's
	# _dtoa `d *= _powtab[i]').  modoper now expands `d op= x' -> `d = d <op> x'.
	libc 'int f(){ double d; d=1.0; d*=100.0; d+=7.0; d-=3.0; d/=4.0; return (int)d; }' 26
	libc 'int f(){ double d; static double t[3]; t[2]=100.0; d=2.0; d*=t[2]; return (int)d; }' 200
fi

echo "=== multi-segment (seg-3) execution: $pass passed, $fail failed ==="
[ "$fail" = 0 ]
