#!/bin/sh
# Z8001 codegen regression: compile a C snippet through the WHOLE shipped toolchain --
# cc0-z8001 -> cc1-z8001 -> cc2-z8001 -> ld-z8001 -> execute (host/runner.sh, the C
# emulator; no simulator is involved in this or any other gate here) --
# and assert the returned R1.  Nothing here reads a compiler's in-memory state: every
# assertion is made against a linked l.out, which is what the machine would run.
# Usage: tests/regress.sh
O=${O:-"${C900_BUILD:-$(cd "$(dirname "$0")/.." && pwd)/host/build}/z8001"}
N2=${N2:-"$(sh "$(cd "$(dirname "$0")/../host" && pwd)/runner.sh")"}
# runner.sh has already explained itself on stderr.  Stop here rather than run
# every case against an empty runner: each one then returns nothing and is
# scored as a wrong ANSWER, so an unset C900_EMU reads as hundreds of compiler
# regressions and the explanation scrolls away above them.
[ -n "$N2" ] || exit 2
VAR=${VAR:-800000000800}
# Scratch files are per-run.  Every case reuses the same three names, so two
# runs sharing them interleave and answer from each other's intermediate files
# -- which reads as a wrong RESULT ("->[-33] want 42") rather than an error.
RG=${TMPDIR:-/tmp}/rg.$$
trap 'rm -f "$RG".*' EXIT INT TERM
# PROVENANCE FIRST, before any result.  md5sums below say the binaries are the
# same or different; they do not say what SOURCE they came from, and a toolchain
# built from a working tree with uncommitted edits in it is the one failure this
# gate cannot distinguish from a real regression.  It has happened: a dirty-tree
# compiler produced a phantom ICE that was relayed to another lane as a source
# bug.  So a dirty toolchain announces itself in line 1, not in an archaeology
# session three lanes later.
. "$(cd "$(dirname "$0")/../host" && pwd)/provenance.sh"
prov_header "toolchain under test" "$O/.provenance" || true
# Same scope as build-cc.sh stamps with, or the two counts are not comparable
# and the difference between them (= the tree moved under the toolchain) is
# unreadable.
prov_now "this tree, now" src/cc src/as src/ld host
# Name the binaries under test, with their identity, so a transcript says what
# it measured.  O and N2 are both overridable and both are shared paths by
# default: a result is only attributable if these are recorded beside it.
echo "== cc: $O"
md5sum "$O"/cc0-z8001 "$O"/cc1-z8001 "$O"/cc2-z8001 2>/dev/null | sed 's/^/   /'
echo "== n2: $N2"
md5sum "$N2" 2>/dev/null | sed 's/^/   /'
pass=0; fail=0
# Every value assertion runs the SHIPPED encoder: cc0 -> cc1 -> cc2-z8001 -> ld -> execute.
# `f' is entered by a stub that pushes the two arguments (one word each; K&R promotes a char
# parameter to int) right-to-left, so they arrive at FP+6/FP+8 exactly as a compiled call site
# delivers them.  This is the whole deliverable pipeline -- object emission, relocation and the
# link included -- not just an encoder's in-memory word stream.
AS=${AS:-"$O/../as-z8001"}; LD=${LD:-"$O/../ld-z8001"}
printf '\t.globl\tSS\nSS = 0\n' > "$RG".ss.s; "$AS" -o "$RG".ss.o "$RG".ss.s 2>/dev/null
# RGTRACE names a file to append one `NNNN PASS|FAIL <case>' line to per value assertion.
# It exists so two runs of this suite can be compared case by case rather than by their
# totals: equal totals do not mean the same cases passed.
rgcase=0
# THE RUNNER IS PROVED BEFORE ANYTHING IS SCORED.  A runner that emits nothing
# makes every value assertion fail and leaves only the assertions that execute
# no code -- so the suite reports a tidy "N passed" that describes the harness
# and not the compiler.  One known answer, checked here; if it does not come
# back, this stops rather than grading 600 cases against silence.
printf 'int f(x,y) int x; int y; { return x+y; }\n' > "$RG".c
# Stderr is KEPT here, unlike in the scored cases: this is the one failure that
# stops the suite, and every pass below it is silenced, so the diagnosis has to
# come from this block or from nowhere.
if { "$O/cc0-z8001" $VAR "$RG".c "$RG".z0 &&
     "$O/cc1-z8001" $VAR "$RG".z0 "$RG".z1 &&
     "$O/cc2-z8001" ${PEEP:-0010} "$RG".z1 "$RG".ro "$RG".rscr 0 &&
     "$LD" -R 0x200 -e f_ -o "$RG".rout "$RG".ro "$RG".ss.o
   } 2>"$RG".pfe; then
	pf=$("$N2" -runobjint "$RG".rout 3 4 2>>"$RG".pfe |
	     grep -oE 'signed -?[0-9]+' | grep -oE '\-?[0-9]+')
else
	pf=
fi
if [ "$pf" != 7 ]; then
	echo "*** regress: the runner did not return 3+4 -- it gave [$pf]." >&2
	echo "***   $N2" >&2
	echo "*** Every value assertion would fail and the only passes would be the" >&2
	echo "*** ones that execute nothing.  Nothing is scored." >&2
	if [ -s "$RG".pfe ]; then
		echo "*** The compile-and-run said:" >&2
		sed 's/^/***   /' "$RG".pfe >&2
	else
		echo "*** Neither the compiler nor the runner said anything." >&2
	fi
	exit 1
fi

chkrun() { # "<label>" a b want   -- the C source is already in $RG.c
  rgcase=$((rgcase+1)); v=FAIL
  # cc0's status is checked like every other pass's.  Unchecked, a cc0 that
  # failed left the PREVIOUS case's $RG.z0 in place and cc1 recompiled that --
  # a wrong answer usually, but a false PASS wherever two consecutive cases
  # expect the same value, which is common here.
  if ! "$O/cc0-z8001" $VAR "$RG".c "$RG".z0 2>/dev/null; then
    echo "  FAIL(cc0) [$1]"; fail=$((fail+1)); rgtrace "$1"; return
  fi
  if ! timeout 5 "$O/cc1-z8001" $VAR "$RG".z0 "$RG".z1 2>/dev/null; then
    echo "  FAIL(cc1) [$1]"; fail=$((fail+1)); rgtrace "$1"; return
  fi
  if ! "$O/cc2-z8001" ${PEEP:-0010} "$RG".z1 "$RG".ro "$RG".rscr 0 2>/dev/null; then
    echo "  FAIL(cc2) [$1]"; fail=$((fail+1)); rgtrace "$1"; return
  fi
  if ! "$LD" -R 0x200 -e f_ -o "$RG".rout "$RG".ro "$RG".ss.o 2>/dev/null; then
    echo "  FAIL(ld) [$1]"; fail=$((fail+1)); rgtrace "$1"; return
  fi
  g=$("$N2" -runobjint "$RG".rout "$2" "$3" 2>/dev/null | grep -oE 'signed -?[0-9]+' | grep -oE '\-?[0-9]+')
  if [ "$g" = "$4" ]; then pass=$((pass+1)); v=PASS
  else echo "  FAIL [$1] ($2,$3)->[$g] want $4"; fail=$((fail+1)); fi
  rgtrace "$1"
}
rgtrace() { # one line per case: id, verdict, and the source with newlines squeezed out
  [ -n "$RGTRACE" ] || return 0
  printf '%04d %s %s\n' "$rgcase" "$v" "$(printf '%s' "$1" | tr '\n\t' '  ')" >> "$RGTRACE"
}
chk() { # "<body>" a b want
  printf 'int f(x,y) int x; int y; { %s }\n' "$1" > "$RG".c
  chkrun "$1" "$2" "$3" "$4"
}
chkf() { # "<full source>" a b want  (for non-int-param signatures, e.g. char)
  printf '%s\n' "$1" > "$RG".c
  chkrun "$1" "$2" "$3" "$4"
}
chkfc() { # "<full source>" [expected-soft-float-symbol]  -- COMPILE-ONLY: these programs
  # need the soft-float runtime to run, so the assertion is that cc1 does not crash and
  # (optionally) that the object cc2 emits actually CALLS the named helper.  The name is
  # read from the object's own symbol table -- an undefined external is stored there as a
  # NUL-padded 16-byte field, so `strings' yields it on a line of its own.
  printf '%s\n' "$1" > "$RG".c
  "$O/cc0-z8001" $VAR "$RG".c "$RG".z0 2>/dev/null \
    || { echo "  FAIL(cc0) [$1]"; fail=$((fail+1)); return; }
  timeout 5 "$O/cc1-z8001" $VAR "$RG".z0 "$RG".z1 2>/dev/null \
    || { echo "  FAIL(cc1 crash) [$1]"; fail=$((fail+1)); return; }
  if [ -z "$2" ]; then pass=$((pass+1)); return; fi
  if ! "$O/cc2-z8001" ${PEEP:-0010} "$RG".z1 "$RG".ro "$RG".rscr 0 2>/dev/null; then
    echo "  FAIL(cc2) [$1]"; fail=$((fail+1)); return
  fi
  if strings -a "$RG".ro | grep -qx "$2"; then pass=$((pass+1));
  else echo "  FAIL(sym) [$1] want $2"; fail=$((fail+1)); fi
}
# The instruction-stream oracle is the toolchain's own passes, not a disassembler.
#
# cc3-z8001 prints the i1 record stream cc1 wrote -- the instruction selection, in the
# operand syntax as-z8001 accepts.  That answers every assertion about WHAT cc1 chose.
# It cannot answer the rest: cc2 rewrites the INS list in its peephole and makes two
# encoding choices below it (LDK for a small immediate, the prologue's frame
# reservation), so a form that only exists after cc2 is invisible to cc3.  For those,
# cc2 prints the same list itself -- `listing()' in n2/z8001/listing.c, selected by
# $CC2LIST, in cc3's syntax so one pattern reads against either dump.
#
# Both dumps are normalised the same way before matching: the leading `NN:' offset is
# dropped and runs of whitespace squeezed to one space, so a pattern spells operand
# separation as a single space regardless of the tab layout.  Patterns anchor at the
# start of the instruction, so `ldl ' cannot be satisfied by an operand that merely
# contains the letters.
#
# The mnemonics come from tables: cc3's is n3/z8001/icode.c's, cc2's is opname[] in
# n2/z8001/optab.c, and `make check-cc3tab' holds icode.c's rows in step with optab.c's
# -- that gate is now load-bearing for the oracle, not just for cc3's readability.  A
# misspelled name would make an absence assertion pass for the wrong reason, so every
# mnemonic asserted absent below is asserted PRESENT somewhere else in this file.
PEEP="${PEEP:-0010}"
rgnorm='s/^[0-9]*:*[	 ]*//; s/[	 ][	 ]*/ /g'
chkfront() { # "<full source>" -- cc0+cc1 into $RG.z1; nonzero return means already failed
  printf '%s\n' "$1" > "$RG".c
  "$O/cc0-z8001" $VAR "$RG".c "$RG".z0 2>/dev/null \
    || { echo "  FAIL(cc0) [$1]"; fail=$((fail+1)); return 1; }
  timeout 5 "$O/cc1-z8001" $VAR "$RG".z0 "$RG".z1 2>/dev/null \
    || { echo "  FAIL(cc1) [$1]"; fail=$((fail+1)); return 1; }
  return 0
}
chkmatch() { # <dump> <regex> yes|no "<label>" <oracle>
  # An EMPTY dump is not an absence, it is a missing oracle: an absence
  # assertion over no text at all passes for the wrong reason, and half the
  # assertions below are absences.  cc3 exiting nonzero, or being absent from
  # $O entirely, produces exactly that.
  if [ -z "$1" ]; then
    echo "  FAIL($5) [$4] the $5 oracle produced no output"; fail=$((fail+1)); return
  fi
  # The oracle's stdout is a TEXT stream, so on Windows every line arrives
  # ending CR LF.  A pattern anchored with `$' then matches nothing, and one
  # anchored absence would report absent for the wrong reason.  tr rather than a
  # sed escape: \r is a GNU extension.
  if printf '%s\n' "$1" | tr -d '\015' | sed "$rgnorm" | grep -qE "^$2"; then got=yes; else got=no; fi
  if [ "$got" = "$3" ]; then pass=$((pass+1));
  else echo "  FAIL($5) [$4] $2 present=$got want=$3"; fail=$((fail+1)); fi
}
chkdis() { # "<full source>" <i1-regex> yes|no  -- assert against cc3's selection dump
  chkfront "$1" || return
  chkmatch "$("$O/cc3-z8001" $VAR "$RG".z1 2>/dev/null)" "$2" "$3" "$1" dis
}
chklist() { # "<full source>" <listing-regex> yes|no  -- assert against cc2's emit listing
  chkfront "$1" || return
  lst=$(CC2LIST=1 "$O/cc2-z8001" $PEEP "$RG".z1 "$RG".o "$RG".scr 2>/dev/null) \
    || { echo "  FAIL(cc2) [$1]"; fail=$((fail+1)); return; }
  chkmatch "$lst" "$2" "$3" "$1" list
}
# arithmetic
chk 'return x + y;' 3 4 7;   chk 'return x - y;' 9 4 5;   chk 'return x & y;' 6 3 2
chk 'return x | y;' 4 1 5;   chk 'return x ^ y;' 6 3 5;   chk 'return x + y + y;' 5 2 9
chk 'return x + 5;' 3 0 8;   chk 'return x - y - y;' 10 3 4
# locals / stores
chk 'int z; z = x + y; return z;' 5 3 8
chk 'int z; z = x - y; return z;' 9 2 7
chk 'int a; int b; a = x; b = y; return a + b;' 6 7 13
# comparisons (return 1/0)
chk 'if (x > y) return 1; return 0;' 5 3 1;  chk 'if (x > y) return 1; return 0;' 3 5 0
chk 'if (x < y) return 1; return 0;' 3 5 1;  chk 'if (x == y) return 1; return 0;' 4 4 1
chk 'if (x != y) return 1; return 0;' 4 5 1; chk 'if (x >= y) return 1; return 0;' 5 5 1
chk 'if (x <= y) return 1; return 0;' 6 5 0
# truth test
chk 'if (x) return 1; return 0;' 5 0 1;  chk 'if (x) return 1; return 0;' 0 0 0
chk 'if (!x) return 1; return 0;' 0 0 1
# conditional value
chk 'if (x > y) return x; return y;' 5 3 5;  chk 'if (x > y) return x; return y;' 2 9 9
# inc/dec (Phase 2)
chk '++x; return x;' 5 0 6;  chk '--x; return x;' 5 0 4
chk 'return x++;' 5 0 5;     chk 'return x--;' 5 0 5
# loops (Phase 2)
chk 'int i; i = 0; while (i < x) i++; return i;' 5 0 5
chk 'int s; s = 0; while (x) { s = s + x; x--; } return s;' 4 0 10
chk 'int i; int s; s = 0; for (i = 0; i < x; i++) s = s + i; return s;' 5 0 10
# assignment (Phase 4)
chk 'int a; a = x; return a;' 6 7 6
chk 'int a; a = 0; return a;' 5 0 0
chk 'int a; a = 42; return a;' 0 0 42
chk 'int a; int b; a = x; b = a; return b;' 9 0 9
chk 'int a; int b; b = a = x; return a + b;' 5 0 10
chk 'int t; t = x; x = y; y = t; return x - y;' 9 2 -7
# char/byte assignment (Phase 4)
chkf 'int f(x,y) char x; char y; { char a; a = x; return a; }' 65 0 65
chkf 'int f(x,y) char x; char y; { char a; char b; a = x; b = a; return b; }' 7 0 7
chkf 'int f(x,y) unsigned char x; unsigned char y; { unsigned char a; unsigned char b; a = x; b = a; return b; }' 200 0 200
# struct field access + inline block copy (Phase 4 / field fix)
chkf 'struct P{int a;int b;}; int f(){ struct P q; q.a=5; q.b=9; return q.b; }' 0 0 9
chkf 'struct P{int a;int b;}; int f(){ struct P q; q.a=5; q.b=9; return q.a; }' 0 0 5
chkf 'struct P{int a;int b;}; int f(){ struct P p,q; q.a=5; q.b=9; p=q; return p.b; }' 0 0 9
chkf 'struct P{int a;int b;int c;}; int f(){ struct P q; q.c=42; return q.c; }' 0 0 42
# function calls (args, return, recursion, cleanup)
chkf 'int g(x) int x; { return x+1; } int f() { return g(41); }' 0 0 42
chkf 'int g(a,b) int a; int b; { return a-b; } int f() { return g(20,8); }' 0 0 12
chkf 'int add(a,b) int a; int b; { return a+b; } int f() { return add(add(1,2),add(3,4)); }' 0 0 10
chkf 'int cd(n) int n; { if (n<=0) return 7; return cd(n-1); } int f(k) int k; { return cd(k); }' 5 0 7
chkf 'int sum(n) int n; { if (n==0) return 0; return n+sum(n-1); } int f(k) int k; { return sum(k); }' 4 0 10
# constant call arguments push the immediate directly (PUSH @R15,#imm, no temp load);
# the IMM|MMX predicate must NOT fold a variable/expression arg (g(n) below stays a load+push).
chkf 'int g(a,b) int a; int b; { return a+b; } int f() { return g(10,32); }' 0 0 42
chkf 'int g(a,b) int a; int b; { return a-b; } int f(n) int n; { return g(n,5); }' 30 0 25
chkf 'int g(a,b,c) int a; int b; int c; { return a*100+b*10+c; } int f() { return g(1,2,3); }' 0 0 123
chkf 'int g(x) int x; { return x; } int f(n) int n; { return g(n)+g(7); }' 4 0 11
# post-call SP cleanup uses INC R15,#nb for nb<=16; a >8-arg call (nb=18) keeps ADD.
# Both must restore SP correctly -- a wrong adjust corrupts the caller's frame.
chkf 'int s9(a,b,c,d,e,f,g,h,i) int a,b,c,d,e,f,g,h,i; { return a+b+c+d+e+f+g+h+i; } int f() { return s9(1,2,3,4,5,6,7,8,9); }' 0 0 45
chkf 'int g(a,b,c,d) int a,b,c,d; { return a*8+b*4+c*2+d; } int f(n) int n; { return g(n,n,n,n)+g(1,2,3,4); }' 1 0 41
# ADD/SUB Rn,#1..16 -> INC/DEC Rn,#k: same value + S/Z/V, NOT carry, so only
# converted where carry is dead.  These exercise convert-then-return, -in-loop, and a
# loop whose unsigned-compare back-edge (carry cc, after a CP) must keep the value right.
chk 'return x+5;' 10 0 15;        chk 'return x-3;' 10 0 7
# simpoper: a binary ALU op's held memory SOURCE reads the register instead
# (g+g -> LD R1,g; ADD R1,R1, dropping the 2nd g's address words).  Must stay correct;
# op#0 (an INC/DEC of memory) is NEVER substituted (that would increment a register).
chkf 'int g; int f(x) int x; { g=x; return g + g; }' 5 0 10
chkf 'int g; int f(x) int x; { g=x; return g - g; }' 7 0 0
chkf 'int g; int h; int f(x) int x; { g=x; h=x+1; return g + h + g; }' 5 0 16
# far-field at a nonzero offset as a direct ALU operand (the col.c PutHalf idiom:
# lp->line[c] indexes a far-ptr field of a regvar struct -> ADD Rd,@RR+4, which has no
# Z8000 BA form).  n2 materializes it (PUSH scratch; LD scratch,off(@RR); OP Rd,scratch;
# POP scratch) -- the original loads into a temp; this must compute + restore correctly.
chkf 'struct L { int len; char *line; }; int f(x) int x; { char buf[4]; struct L rec; register struct L *lp; int c; int s; buf[0]=x;buf[1]=x+1;buf[2]=x+2;buf[3]=0; rec.len=3;rec.line=buf;lp=&rec; s=0; for(c=0;c<lp->len;c++) s=s+lp->line[c]; return s; }' 5 0 18
chkf 'int f(x) int x; { int i; int s; s=0; for(i=0;i<x;i=i+2) s=s+i; return s; }' 8 0 12
chkf 'int f(x) unsigned x; { unsigned i; int s; s=0; for(i=1;i<=x;i=i+3) s=s+1; return s; }' 10 0 4
chkf 'int f(x) int x; { int v[4]; int *p; int s; int i; for(i=0;i<4;i=i+1) v[i]=i+1; p=v; s=0; for(i=0;i<4;i=i+1){ s=s+ *p; p=p+1; } return s+x; }' 0 0 10
# >=3 callee saves use one STM/LDM over the used range, with the area folded
# into the frame SUB; 3 far-ptr locals held across a call force RR6/RR8/RR10 -> STM.
# Restore must reload them from the frame before LD R15,R13 tears it down.
chkf 'int e() { return 0; } int f(x) int x; { int p[2]; int q[2]; int r[2]; int *a; int *b; int *c; p[0]=x;q[0]=x+1;r[0]=x+2; a=p;b=q;c=r; e(); return *a + *b + *c; }' 10 0 33
# far pointers (VLARGE model: address-of, deref load/store, args, swap)
chkf 'int f(x) int x; { int *p; p=&x; return *p; }' 6 0 6
chkf 'int f(x) int x; { int *p; p=&x; *p=9; return x; }' 7 0 9
chkf 'int f(x) int x; { int *p; p=&x; *p=*p+1; return x; }' 5 0 6
chkf 'int g(p) int *p; { return *p; } int f(x) int x; { return g(&x); }' 8 0 8
chkf 'int f(x) int x; { int *p; int **pp; p=&x; pp=&p; return **pp; }' 7 0 7
chkf 'int sw(a,b) int *a; int *b; { int t; t=*a; *a=*b; *b=t; return 0; } int f(x,y) int x; int y; { sw(&x,&y); return x-y; }' 3 8 5
# sign correctness: unary neg/not (P_SLT share-left-temp), signed mul/div/rem with
# negatives, unsigned div/rem (CLR zero-extend, kept unsigned through return-coerce)
chk 'return -x;' 20 9 -20;        chk 'return -x;' -7 4 7
chk 'return ~x;' 5 8 -6;          chk 'return ~x;' 0 0 -1
chk 'return -x/y;' 20 3 -6;       chk 'return -(x-y);' 3 10 7
chk 'return x*y;' -6 7 -42;       chk 'return x*y;' -6 -7 42
chk 'return x/y;' -20 3 -6;       chk 'return x%y;' -20 3 -2
chk 'return x/y;' 20 -3 -6;       chk 'return x%y;' -20 -3 -2
chkf 'int f(x,y) unsigned x; unsigned y; { return x/y; }' 40000 2 20000
chkf 'int f(x,y) unsigned x; unsigned y; { return x%y; }' 40001 2 1
chkf 'int f(x,y) unsigned x; unsigned y; { return x/y; }' 60000 7 8571
chkf 'int f(x,y) unsigned x; unsigned y; { return x%y; }' 60000 7 3
chkf 'int f(x,y) unsigned x; unsigned y; { unsigned z; z=x/y; return z; }' 40000 2 20000
# shifts (Phase 6): Z8000 SHIFT = SLL/SLA opcode + signed count (negative => right;
# decoder infers SRL/SRA).  Constant count -> static immediate; variable -> dynamic
# SDL/SDA (right shift needs a runtime NEG of the count).  signed >> = arithmetic
# (sign-filling SRA); unsigned >> = logical (zero-filling SRL).
chk 'return x << 1;' 12 3 24;     chk 'return x << 3;' 5 3 40
chk 'return x >> 1;' 13 3 6;      chk 'return x >> 2;' -40 3 -10
chk 'return x << y;' 5 3 40;      chk 'return x >> y;' 40 2 10
chk 'return x >> y;' -40 2 -10;   chk 'return x * 2;' 7 3 14
chkf 'int f(x,y) unsigned x; unsigned y; { return x >> 1; }' 40000 3 20000
chkf 'int f(x,y) unsigned x; unsigned y; { return x >> 3; }' 40000 3 5000
chkf 'int f(x,y) unsigned x; unsigned y; { return x >> y; }' 40000 2 10000
chkf 'int f(x,y) unsigned x; unsigned y; { unsigned z; z = x >> 2; return z; }' 40000 3 10000
# compound assignment (Phase 7): Z8000 arithmetic is register-dest only, so x op= y
# is load-modify-store (LD Rt,x; OP Rt,y; LD x,Rt).  mul/div/rem use the fixed RR0/R1
# pair + sign extend.  Result temp also carries the rvalue (z=(x+=..)) and tests for
# relational context.  Sign-sensitive /= %= >>= keep unsigned through a return-coerce.
chk 'x += y; return x;' 5 4 9;     chk 'x -= y; return x;' 9 4 5
chk 'x &= y; return x;' 6 3 2;     chk 'x |= y; return x;' 4 1 5
chk 'x ^= y; return x;' 6 3 5;     chk 'int z; z = (x += 2); return z;' 5 9 7
chk 'x <<= y; return x;' 5 3 40;   chk 'x >>= y; return x;' -40 2 -10
chk 'x *= y; return x;' 6 7 42;    chk 'x *= y; return x;' -6 7 -42
chk 'x /= y; return x;' -20 3 -6;  chk 'x %= y; return x;' -20 3 -2
chk 'x += y; x *= 2; return x;' 5 4 18
chkf 'int f(x,y) unsigned x; unsigned y; { x >>= 1; return x; }' 40000 9 20000
chkf 'int f(x,y) unsigned x; unsigned y; { x /= y; return x; }' 40000 2 20000
chkf 'int f(x,y) unsigned x; unsigned y; { x %= y; return x; }' 40001 2 1
chkf 'int f(x,y) unsigned x; unsigned y; { return (x /= y); }' 40000 2 20000
# block move: small struct (<=INLINEBLK=8B) inlines word copies; larger uses the
# Z8000 LDIRB (one self-repeating instruction, far dst/src pairs + byte count).
chkf 'struct P{int a;int b;int c;int d;int e;}; int f(){ struct P p,q; q.e=42; p=q; return p.e; }' 0 0 42
chkf 'struct P{int a;int b;int c;int d;int e;}; int f(){ struct P p,q; q.a=11;q.e=5; p=q; return p.a; }' 0 0 11
chkf 'struct P{int a;int b;int c;int d;int e;int f;int g;}; int f(){ struct P p,q; q.g=99; p=q; return p.g; }' 0 0 99
# long / pointer return: 32-bit return in RR0; far pointer return in RR0
chkf 'long g(){ return 100000; } int f(){ return (int)g(); }' 0 0 -31072
chkf 'long g(){ return 7; } int f(){ return (int)g(); }' 0 0 7
chkf 'int *g(p) int *p; { return p; } int f(x) int x; { int *q; q=g(&x); return *q; }' 8 0 8
# segmented pointer arithmetic -- RUNTIME index through a (memory/param) far pointer:
# `p[i]' = *(p + i*scale) adds the scaled index to the pointer's OFFSET half, keeps the
# segment, and the deref links via @RRn.  (n2 frame-reservation: SUB R15,#framesize so the
# call's arg-pushes don't clobber the caller's locals.)
chkf 'int g(p,i) int *p; int i; { return p[i]; } int f(){ int a[3]; a[0]=10; a[1]=20; a[2]=42; return g(a,2); }' 0 0 42
chkf 'int g(p,i) int *p; int i; { return p[i]; } int f(){ int a[3]; a[0]=10; a[1]=20; a[2]=42; return g(a,1); }' 0 0 20
chkf 'int g(p,i) int *p; int i; { return p[i]; } int f(){ int a[3]; a[0]=10; a[1]=20; a[2]=42; return g(a,0); }' 0 0 10
chkf 'int g(p) char *p; { char *q; q = p + 3; return 0; } int f(){ return 0; }' 0 0 0
# Compound +=/-= on a far-pointer REGISTER-pair lvalue modifies the OFFSET half IN PLACE
# (aadd.t/asub.t REG|MMX rule) instead of the load-modify-store round-trip (the original's
# form).  p is pinned to a callee-saved pair by being live across the h() calls; the address
# arithmetic is execution-checked through the deref.
chkf 'h(){} char b[8]; int f(){ register char *p; int i; for(i=0;i<8;i++)b[i]=i+1; p= &b[0]; h(); p+=5; h(); return *p; }' 0 0 6
chkf 'h(){} char b[8]; int f(){ register char *p; int i; for(i=0;i<8;i++)b[i]=i+1; p= &b[7]; h(); p-=3; h(); return *p; }' 0 0 5
# Storing a far pointer (a register PAIR) to memory is ONE native `LDL mem,RR' (or `LDL @Rn,RR'
# through a far pointer), not two `LD' halves -- the store counterpart to the direct pair LOAD.
# Covers a frame/global lvalue (REG-source direct rule) and a far-deref `*p = q' (general store
# rule now emits one LDL).  Execution-checked through the stored pointer.
chkf 'char a[4]; char *slot[3]; int f(){ char **pp; char *q; a[2]=81; pp= &slot[1]; q= &a[2]; *pp=q; return *slot[1]; }' 0 0 81
chkf 'char *gp; char *h(){ static char c; c=88; return &c; } int f(){ gp=h(); return *gp; }' 0 0 88
# `*p != 0' / `l != 0' / `G != 0' (far-ptr/long compared to 0) tests the value IN MEMORY with
# one TESTL (@RRn / DA / X form) instead of LDL-into-a-temp-then-TESTL -- matching the original
# (`TESTL @R10').  EQ/NE uses only the Z flag, which the memory TESTL sets; execution-checked.
chkf 'char *s[2]; int chk(p) char **p; { if (*p != 0) return 7; return 9; } int f(){ s[0]=0; s[1]="x"; return chk(&s[1]) + chk(&s[0]); }' 0 0 16
chkf 'int f(){ long l; l=5; if (l != 0) return 7; return 9; }' 0 0 7
chkf 'int f(){ long l; l=0; if (l != 0) return 7; return 9; }' 0 0 9
# A loaded far-pointer index `p[i]' (p a STAR-loaded pointer PARAM) keeps the pointer on the
# LEFT (modswap commutative-swap guard) so the P_SLT single-ADD rule fires: LDL the pair, then
# ADD the scaled index to its OFFSET half -- the original backend's form.  Without the guard the
# generic flag-swap flips it to int-LEFT, forcing the segment-copy split (no LDL, one insn more).
chkdis 'int g(p,i) int *p; int i; { return p[i]; }' 'ldl ' yes
# A leaf with no locals reserves no frame -- the prologue's `SUB R15,#framesize' is emitted
# only when the reservation (locals + STM save area) is nonzero (n2 synthesizes it at EPILOG),
# so a zero-size frame emits no SUB at all (the original's leaf form; `SUB R15,#0' was a no-op).
chklist 'int f(){ return 3; }' 'sub r15,' no
# ...but a function WITH locals still reserves them (correctness: a CALL's arg-pushes must not
# clobber the local array the callee indexes).
chklist 'g(){} int f(){ int a[3]; a[0]=7; g(); return a[0]; }' 'sub r15,' yes
# far-ptr + variable offset MATERIALIZED as a value : `q=p+i', `return p+i',
# `g(p+i)' all need a fresh register PAIR for the result -- regselect(PAIR) needs the LPTR
# p_pair kind set (was 0 -> no pair allocatable -> ASSIGN/ADD/CALL no-match).
chkf 'int set(p,i,v) int *p; int i; int v; { int *q; q=p+i; *q=v; return 0; } int f(){ int a[3]; set(a,2,42); return a[2]; }' 0 0 42
chkf 'int *adr(p,i) int *p; int i; { return p+i; } int f(){ int a[3]; int *q; a[2]=77; q=adr(a,2); return *q; }' 0 0 77
chkf 'int dr(p) int *p; { return *p; } int g(p,i) int *p; int i; { return dr(p+i); } int f(){ int a[3]; a[1]=55; return g(a,1); }' 0 0 55
# LOCAL-array runtime index `q[i]': cc0 folds q's frame disp into the index and leaves
# `int + FP' (T_SREG); add.t materializes a seg-0 far pair (ADD [LO],FP; SUB [HI],[HI]) and the
# element addr rides in the @RRn deref DISPLACEMENT.  That displacement REQUIRES the Z8000 BA
# (Base Address) mode -- opcode 0x31 load / 0x33 store, verified vs the Zilog Z8000 CPU Ref Man
# (segmented, p.108-110): disp added to the pair's OFFSET, segment unchanged.  Plain @RRn (IR)
# has no disp field, so n2 was silently dropping it (read element 0).  Guards both load + store.
chkf 'int f(){ int q[4]; int i; i=0; q[0]=10;q[1]=20;q[2]=42;q[3]=99; return q[i]; }' 0 0 10
chkf 'int f(){ int q[4]; int i; i=1; q[0]=10;q[1]=20;q[2]=42;q[3]=99; return q[i]; }' 0 0 20
chkf 'int f(){ int q[4]; int i; i=2; q[0]=10;q[1]=20;q[2]=42;q[3]=99; return q[i]; }' 0 0 42
chkf 'int f(){ int q[4]; int i; i=3; q[0]=10;q[1]=20;q[2]=42;q[3]=99; return q[i]; }' 0 0 99
# write through a runtime local-array index: register value -> BA-mode STORE (opcode 0x33):
chkf 'int f(){ int q[4]; int i; int v; i=2; v=42; q[i]=v; return q[2]; }' 0 0 42
# ...and an IMMEDIATE value: no Z8000 BA-immediate store, but after the far-ptr
# materialize pass the only @RR+disp immediate store is a seg-0 frame element, so n2 emits
# the X-mode immediate store indexed by the pair's offset register (segment 0 = the frame):
chkf 'int f(){ int q[4]; int i; i=2; q[i]=42; return q[2]; }' 0 0 42
chkf 'int f(){ int q[4]; int i; i=0; q[i]=77; return q[0]; }' 0 0 77
# ADDRESS of a local-array element with a RUNTIME index, materialized as a far-ptr VALUE
# `&a[n]' / `a+n' for a LOCAL array is cc0-formed as (FP+n)-frame_offset -- a far
# pointer minus a constant -- needing the LPTX `ptr-int' rule in sub.t (mirror of add.t).
chkf 'int f(n) int n; { int a[5]; int *q; q = &a[n]; *q = 42; return a[3]; }' 3 0 42
chkf 'int f(n) int n; { int a[5]; int *q; a[2]=99; q = &a[n]; return *q; }' 2 0 99
chkf 'int f(i) int i; { int a[5]; int *p; a[1]=55; p = &a[3]; p = p - i; return *p; }' 2 0 55
chkf 'int f() { int a[4]; int *q; int i; int s; a[0]=1;a[1]=2;a[2]=3;a[3]=4; s=0; for(i=0;i<4;i++){ q=&a[i]; s+=*q; } return s; }' 0 0 10
# 2D CHAR array indexed by two register vars (banner.c `font[*s-' '][i]').  cc0 left-
# associates a[i][j] (scale-1 inner index) as (i*scale + base) + j, leaving the scaled term
# folded against the static base -- a scaled address gencoll can't encode.  modoper rotates
# the static base out (-> (i*scale + j) + base) so the two indices combine into one register
# and the base folds as the displacement, matching the original `LDB Rd, base(Ridx)' codegen.
chkf 'int f(x,y) int x; int y; { static char a[3][4]; register int i,j; a[2][3]=42; i=x;j=y; return a[i][j]; }' 2 3 42
chkf 'int f(x,y) int x; int y; { static char a[3][4]; register int i,j; i=x;j=y; a[i][j]=7; return a[2][1]; }' 2 1 7
# far-pointer struct field at a NON-ZERO offset -> BA-mode load (ALL silently read field 0
# before the n2 BA fix; this whole block exercises @RRn-with-displacement load/store):
chkf 'struct s{int a;int b;}; int g(p) struct s *p; { return p->b; } int f(){ struct s v; v.a=10; v.b=42; return g(&v); }' 0 0 42
chkf 'struct s{int a;int b;int c;}; int g(p) struct s *p; { return p->c; } int f(){ struct s v; v.a=10;v.b=20;v.c=30; return g(&v); }' 0 0 30
chkf 'struct s{int a;int b;int c;}; int g(p) struct s *p; { return p->a; } int f(){ struct s v; v.a=10;v.b=20;v.c=30; return g(&v); }' 0 0 10
# byte field at an offset -> BA-mode BYTE load (opcode 0x30):
chkf 'struct s{int a;char b;}; int g(p) struct s *p; { return p->b; } int f(){ struct s v; v.a=10;v.b=7; return g(&v); }' 0 0 7
# store a REGISTER value through a far field at an offset -> BA-mode store (opcode 0x33):
chkf 'struct s{int a;int b;int c;}; int g(p,x) struct s *p; int x; { p->c=x; return p->c; } int f(){ struct s v; return g(&v,30); }' 0 0 30
# far deref at an offset used in a NON-LOAD context: BA mode is LOAD-only, so the
# element address MATERIALIZES into the pair (findoffs, via isfarbase) -> deref @RRn disp 0,
# which every operator can use.  Covers an arithmetic operand and an immediate-store dest.
chkf 'struct s{int a;int b;}; int g(p) struct s *p; { return p->a + p->b; } int f(){ struct s v; v.a=10;v.b=20; return g(&v); }' 0 0 30
chkf 'struct s{int a;int b;}; int g(p) struct s *p; { return p->a * p->b; } int f(){ struct s v; v.a=10;v.b=20; return g(&v); }' 0 0 200
chkf 'struct s{int a;int b;}; int g(p) struct s *p; { return p->a - p->b; } int f(){ struct s v; v.a=30;v.b=8; return g(&v); }' 0 0 22
chkf 'struct s{int a;int b;}; int g(p) struct s *p; { return p->b << 2; } int f(){ struct s v; v.b=10; return g(&v); }' 0 0 40
chkf 'struct s{int a;int b;}; int g(p) struct s *p; { return p->a == p->b; } int f(){ struct s v; v.a=5;v.b=5; return g(&v); }' 0 0 1
chkf 'struct s{int a;int b;}; int g(p) struct s *p; { p->b=42; return p->b; } int f(){ struct s v; return g(&v); }' 0 0 42
# switch statements: genswitch is an if-chain comparing SWREG (the MI evaluates the
# switch value into SWREG); the earlier bug compared a hard-wired R1 -> every switch hit the
# default.  Covers case match, default, case 0 (OR SWREG,SWREG), break, fall-through, negative.
chkf 'int f(x,y) int x; int y; { switch(x){ case 1: return 10; case 2: return 20; case 3: return 30; default: return 99; } }' 2 0 20
chkf 'int f(x,y) int x; int y; { switch(x){ case 1: return 10; case 2: return 20; default: return 99; } }' 9 0 99
chkf 'int f(x,y) int x; int y; { switch(x){ case 0: return 7; case 5: return 50; default: return 1; } }' 0 0 7
chkf 'int f(x,y) int x; int y; { int z; z=0; switch(x){ case 1: z=10; break; case 2: z=20; break; default: z=99; } return z; }' 2 0 20
chkf 'int f(x,y) int x; int y; { int z; z=0; switch(x){ case 1: case 2: z=20; break; default: z=99; } return z; }' 1 0 20
chkf 'int f(x,y) int x; int y; { switch(x){ case -5: return 5; default: return 0; } }' -5 0 5
# span-dependent JR->JP promotion: a branch beyond JR's +-128-word reach is promoted
# to an absolute JP (iterated to a fixed point in n2).  Force it with a large loop body
# (40 statements >> 128 words back-branch) running a known number of times.
spanbody=$(for n in $(seq 1 40); do printf ' s=s+1;'; done)
chkf "int f(x,y) int x; int y; { int s; int i; s=0; for(i=0;i<2;i++){$spanbody } return s; }" 0 0 80
chkf "int f(x,y) int x; int y; { int s; s=5; if(x){$spanbody } return s; }" 1 0 45
chkf "int f(x,y) int x; int y; { int s; s=5; if(x){$spanbody } return s; }" 0 0 5
# control-flow coverage: nested loops, do-while, continue/break, goto, nested if/else
chkf 'int f(x,y) int x; int y; { int i; int j; int s; s=0; for(i=0;i<x;i++) for(j=0;j<y;j++) s++; return s; }' 3 4 12
chkf 'int f(x,y) int x; int y; { int s; int i; s=0; i=1; do { s=s+i; i++; } while(i<=x); return s; }' 5 0 15
chkf 'int f(x,y) int x; int y; { int i; int s; s=0; for(i=0;i<x;i++){ if(i==3) continue; if(i==7) break; s=s+i; } return s; }' 10 0 18
chkf 'int f(x,y) int x; int y; { int s; s=0; if(x) goto skip; s=99; skip: return s; }' 1 0 0
chkf 'int f(x,y) int x; int y; { if(x>5){ if(y>5) return 1; else return 2; } else return 3; }' 8 2 2
# mask test `if(x & const)' in a relational/flow context: getldown must force the
# AND's left operand into a register (no Z8000 AND/TEST mem,#imm), else the const-right
# mask test no-matched while the variable-right `x & y' compiled fine.
chk 'if(x&4) return 7; return 9;' 5 0 7;   chk 'if(x&4) return 7; return 9;' 2 0 9
chk 'if(4&x) return 7; return 9;' 5 0 7;   chk 'return (x&4)==0;' 2 0 1
chk 'int n; n=0; while(x&1){n++; x>>=1;} return n;' 7 0 3
# global variables: n2 builds a data segment at dataBase=0xC000 from
# the GLABEL + ZBYTE/ZWORD/ZGPTR data records, and resolves GID operand references (incl.
# forward refs) to a global's absolute address.  Covers scalar/array, init/uninit, pointer.
chkf 'int g = 42; int f(){ return g; }' 0 0 42
chkf 'int g; int f(x,y) int x; int y; { g=x; return g+1; }' 5 0 6
chkf 'int a[3] = {7,8,9}; int f(x,y) int x; int y; { return a[x]; }' 1 0 8
chkf 'int a[3]; int f(x,y) int x; int y; { a[0]=10;a[1]=20;a[2]=30; return a[x]; }' 2 0 30
chkf 'int g; int *p = &g; int f(){ *p = 55; return g; }' 0 0 55
# multiple globals: each must get a DISTINCT data offset (the addrWords o.off fix lets the
# literal pool's far-pointer entries -- seg word at +0, offset word at +2 -- resolve apart).
chkf 'int a; int b; int f(x,y) int x; int y; { a=x; b=y; return a*10+b; }' 3 7 37
chkf 'int a=4; int b=9; int f(){ return a*10+b; }' 0 0 49
chkf 'int gi=6; int gu; int f(x) int x; { gu=x; return gi+gu; }' 5 0 11
chkf 'int a[3]={7,8,9}; int b[2]={3,4}; int f(x,y) int x; int y; { return a[x]+b[y]; }' 1 0 11
chkf 'int arr[4]; int sv; int f(x,y) int x; int y; { sv=x; arr[1]=y; return sv+arr[1]; }' 5 7 12
# efficiency: a SCALAR (non-pointer) static is read/written by DIRECT DA addressing
# (LD R1,g / LD g,R1) instead of pooling its address into a far pointer + @RR deref --
# `return g' drops 2 insns -> 1.  Gated on !ispoint && ptp!=ADDR so arrays/pointer-typed
# statics and address-of uses keep the pooled/decay path (correctness; see banner/p-m).
chkdis 'int g; int f(){ return g; }' 'ldl ' no
chkf 'int g; int h; int f(){ g=300; h=65; return g+h; }' 0 0 365
chkf 'int g; int h; int f(x) int x; { g=x; h=g*2; return g+h; }' 7 0 21
# global g++ / --g use the efficient INC/DEC-of-memory form (opcode 0x69, added to n2)
chkf 'int g; int f(x) int x; { g=x; g++; --g; g+=5; return g; }' 10 0 15
chkf 'int g; int f(x) int x; { g=x; return g++; }' 7 0 7
chkf 'char c; int f(x) int x; { c=x; c++; return c; }' 7 0 8
# The VALUE of ++/--/op= on a `char' is the STORED byte promoted to int, so it must be
# extended through the high half (sibling of the postfix case).  Without it the word
# temp holds the untruncated result over a stale high byte: `--c' from 0 reads as +255,
# `c += 91' from 37 as +128, `c <<= 3' from 127 as +1016.  The real sites were the rec/mm.c
# console driver (`if (--mmrow < 0)' never scrolled) and split.c's `if (++*cp <= 'z')'.
# Effect-only forms must stay extension-free -- see the codesize gate.
chkf 'char c; int f(x) int x; { c=x; return --c; }' 0 0 -1
chkf 'char c; int f(x) int x; { c=x; return ++c; }' 127 0 -128
chkf 'char c; int f(x) int x; { c=x; return (c += 91); }' 37 0 -128
chkf 'char c; int f(x) int x; { c=x; return (c -= 1); }' -1 0 -2
chkf 'char c; int f(x) int x; { c=x; return (c |= 9); }' -120 0 -119
chkf 'char c; int f(x) int x; { c=x; return (c ^= 1); }' -1 0 -2
chkf 'char c; int f(x) int x; { c=x; return (c &= 0xF0); }' -1 0 -16
chkf 'char c; int f(x) int x; { c=x; return (c <<= 3); }' 127 0 -8
chkf 'unsigned char c; int f(x) int x; { c=x; return (c -= 1); }' 0 0 255
chkf 'unsigned char c; int f(x) int x; { c=x; return (c += 1); }' 255 0 0
# and the guarded-branch form the driver actually used
chkf 'char r; int f(x) int x; { r=x; if (--r < 0) return 1; return 0; }' 0 0 1
chkf 'char r; int f(x) int x; { r=x; if (++r >= 24) return 1; return 0; }' 127 0 0
# data-segment WORD ALIGNMENT: a word/long global after a byte global must land at an
# EVEN offset -- the Z8000 ignores address bit0 on a word access, so an int at an odd offset
# aliased its even neighbour (`char c; int g;' returned c=g>>8).  n2 now even-aligns each
# data global at GLABEL.  Order-dependent before the fix; both orders must work now.
chkf 'char c; int g; int f(){ c=65; g=300; return g+c; }' 0 0 365
chkf 'char a; char b; int g; int f(){ a=1; b=2; g=300; return g+a+b; }' 0 0 303
chkf 'char m[3]; int g; int f(){ m[0]=5; g=300; return g+m[0]; }' 0 0 305
# efficiency: a RUNTIME-INDEXED static array g[i]/font[k][i] addresses via X-mode
# (LDB Rd,font(Rindex) -- the static base is the displacement, the index a register)
# instead of pooling the base into a far pointer + @RR deref.  font[k][i] drops 13->6 insns.
# The deref base is kept UNPOOLED via the modtree deref-spine signal (mtree0.c overlay); a
# static used as a far-pointer VALUE (g+i, &g[i]) still pools -- so the value cases below
# must stay correct.  Assert no ZLDL far-pointer load is emitted for the indexed read.
chkdis 'int g[10]; int f(i) int i; { return g[i]; }' 'ldl ' no
chkf 'int g[10]; int f(i) int i; { g[3]=300; g[5]=500; return g[i]; }' 5 0 500
chkf 'int g[10]; int f(i,v) int i,v; { g[i]=v; return g[2]; }' 2 700 700
chkf 'char c[10]; int f(i) int i; { c[4]=65; return c[i]; }' 4 0 65
chkf 'char m[3][4]; int f(k,i) int k,i; { m[1][2]=88; return m[k][i]; }' 1 2 88
chkf 'int a[3][4]; int f(k,i) int k,i; { a[1][2]=21; return a[k][i]; }' 1 2 21
chkf 'int g[10]; int h[10]; int f(i) int i; { g[7]=99; h[2]=7; return g[h[i]]; }' 2 0 99
# value uses of a static base must STILL pool correctly (not X-mode):
chkf 'int g[10]; int f(i) int i; { int *p,*q; p=&g[i]; q=&g[0]; return p-q; }' 4 0 4
# static used as a far-pointer value passed to a callee
chkf 'int g[10]; int s(p) int *p; { return *p; } int f(i) int i; { g[3]=33; return s(g+i); }' 3 0 33
# efficiency: a far-pointer field deref `*(p+k)' folds the constant offset into the
# @RRn+disp BA displacement for a LOAD/STORE (3->2 insns), but MATERIALIZES (@RRn disp 0)
# when it is a direct ALU/compare/inc-dec/convert operand or a truth-test -- those Z8000
# ops have no @RRn+disp memory form.  modoper marks the load/store case (T_FOLDOFS);
# amd's findoffs folds it.  All shapes must stay correct AND compile (no `no BA form').
chkf 'struct s{int a,b,c;}; int f(){ struct s v; struct s *p; p=&v; v.b=42; return p->b; }' 0 0 42
chkf 'struct s{int a,b,c;}; int f(){ struct s v; struct s *p; p=&v; p->c=77; return v.c; }' 0 0 77
chkf 'struct s{int a,b;}; int f(){ struct s v; struct s *p; p=&v; v.b=7; if(p->b) return 1; return 0; }' 0 0 1
chkf 'struct s{int a,b;}; int f(){ struct s v; struct s *p; p=&v; v.a=10; v.b=20; return p->a+p->b; }' 0 0 30
chkf 'struct s{int a,b;}; int f(){ struct s v; struct s *p; p=&v; v.a=5; v.b=5; return p->a==p->b; }' 0 0 1
chkf 'struct s{int a; long l;}; int f(){ struct s v; struct s *p; p=&v; v.l=70000; return (int)(v.l-69958); }' 0 0 42
# long/far-ptr truth-test reads the 32-bit operand DIRECTLY from memory: TESTL @mem (one
# instruction), not a load-into-a-pair + TESTL of the register.  cc1 already emits the memory
# operand; n2 now encodes the @Rs/X/DA memory form of TESTL (0x1C08/0x5C08) instead of forcing
# the register form (0x9C08).  Equality (if/while) + ordering (RESFLG clears V/C after TESTL).
chkf 'int f(){ long l; l=5; if(l) return 7; return 9; }' 0 0 7
chkf 'int f(){ long l; l=0; if(l) return 7; return 9; }' 0 0 9
chkf 'int f(){ long l; l=5; if(l>0) return 1; return 0; }' 0 0 1
chkf 'int f(){ long l; l=0-5; if(l>0) return 1; return 0; }' 0 0 0
chkf 'int f(){ long l; l=0-5; if(l<0) return 1; return 0; }' 0 0 1
chkf 'int f(n) int n; { long l; int c; c=0; l=n; while(l){ c=c+1; l=l-1; } return c; }' 3 0 3
# static locals: a function-local `static' lives in the data segment (numbered SLABEL,
# its &s pool entry is a ZGPTR-by-LID -> the static's storage label, not a named global).
chkf 'int f(x) int x; { static int s = 7; s = s + x; return s; }' 5 0 12
chkf 'int f(x) int x; { static int n; n = n + x; return n; }' 3 0 3
# callee-saved register save/restore: a `register' var lives in R6..R12 (callee-saved);
# a CALL must NOT clobber it.  n2's prolog now PUSHes / epilog POPs exactly the register
# set the function uses (gen1 emits the union mask; leaf functions save nothing).  Before
# this, a callee destroyed the caller's register var (returned the callee's value).
chkf 'int g(){ register int z; z=42; return z; } int f(){ register int a; register int b; a=10; b=20; g(); return a+b; }' 0 0 30
chkf 'int g(){ return 7; } int f(){ register int k; k=100; g(); g(); return k; }' 0 0 100
chkf 'int g(x) int x; { return x; } int f(n) register int n; { register int i; register int t; t=0; for(i=0;i<n;i++) t=t+g(i); return t; }' 5 0 10
# recursion / cross-call temporaries: cc1 may hold a value across a CALL in a callee-saved
# register (e.g. fib(n-1) held in R12 across the fib(n-2) call).  Such TEMPS are not in
# cc0's register-VARIABLE mask, so n2 derives the prolog save-set from the callee-saved
# registers the function actually references (union with the var mask) -- matching the
# original (`LDM @R14,Rlow,#count' saves every used callee reg).  Without this the inner
# call clobbered the outer's first result.  Leaf functions still save nothing.
chkf 'int fib(n) int n; { if(n<2) return n; return fib(n-1)+fib(n-2); } int f(){ return fib(10); }' 0 0 55
chkf 'int a(m,n) int m,n; { if(m==0) return n+1; if(n==0) return a(m-1,1); return a(m-1,a(m,n-1)); } int f(){ return a(2,3); }' 0 0 9
chkf 'int s(n) int n; { if(n<=0) return 0; return n+s(n-1); } int f(){ return s(50); }' 0 0 1275
chkf 'int g(x) int x; { return x*x; } int f(n) int n; { return g(n)+g(n+1)+g(n+2); }' 3 0 50
# indexed far-field as a direct ALU/compare operand: `a[i].field + x' (a = struct ptr).
# cc0 emits the element address as `i*scale + a' with the far base on the RIGHT of the
# ADD, but isfarbase only walked the LEFT spine -> it found the index, not the base, so
# findoffs FOLDED the field offset into an ALU @RRn+disp operand (which the Z8000 cannot
# encode -> n2 error).  isfarbase now checks BOTH operands of a commutative ADD, so the
# field offset materializes (deref @RRn disp 0) for the ALU case.
chkf 'struct s{int x,y;}; int g(a,i,x) struct s *a; int i,x; { return a[i].y+x; } int f(){ struct s b[2]; b[1].y=40; return g(b,1,5); }' 0 0 45
chkf 'struct s{int x,y;}; int g(a,i) struct s *a; int i; { return a[i].x+a[i].y; } int f(){ struct s b[2]; b[1].x=10; b[1].y=20; return g(b,1); }' 0 0 30
chkf 'struct s{int x,y;}; int sm(a,n) struct s *a; int n; { int i,t; t=0; for(i=0;i<n;i++) t=t+a[i].x+a[i].y; return t; } int f(){ struct s b[3]; int i; for(i=0;i<3;i++){b[i].x=i;b[i].y=i*2;} return sm(b,3); }' 0 0 9
# LOCAL array element as a direct ALU/compare operand: `local_a[i] + x', `local_a[i].y + x'.
# The base is a FRAME address (FP-relative) materialized into a pair (@RRn=(0,i*scale+FP)),
# and the array's frame offset became the @RRn displacement -- which ALU/compare ops cannot
# encode.  findoffs now materializes that const for an ALU operand when the base is
# frame-relative WITH an index (frameindexed()).  MUST NOT pessimize the X-mode cases
# (canaries below): a STATIC array field `g[i].y'+x and a simple `FP+const' field stay
# X-mode (`addr(Rindex)' / `const(FP)'), which IS ALU-encodeable.
chkf 'int f(i,x) int i,x; { int a[3]; a[0]=10;a[1]=20;a[2]=30; return a[i]+x; }' 1 5 25
chkf 'struct s{int x,y;}; int f(){ struct s a[3]; int i,s; for(i=0;i<3;i++){a[i].x=i;a[i].y=i*2;} s=0; for(i=0;i<3;i++) s=s+a[i].x+a[i].y; return s; }' 0 0 9
chkf 'int f(i,b) int i,b; { int a[3]; a[0]=5;a[1]=15;a[2]=25; if(a[i]<b) return 1; return 0; }' 1 20 1
chkf 'int f(i,j) int i,j; { int a[2][3]; a[1][2]=8; return a[i][j]+100; }' 1 2 108
# canaries: static array-field + simple frame field as ALU operands must STAY encodeable (X-mode)
chkf 'int g[5]; int f(i,x) int i,x; { g[2]=100; return g[i]+x; }' 2 7 107
chkf 'struct s{int x,y;}; int f(x) int x; { struct s v; v.y=50; return v.y+x; }' 8 0 58
# far-pointer register variables: a `register' pointer lives in a callee-saved PAIR
# (RR6/RR8/RR10), loaded once (LDL) and kept across the loop -- no per-iteration frame
# reload -- and preserved across calls.  bind.c allocs the pair; loadreg copies a far-ptr
# param as a single LDL into the pair (assign.t direct REG=mem LDL rule); the prolog saves
# the pair with one PUSHL.  Deref / pointer-arith / survives-call all stay correct.
chkf 'int f(){ int a[3]; register int *p; a[1]=42; p=&a[1]; return *p; }' 0 0 42
chkf 'int slen(s) register char *s; { register int n; n=0; while(*s){ n=n+1; s=s+1; } return n; } int f(){ char b[4]; b[0]=88;b[1]=89;b[2]=90;b[3]=0; return slen(b); }' 0 0 3
chkf 'int g(){ return 0; } int sum(p,n) register int *p; int n; { register int t; register int i; t=0; for(i=0;i<n;i++){ t=t+*p; p=p+1; g(); } return t; } int f(){ int a[3]; a[0]=10;a[1]=20;a[2]=30; return sum(a,3); }' 0 0 60
# double-indexed pointer array `m[i][j]' with BOTH indices variable -- a far pointer
# LOADED FROM MEMORY then runtime-indexed.  The Z8000 has no @RR+register-index mode, so
# modoper hoists the inner deref to a temp (`tmp = m[i]; *(j*scale + tmp)') -- the form
# that selects cleanly.  Covers param (int **), local (int *[]), char ** (scale-1 inner),
# and the lvalue store / compound-assign / inc paths (the COMMA-lifted lvalue).
chkf 'int g(m,i,j) int **m; int i,j; { return m[i][j]; } int f(i,j) int i,j; { int a[2],b[2]; int *r[2]; a[0]=30;a[1]=31;b[0]=40;b[1]=41; r[0]=a;r[1]=b; return g(r,i,j); }' 0 1 31
# indirect call through a GLOBAL fn pointer: the address load is coalesced into
# RR2 directly (LDL RR2,pool ; LDL RR0,@R2 ; CALL @R0) instead of load-RR0-then-copy.
# Must still call the right function -- a wrong dest pair calls garbage.
chkf 'int sq(n) int n; { return n*n; } int dbl(n) int n; { return n+n; } int (*gfp)(); int f(x,k) int x,k; { gfp = k ? dbl : sq; return (*gfp)(x); }' 5 0 25
chkf 'int sq(n) int n; { return n*n; } int dbl(n) int n; { return n+n; } int (*gfp)(); int f(x,k) int x,k; { gfp = k ? dbl : sq; return (*gfp)(x); }' 5 1 10
chkf 'int g(m,i,j) int **m; int i,j; { return m[i][j]; } int f(i,j) int i,j; { int a[2],b[2]; int *r[2]; a[0]=30;a[1]=31;b[0]=40;b[1]=41; r[0]=a;r[1]=b; return g(r,i,j); }' 1 0 40
chkf 'int f(i,j) int i,j; { int a[2],b[2]; int *rows[2]; a[0]=10;a[1]=11;b[0]=20;b[1]=21; rows[0]=a;rows[1]=b; return rows[i][j]; }' 1 1 21
chkf 'int f(i,j) int i,j; { char a[2],b[2]; char *rows[2]; a[0]=65;a[1]=66;b[0]=67;b[1]=68; rows[0]=a;rows[1]=b; return rows[i][j]; }' 0 1 66
chkf 'int f(i,j) int i,j; { int a[2],b[2]; int *rows[2]; a[0]=1;a[1]=2;b[0]=3;b[1]=4; rows[0]=a;rows[1]=b; rows[i][j]=99; return a[0]+a[1]+b[0]+b[1]; }' 1 0 106
chkf 'int f(i,j) int i,j; { int a[2],b[2]; int *rows[2]; a[0]=10;a[1]=10;b[0]=10;b[1]=10; rows[0]=a;rows[1]=b; rows[i][j]+=5; return a[0]+a[1]+b[0]+b[1]; }' 1 1 45
chkf 'int f(){ register long l; l=70000; return (int)(l-69958); }' 0 0 42
# signed/unsigned ORDERING relop vs the literal 0: must COMPARE (CP sets the V
# overflow flag the signed condition codes need) -- NOT TEST.  On the Z8000 the word/long
# TEST is a logical op that does NOT write V (only byte logicals write P/V, as parity), so
# `x>0 / x>=0 / x<0 / x<=0' off a TEST read a STALE V and were wrong (x>0 always 0).
# Equality (x==0/x!=0, if(x)) only needs Z and stays on TEST.  Word path = one CP mem,#0.
chkf 'int f(x) int x; { return x>0; }'  5 0 1
chkf 'int f(x) int x; { return x>0; }' -3 0 0
chkf 'int f(x) int x; { return x>=0; }' -1 0 0
chkf 'int f(x) int x; { return x<0; }'   5 0 0
chkf 'int f(x) int x; { return x<=0; }'  0 0 1
chkf 'int f(x) unsigned x; { return x>0; }' 5 0 1
chkf 'int f(x) int x; { int c; c=0; while(x>0){ c=c+1; x=x-1; } return c; }' 5 0 5
chkf 'int f(x) int x; { return x==0; }'  5 0 0
chkf 'int f(x) int x; { return x!=0; }'  5 0 1
# LONG / far-ptr ordering vs 0: TESTL (like word TEST) sets Z and S but NOT V or
# C, so signed (S XOR V) and unsigned (C) ordering condition codes would read stale
# flags.  After TESTL, RESFLG V,C (mask 9) clears both -- exactly what a CPL against 0
# sets -- so ordering is correct; equality keeps the bare 1-insn TESTL.
chkf 'int f(){ long l; l=5;     return l>0; }'  0 0 1
chkf 'int f(){ long l; l=0-5;   return l>0; }'  0 0 0
chkf 'int f(){ long l; l=0-5;   return l<0; }'  0 0 1
chkf 'int f(){ long l; l=0;     return l<=0; }' 0 0 1
chkf 'int f(){ long l; l=0-1;   return l>=0; }' 0 0 0
chkf 'int f(){ long l; l=0;     return l==0; }' 0 0 1
chkf 'int f(){ unsigned long l; l=5; return l>0; }' 0 0 1
chkf 'int f(){ unsigned long l; l=0; return l>0; }' 0 0 0
# string literals: bytes pooled in a data segment, referenced by a far-pointer pool entry.
# The data-segment ENTER realigns to even, so the odd-length "ABCD\0" doesn't misalign the
# following pool pointer (a misaligned LDL would read garbage).
chkf 'int f(i) int i; { char *p = "ABCD"; return p[i]; }' 1 0 66
chkf 'int f(i) int i; { char *p = "ABCD"; return p[i]; }' 0 0 65
chkf 'char *g() { return "Hi"; } int f() { char *p; p = g(); return p[0]; }' 0 0 72
# function pointers: &fn is a far code constant -- the n2 relocates the function-address
# immediate (seg word = 0, offset word = codeBase + fn) and synthesizes an indirect call
# (no memory-indirect CALL on the Z8000): LDL RR0,<fp> ; CALL @RR0.
chkf 'int g() { return 42; } int f() { int (*fp)(); fp = g; return (*fp)(); }' 0 0 42
chkf 'int add(a,b) int a; int b; { return a+b; } int f(x,y) int x; int y; { int (*fp)(); fp = add; return (*fp)(x,y); }' 20 8 28
# ternary-selected fn ptr exercises the LDL #imm32 (32-bit far constant) materialization.
chkf 'int sq(n) int n; { return n*n; } int dbl(n) int n; { return n+n; } int f(x,y) int x; int y; { int (*fp)(); fp = y ? sq : dbl; return (*fp)(x); }' 5 1 25
chkf 'int sq(n) int n; { return n*n; } int dbl(n) int n; { return n+n; } int f(x,y) int x; int y; { int (*fp)(); fp = y ? sq : dbl; return (*fp)(x); }' 5 0 10
# indirect call through a VARIABLE-INDEXED function-pointer array `(*t[i])()'.  cc1
# materializes the slot address &t[i] into RR0; R0 cannot be an @RRn indirect base (reg
# field 0 = immediate mode), so n2 relocates it (LDL RR2,RR0) before the deref-load + call.
chkf 'int g1() { return 10; } int g2() { return 20; } int f(i) int i; { int (*t[2])(); t[0]=g1; t[1]=g2; return (*t[i])(); }' 0 0 10
chkf 'int g1() { return 10; } int g2() { return 20; } int f(i) int i; { int (*t[2])(); t[0]=g1; t[1]=g2; return (*t[i])(); }' 1 0 20
chkf 'int a(x,y) int x,y; { return x+y; } int m(x,y) int x,y; { return x*y; } int f(i) int i; { int (*t[2])(); t[0]=a; t[1]=m; return (*t[i])(3,4); }' 1 0 12
# RR0 is barred from ADDRESSING, not from holding a pointer.  The Z8000 rule is
# "register R0 (or the double register RR0 in segmented mode) cannot be used as an
# indirect register, base register, index register, or software stack pointer" (Z8000 CPU
# Technical Manual, 5.2 "Use of CPU Registers", p.5-2) -- a property of the ROLE, so it
# lives in reg[RR0].r_lvalue (table1.c withholds KLP there) and nowhere else.  These two
# cases pin both edges of that line and fail in opposite directions.
#
# NEGATIVE CONTROL -- the form that must still be rewritten.  Under register pressure the
# far pointer `lp' lives in a frame slot, so each `lp->used' reloads it into a pair as a
# DEREF BASE.  With KLP restored to RR0's r_lvalue the allocator picks RR0 (first free
# pair) and `LD R3,@R0' encodes as `LD R3,#imm', eating the next word: the case then
# returns nothing at all.  Answer: nbytes=y+1, nlines=1, c=(y+1)&0x7F -> (y+2)+c.
chkf 'struct LINE { struct LINE *fw; int used; }; struct LINE l0, l1; int f(x,y) int x,y; { register char *cp1, *cp2; register struct LINE *lp; register long nlines, nbytes; register int c; char b[8]; l0.fw = &l1; l0.used = x; l1.fw = &l0; l1.used = y; cp1 = b; cp2 = b; c = 0; nbytes = 0; nlines = 0; lp = l0.fw; while (lp != &l0) { nlines++; nbytes += lp->used + 1; lp = lp->fw; } *cp1 = (char)(nbytes & 0x7F); c = *cp2; return (int)(nbytes + nlines) + c; }' 3 4 11
# EFFICIENCY GATE -- the form that must NOT be rewritten.  The value of r->name is returned,
# never dereferenced, so RR0 (the pointer return pair) is the right home for it.  A gate
# that only bars RR0 from addressing loads the argument straight into RR0: 9 insns.  A
# gate that bars RR0 from every KLP value routes it through RR2 and then copies it back
# into RR0 to return it: LDL RR2,6(R13) plus a reload, 10 insns.  Both answer 34.
chkdis 'struct R { long id; char name[8]; }; char *rname(h) char *h; { struct R *r; r = (struct R *)h; return r->name; }' 'ldl rr2,' no
chkf 'struct R { long id; char name[8]; }; struct R rb; char *g(h) char *h; { struct R *r; r = (struct R *)h; return r->name; } int f(x,y) int x,y; { char *p; rb.name[0] = x; rb.name[1] = y; p = g((char *)&rb); return p[0]*10 + p[1]; }' 3 4 34
# a FILE-SCOPE `static' is named by SLABEL, not GLABEL -- its address must still bind
# and resolve within the object (driver CON tables, tty t_start/t_param, signal/timeout
# callbacks).  Covers the address of a static function in a file-scope table, a static
# function passed as a callback argument, and a file-scope static datum.
chkf 'static int so(m) int m; { return m+37; } static int sw(m,n) int m,n; { return m*100+n; } int (*ct[2])() = { so, sw }; int f(x,y) int x,y; { return (*ct[0])(x) + (*ct[1])(y,17); }' 5 3 359
chkf 'static int tk(v) int v; { return v-11; } int ap(g,v) int (*g)(); int v; { return (*g)(v); } int f(x,y) int x,y; { return ap(tk,x) + y; }' 42 6 37
chkf 'static int sc = 41; int f(x,y) int x,y; { sc += x; return sc*y; }' 17 3 174
# struct-by-value RETURN assigned to a struct lvalue (`struct s q; q = mk(x);').  The callee
# returns the struct via a static SBSS buffer and hands back its &address in RR0; the caller
# evaluates the call ONCE (cc1 modsasg now binds the source pointer to a stack temp, so the
# per-word copy no longer duplicates the call) and copies word-by-word.  Fixes: modsasg temp
# + dest-address result value + BSS-size zput width; n2 applies the &buf+off pool addend.
chkf 'struct s{int a;int b;}; struct s mk(x) int x;{ struct s r; r.a=x;r.b=x+1; return r;} int f(x) int x;{ struct s q; q=mk(x); return q.a+q.b; }' 10 0 21
chkf 'struct s{int a;int b;int c;}; struct s mk(x) int x;{ struct s r; r.a=x;r.b=x+1;r.c=x+2; return r;} int f(x) int x;{ struct s q; q=mk(x); return q.a+q.b+q.c; }' 4 0 15
chkf 'struct s{int a;}; struct s mk(x) int x;{ struct s r; r.a=x; return r;} int f(x) int x;{ struct s q; q=mk(x); return q.a; }' 7 0 7
chkf 'struct s{char a;char b;}; struct s mk(x) int x;{ struct s r; r.a=x;r.b=x+1; return r;} int f(x) int x;{ struct s q; q=mk(x); return q.a; }' 9 0 9
# the struct-returning call must be evaluated exactly once (side-effect probe via a global)
chkf 'int n; struct s{int a;int b;}; struct s mk(){ struct s r; n=n+1; r.a=n; r.b=0; return r;} int f(){ struct s q; q=mk(); return n; }' 0 0 1
chkf 'struct s{int a;int b;}; struct s mk(x) int x;{ struct s r; r.a=x;r.b=x+1; return r;} int f(x) int x;{ return mk(x).a + mk(x).b; }' 5 0 11

# a struct assignment whose DESTINATION address is computed (`t[y] = u',
# `q[y] = u', `t[y+1] = t[y]').  The inline unroll used to hand every member store
# THE SAME address subtree, making the statement a DAG -- which crashed cc1
# (outtree on a node selection had already relabelled REG) and, once that was
# dodged, silently miscompiled: one member's folded offset landed on the shared
# base, so the first store went to the wrong word and the rest walked off the
# object.  Each store now gets its own dupnode copy.  These check the LAST member
# (was written to the wrong place) and the FIRST (was never written at all).
chkf 'struct s{int a;int b;}; struct s t[8]; struct s u; int f(y) int y; { u.a=11;u.b=42; t[y]=u; return t[3].a*100+t[3].b; }' 3 0 1142
chkf 'struct s{int a;int b;int c;}; struct s t[8]; struct s u; int f(y) int y; { u.a=1;u.b=2;u.c=3; t[y]=u; return t[4].a*100+t[4].b*10+t[4].c; }' 4 0 123
chkf 'struct s{int a;int b;}; struct s t[8]; struct s *q; struct s u; int f(y) int y; { q=t; u.a=11;u.b=42; q[y]=u; return t[3].a*100+t[3].b; }' 3 0 1142
chkf 'struct s{int a;int b;}; struct s t[8]; int f(y) int y; { t[2].a=5;t[2].b=7; t[y+1]=t[y]; return t[3].a*100+t[3].b; }' 2 0 507
chkf 'struct s{char a;char b;char c;char d;}; struct s t[8]; struct s u; int f(y) int y; { u.a=1;u.b=2;u.c=3;u.d=4; t[y]=u; return t[5].a*1000+t[5].b*100+t[5].c*10+t[5].d; }' 5 0 1234
# neighbouring elements must be untouched by the copy
chkf 'struct s{int a;int b;}; struct s t[8]; struct s u; int f(y) int y; { u.a=-1;u.b=-1; t[y]=u; return t[2].a|t[2].b|t[4].a|t[4].b; }' 3 0 0
# and the value of the assignment is still the destination
chkf 'struct s{int a;int b;}; struct s t[8]; struct s u,v; int f(y) int y; { u.a=9;u.b=1; v=(t[y]=u); return v.a*10+v.b; }' 5 0 91
# 32-bit long add/sub: native ADDL/SUBL on register pairs; a whole long immediate is the
# A_IMML form (32-bit, high word then low word).  A decimal constant > 32767 is typed long
# by cc0, so x+40000 exercises int->long promotion + ADDL #imm32 + long->int truncation.
chkf 'int f(x) int x; { long n; n=x; n=n+1; return n; }' 41 0 42
chkf 'int f(x) int x; { long a; long b; a=x; b=x; return a+b; }' 20 0 40
chkf 'int f(x) int x; { long n; n=x; return n-1; }' 50 0 49
chkf 'int f(x) int x; { return x+40000; }' 100 0 -25436
chkf 'int f(x) int x; { long n; n=x; n=n-1000; return n+1000; }' 5000 0 5000
# 32-bit long mul/div/rem: native MULTL/DIVL (no runtime helper -- the i8086 makecall is
# gone).  mul = MULTL RQ0 (low pair RR2); div/rem widen the dividend (EXTSL signed / SUBL
# zero unsigned) into RQ0 then DIVL -> quotient RR2, remainder RR0.
chkf 'int f(x) int x; { long n; n=x; return n*3; }' 10 0 30
chkf 'int f(x) int x; { long n; n=x; n=n*1000; return n/7; }' 70 0 10000
chkf 'int f(x) int x; { long n; n=x; return n/3; }' 30 0 10
chkf 'int f(x) int x; { long n; n=x; return n%7; }' 100 0 2
chkf 'int f(x) int x; { unsigned long n; n=x; return n/3; }' 31 0 10
chkf 'int f(x) int x; { long n; n= -100; return n/x; }' 7 0 -14
# 32-bit long logicals (two 16-bit ops on the pair halves -- no native 32-bit logical)
# and shifts (native SLLL/SLAL; right shift = negative count, signed SLAL / unsigned SLLL).
chkf 'int f(x) int x; { long n; n=x; return n & 12; }' 15 0 12
chkf 'int f(x) int x; { long n; n=x; return n | 256; }' 1 0 257
chkf 'int f(x) int x; { long n; n=x; return n ^ 15; }' 10 0 5
chkf 'int f(x) int x; { long n; n=x; return n << 4; }' 3 0 48
chkf 'int f(x) int x; { long n; n=x; n=n*1000; return n >> 3; }' 80 0 10000
chkf 'int f(x) int x; { unsigned long n; n=x; n=n*1000; return n >> 4; }' 16 0 1000
chkf 'int f(x) int x; { long n; n= -64; return n >> 2; }' 0 0 -16
# 32-bit long compare: native CPL (single branch on the full 32-bit flags).  The relop
# node temp is decoupled from the operand (the relop result type is int but the operand
# is long); the compare-against-0 fold is skipped for long so it uses CPL n,#0.
chkf 'int f(x) int x; { long n; n=x; return n < 100; }' 50 0 1
chkf 'int f(x) int x; { long n; n=x; return n >= 50; }' 40 0 0
chkf 'int f(x) int x; { long n; n=x; n=n*1000; return n > 40000; }' 50 0 1
chkf 'int f(x) int x; { long n; n=x; if (n != 0) return 7; return 9; }' 5 0 7
chkf 'int f(x) int x; { long n; n=x; if (n != 0) return 7; return 9; }' 0 0 9
chkf 'int f(x) int x; { long n; int c; n=x; c=0; while (n>0) { n=n-1; c=c+1; } return c; }' 5 0 5
chkf 'int f(x) int x; { long n; n= -100; return n < 0; }' 0 0 1
chkf 'int f(x) int x; { unsigned long n; n=x; n=n*100000; return n > 250000; }' 3 0 1
chkf 'int f(x) int x; { long a; long b; a=x; b=x; return a==b; }' 7 0 1
# unsigned word divide/mod by a CONSTANT with bit 15 set: the signed Z8000 DIV misreads
# it, so cc1 strength-reduces (quotient is 0/1):  x/C -> (x>=C);  x%C -> (x>=C)?x-C:x.
# Cheap (a compare + select, no DIVL) and only for this constant corner.
chkf 'int f(x) unsigned x; { return x / 0xC000; }' 50000 0 1
chkf 'int f(x) unsigned x; { return x / 0xC000; }' 40000 0 0
chkf 'int f(x) unsigned x; { return x % 0xC000; }' 50000 0 848
chkf 'int f(x) unsigned x; { return x % 0xC000; }' 40000 0 -25536
# same strength reduction at 32 bits (constant divisor >= 2^31).  n = 40000*100000 = 4e9.
chkf 'int f(x) unsigned x; { unsigned long n; n=x; n=n*100000; return n / 0x90000000; }' 40000 0 1
chkf 'int f(x) unsigned x; { unsigned long n; n=x; n=n*10000;  return n / 0x90000000; }' 40000 0 0
# unsigned long compares that CROSS the 2^31 boundary are correct (native CPL carry).
chkf 'int f(x) unsigned x; { unsigned long n; n=x; n=n*100000; return n > 0x90000000; }' 40000 0 1
chkf 'int f(x) unsigned x; { unsigned long a; unsigned long b; a=x; a=a*100000; b=x; b=b*50000; return a > b; }' 40000 0 1
# bit fields: store is load / AND ~mask / OR value / store (no mem-dest logical on Z8000);
# read is shift+mask (unsigned) or shift-pair sign-extend (signed).
chkf 'int f(x,y) unsigned x; unsigned y; { struct s { unsigned a:3; unsigned b:5; } v; v.a=x; return v.a; }' 12 0 4
chkf 'int f(x,y) unsigned x; unsigned y; { struct s { unsigned a:3; unsigned b:5; } v; v.a=x; v.b=y; return v.b; }' 5 9 9
chkf 'int f(x,y) unsigned x; unsigned y; { struct s { unsigned a:3; unsigned b:5; } v; v.b=y; v.a=x; return v.b; }' 7 9 9
chkf 'int f(x,y) unsigned x; unsigned y; { struct s { unsigned a:3; unsigned b:5; } v; v.a=x; v.b=y; return v.b; }' 5 40 8
chkf 'int f(x,y) int x; int y; { struct s { int a:4; int b:4; } v; v.a=x; return v.a; }' -3 0 -3
chkf 'int f(x,y) int x; int y; { struct s { int a:4; int b:4; } v; v.a=x; return v.a; }' 7 0 7
# value of a field-assignment expression: extract follows the FIELD's signedness
# (unsigned -> zero-extend, signed -> sign-extend), not the assign node's type.
chkf 'int f(x,y) unsigned x; unsigned y; { struct s { unsigned a:3; } v; return (v.a = x); }' 13 0 5
chkf 'int f(x,y) int x; int y; { struct s { int a:4; } v; return (v.a = x); }' -3 0 -3
# compound-assign + inc/dec on an int bitfield.  Z8000 has no memory-destination op,
# so AADD/ASUB use a single-temp masked load-modify-store (O_new = O ^ (((O op V) ^ O) &
# mask), which contains carry/borrow to the field -> the defined modular wrap); AAND/AOR/
# AXOR take modlfld's pre-masked rhs straight into the object.  ++/-- (prefix + effect-
# context postfix) lower to field +=1 / -=1 in modlfld.  Cover op correctness, neighbour
# preservation, signed/unsigned wrap, value context, and access via a far pointer.
chkf 'struct s { int a:5; int b:7; }; int f() { struct s x; x.a=9; x.b=3; x.b+=4; return x.b; }' 0 0 7
chkf 'struct s { int a:5; int b:7; }; int f() { struct s x; x.a=9; x.b=3; x.b+=4; return x.a; }' 0 0 9
chkf 'struct s { unsigned a:5; unsigned b:7; }; int f() { struct s x; x.b=100; x.b+=50; return x.b; }' 0 0 22
chkf 'struct s { int a:5; int b:7; }; int f() { struct s x; x.b=10; x.b-=4; return x.b; }' 0 0 6
chkf 'struct s { int a:5; int b:7; }; int f() { struct s x; x.b=15; x.b&=6; return x.b; }' 0 0 6
chkf 'struct s { int a:5; int b:7; }; int f() { struct s x; x.a=9; x.b=1; x.b|=4; return (x.b<<5)|x.a; }' 0 0 169
chkf 'struct s { int a:5; int b:7; }; int f() { struct s x; x.b=12; x.b^=10; return x.b; }' 0 0 6
chkf 'struct s { int a:5; int b:7; }; int f() { struct s x; int y; x.b=12; y=(x.b^=10); return y; }' 0 0 6
chkf 'struct s { int a:5; int b:7; }; int f() { struct s x; x.b=3; ++x.b; return x.b; }' 0 0 4
chkf 'struct s { int a:5; int b:7; }; int f() { struct s x; x.b=3; --x.b; return x.b; }' 0 0 2
chkf 'struct s { int a:5; int b:7; }; int f() { struct s x; x.b=3; x.b++; return x.b; }' 0 0 4
chkf 'struct s { int a:5; int b:7; }; int f() { struct s x; int i; x.b=0; for(i=0;i<5;i++) x.b++; return x.b; }' 0 0 5
chkf 'struct s { int a:5; int b:7; }; int f(p) struct s *p; { p->a=9; p->b=3; p->b+=4; return p->b; }' 0 0 7
chkf 'struct s { int a:5; int b:7; }; int f(p) struct s *p; { p->b=3; p->b++; return p->b; }' 0 0 4
# CHAR/BYTE bit fields.  A byte field lives in one byte of storage, so the read-
# modify-write uses byte loads/stores (LDB/ANDB/ORB), but the value being inserted is the
# usual word expression -> the FFLD8 rules take a WORD rhs and OR its low byte.  The signed
# read promotes the byte field to a word first, so the extract shifts run at mw=16 (the
# field's sign bit must reach bit 15); the narrow back to char is an in-place EXTSB/CLRB on
# the temp.  Cover store/read (signed+unsigned), negative values, the signed 4-bit wrap
# (5+3=8 -> -8), neighbour preservation, and compound-assign / inc-dec.
chkf 'struct s { char a:3; char b:4; }; int f() { struct s x; x.a=2; x.b=5; return x.b; }' 0 0 5
chkf 'struct s { char a:3; char b:4; }; int f() { struct s x; x.b=-3; return x.b; }' 0 0 -3
chkf 'struct s { unsigned char a:3; unsigned char b:4; }; int f() { struct s x; x.b=15; return x.b; }' 0 0 15
chkf 'struct s { char a:3; char b:4; }; int f() { struct s x; x.a=3; x.b=5; return x.a*100+x.b; }' 0 0 305
chkf 'struct s { char a:3; char b:4; }; int f() { struct s x; x.b=5; x.b+=3; return x.b; }' 0 0 -8
chkf 'struct s { unsigned char a:3; unsigned char b:4; }; int f() { struct s x; x.b=5; x.b+=3; return x.b; }' 0 0 8
chkf 'struct s { unsigned char a:3; unsigned char b:4; }; int f() { struct s x; x.b=14; x.b+=3; return x.b; }' 0 0 1
chkf 'struct s { char a:3; char b:4; }; int f() { struct s x; x.b=6; x.b&=5; return x.b; }' 0 0 4
chkf 'struct s { char a:3; char b:4; }; int f() { struct s x; x.b=4; x.b|=2; return x.b; }' 0 0 6
chkf 'struct s { char a:3; char b:4; }; int f() { struct s x; x.b=6; x.b^=3; return x.b; }' 0 0 5
chkf 'struct s { char a:3; char b:4; }; int f() { struct s x; x.b=5; ++x.b; return x.b; }' 0 0 6
chkf 'struct s { char a:3; char b:4; }; int f() { struct s x; x.b=5; x.b++; return x.b; }' 0 0 6
chkf 'struct s { char b:7; }; int f() { struct s x; x.b=-5; return x.b; }' 0 0 -5
# Narrowing cast of a word/long to char: load the LOW byte into the result reg's LOW half
# (RL), not the high half -- the narrow leaves.t rules used [R] (which encodes RH for a byte
# op) instead of [LO R], so (char)x / (unsigned char)x returned garbage (the byte landed in
# RH and EXTSB/CLRB then read the wrong half).  Signed sign-extends, unsigned clears RH.
chkf 'int f() { int x; x=300; return (char)x; }' 0 0 44
chkf 'int f() { int x; x=200; return (char)x; }' 0 0 -56
chkf 'int f() { int x; x= -1; return (unsigned char)x; }' 0 0 255
chkf 'int f() { int x; x=0xABCD; return (unsigned char)x; }' 0 0 205
chkf 'int f() { long l; l=0x1234; return (char)l; }' 0 0 52
# Byte-register convention: a byte VALUE lives in the LOW half (RL) of its word register.
# The byte rvalue LOAD (leaves.t) and byte COMPARE (relop.t CPB) used [R] (= RH for a byte
# op) while the byte STORE / widen / narrow use [LO R] (= RL).  So `char c = *p' (deref a
# frame char pointer, store to a char) crossed conventions: the deref wrote RH but the store
# read RL -- returning whatever stale value was in RL (it passed only by coincidence when an
# earlier byte store had left the right value there).  Load + compare now use [LO R] too.
chkf 'int f() { static char b[2]; char *p; char c; b[0]=66; p=b; c=*p; return c; }' 0 0 66
chkf 'int f() { static unsigned char b[2]; unsigned char *p; unsigned char c; b[0]=200; p=b; c=*p; return c; }' 0 0 200
chkf 'int f() { static char b[2]; char *p; char c; b[0]= -7; p=b; c=*p; return c; }' 0 0 -7
chkf 'int f() { static char b[3]; char *p; char c; b[1]=88; p=b; c=p[1]; return c; }' 0 0 88
chkf 'int f() { static char b[2]; char *p; b[0]=66; p=b; return *p==66; }' 0 0 1
chkf 'int f() { static char b[2]; char *p; char c; b[0]=10; p=b; c=*p+5; return c; }' 0 0 15
chkf 'int f() { static char s[4]; char *p; int n; s[0]=1;s[1]=1;s[2]=0; p=s; n=0; while(*p!=0){n++;p++;} return n; }' 0 0 2
# a BYTE truth-test (`if(c)' / `while(*p)', c/*p a char) TESTBs the memory byte
# directly instead of widening it (LDB + EXTSB + TEST).  Must be ZTESTB, not a bare ZTEST
# (which encodes a WORD test that reads the adjacent byte too -- the `adjacent' case proves
# it: c=0 with a non-zero neighbour must read FALSE).  Cover frame char, far-ptr deref, and
# a NUL-terminated walk (a word test would over-run the NUL).
chkf 'int f() { char c; c=5; if(c) return 7; return 0; }' 0 0 7
chkf 'int f() { char c; char d; c=0; d=99; if(c) return 1; return d; }' 0 0 99
chkf 'int f() { unsigned char c; c=200; if(c) return 1; return 0; }' 0 0 1
chkf 'int slen(s) register char *s; { register int n; n=0; while(*s){n=n+1;s=s+1;} return n; } int f(){ static char b[4]; b[0]=88;b[1]=89;b[2]=90;b[3]=0; return slen(b); }' 0 0 3
chkf 'int f() { static char b[4]; char *p; int n; b[0]=1;b[1]=1;b[2]=0; p=b; n=0; while(*p){n++;p++;} return n; }' 0 0 2
# effect-context `X = *p++;' (far pointer p) derefs straight into X then bumps p --
# (X = *p, p++) -- dropping the postfix pair copy with no temp.  Cover char + int targets,
# the `*d++ = *s++' (postfix on both sides), and that p advances exactly once per store.
chkf 'int f() { static char b[3]; register char *p; char c; int s; b[0]=65;b[1]=66; p=b; s=0; c=*p++; s+=c; c=*p++; s+=c; return s; }' 0 0 131
chkf 'int g[3]; int f() { register int *p; int x,s; g[0]=11;g[1]=22; p=g; s=0; x=*p++; s+=x; x=*p++; s+=x; return s; }' 0 0 33
chkf 'int f() { static char s[5]; static char d[5]; register char *p,*q; s[0]=65;s[1]=66;s[2]=67;s[3]=0; p=s;q=d; while(*q++=*p++); return d[0]+d[1]+d[2]; }' 0 0 198
# VALUE-context postfix bit-field (`y = field++`).  The compound-assign yields the NEW
# field, but a postfix needs the OLD value, and `(field += 1) - 1' would mis-read across
# the modular wrap -- so modlfld lowers it to `(tmp = field, field += 1, tmp)', reading the
# old value into a temp (off a deep copy of the FIELD subtree) before the increment.  Cover
# the yielded old value, the post-state of the field, a use in a larger expression, the
# unsigned wrap, neighbour preservation, and char fields (held in a word temp).
chkf 'struct s { int a:5; int b:7; }; int f() { struct s x; int y; x.b=5; y=x.b++; return y*100+x.b; }' 0 0 506
chkf 'struct s { int a:5; int b:7; }; int f() { struct s x; int y; x.b=5; y=x.b--; return y*100+x.b; }' 0 0 504
chkf 'struct s { int a:5; int b:7; }; int f() { struct s x; x.b=5; return 2*(x.b++); }' 0 0 10
chkf 'struct s { unsigned a:5; unsigned b:7; }; int f() { struct s x; int y; x.b=127; y=x.b++; return y*100+x.b; }' 0 0 12700
chkf 'struct s { int a:5; int b:7; }; int f() { struct s x; int y; x.a=9; x.b=5; y=x.b++; return x.a*1000+x.b*10+y; }' 0 0 9065
chkf 'struct s { char a:3; char b:4; }; int f() { struct s x; int y; x.b=5; y=x.b++; return y*100+x.b; }' 0 0 506
chkf 'struct s { char a:3; char b:4; }; int f() { struct s x; int y; x.a=3; x.b=6; y=x.b++; return x.a*100+x.b*10+y; }' 0 0 376
chkf 'struct s { char a:3; char b:4; }; int f() { struct s x; int y; x.b=-3; y=x.b++; return y; }' 0 0 -3
# struct passed BY VALUE: caller reserves a stack slot and inline-LDIRBs the struct
# into it (no blkmv helper). Exercises whole-struct copy, second-field read, mixed
# scalar+struct args, a live value across the copy, and two struct args.
chkf 'struct s { int a; int b; }; int g(p) struct s p; { return p.a + p.b; } int f() { struct s v; v.a=3; v.b=4; return g(v); }' 0 0 7
chkf 'struct s { int a; int b; }; int g(p) struct s p; { return p.b; } int f() { struct s v; v.a=11; v.b=22; return g(v); }' 0 0 22
chkf 'struct s { int a; int b; }; int g(k,p) int k; struct s p; { return k*100 + p.a + p.b; } int f() { struct s v; v.a=3; v.b=4; return g(9,v); }' 0 0 907
chkf 'struct s { int a; int b; }; int g(p) struct s p; { return p.a+p.b; } int f(x) int x; { struct s v; v.a=3; v.b=4; return x + g(v); }' 5 0 12
chkf 'struct s { int a; int b; }; int g(p,q) struct s p; struct s q; { return p.a+p.b+q.a+q.b; } int f() { struct s v; struct s w; v.a=1; v.b=2; w.a=3; w.b=4; return g(v,w); }' 0 0 10
chkf 'struct s { char a; char b; int c; }; int g(p) struct s p; { return p.a + p.b + p.c; } int f() { struct s v; v.a=5; v.b=7; v.c=100; return g(v); }' 0 0 112
# soft-float backend lowering: COMPILE-ONLY (no linker yet) -- cc1 must not
# crash and must emit the correct Z8001 libc/crt symbol. Arithmetic uses dl* (second
# operand by reference); conversions match libc (diflt/ifix/dfpack/...).
chkfc 'double f(a,b) double a; double b; { return a + b; }' dladd
chkfc 'double f(a,b) double a; double b; { return a - b; }' dlsub
chkfc 'double f(a,b) double a; double b; { return a * b; }' dlmul
chkfc 'double f(a,b) double a; double b; { return a / b; }' dldiv
chkfc 'int f(a,b) double a; double b; { return a > b; }' dlcmp
chkfc 'int f(a,b) double a; double b; { return a == b; }' dlcmp
chkfc 'double f(x) int x; { return x; }' diflt
chkfc 'double f(x) unsigned x; { return x; }' duflt
chkfc 'double f(x) long x; { return x; }' dlflt
chkfc 'double f(x) unsigned long x; { return x; }' dvflt
chkfc 'int f(a) double a; { return a; }' ifix
chkfc 'long f(a) double a; { return a; }' lfix
chkfc 'unsigned long f(a) double a; { return a; }' vfix
# float/double in a FLOW context (if/while/?:/&&) is an implicit `f != 0.0' -> dlcmp.
# Was a selfix<->iselect stack-overflow crash (no float TEST / truth-test rule).
chkfc 'int f(a) double a; { if(a) return 1; return 0; }' dlcmp
chkfc 'int f(a) float a; { if(a) return 1; return 0; }' dlcmp
# float/double value DISCARDED for effect (units.c: `d;', `atof(s);', `for(;;d+=1.0)').
# The i8086 NFLT/RREG effect-discard terminator excludes floats; the Z8001 soft-float keeps
# F32/F64 in register pairs so a discard is a no-op -- without the FLT|DBL discard rule the
# selfix<->iselect loop overflowed the stack (cc1 SEGV).  These must COMPILE (not hang/crash).
chkfc 'int f() { double d; d=1.0; d; return 0; }'
chkfc 'int f() { float d; d=1.0; d; return 0; }'
chkfc 'double g(); int f() { g(); return 0; }'
chkfc 'int f() { double d; d=0.0; for(;d<3.0;d+=1.0); return 0; }'
chkfc 'int f(a) double a; { return a ? 7 : 9; }' dlcmp
chkfc 'int f(a) double a; { int n; n=0; while(a){n++;if(n>3)break;} return n; }' dlcmp
chkfc 'int f(a,b) double a; int b; { return a && b; }' dlcmp
# constants / stores / load / mem=mem / float / mixed -- compile-clean (no symbol assert)
chkfc 'double f() { return 1.5; }'
chkfc 'double g; f(a,b) double a; double b; { g = a*b; }'
chkfc 'double f(a) double a; { double x; x = a; return x; }'
chkfc 'double f(a) double a; { return a * 2.0 + 1.5; }'
chkfc 'float f(a,b) float a; float b; { return a + b; }'
chkfc 'double f(a,b,c) double a; double b; double c; { return a*b + c/2.0; }'

# ---- inc/dec + compound-assign for non-WORD lvalues (long / pointer / char) ----
# char compound-assign + inc/dec (the node is WORD-typed over a byte lvalue)
chkf 'int f(){ char c; c=5; c+=2; return c; }' 0 0 7
chkf 'int f(){ char c; c=200; c+=100; return c; }' 0 0 44
chkf 'int f(){ char c; c=10; c-=3; return c; }' 0 0 7
chkf 'int f(){ char c; c=15; c&=9; return c; }' 0 0 9
chkf 'int f(){ char c; c=8;  c|=5; return c; }' 0 0 13
chkf 'int f(){ char c; c=15; c^=9; return c; }' 0 0 6
chkf 'int f(){ char c; c=3;  c<<=2; return c; }' 0 0 12
chkf 'int f(){ char c; c=80; c>>=2; return c; }' 0 0 20
chkf 'int f(){ char c; c=-80; c>>=2; return c; }' 0 0 -20
chkf 'f(){ unsigned char c; c=200; c>>=2; return c; }' 0 0 50
chkf 'int f(){ char c; c=5; c++; return c; }' 0 0 6
chkf 'int f(){ char c; c=5; return c++; }' 0 0 5
chkf 'int f(){ char c; c=5; --c; return c; }' 0 0 4
# long (32-bit) compound-assign + inc/dec
chkf 'long f(){ long l; l=10; l-=3; return l; }' 0 0 7
chkf 'long f(){ long l; l=15; l&=9; return l; }' 0 0 9
chkf 'long f(){ long l; l=8;  l|=5; return l; }' 0 0 13
chkf 'long f(){ long l; l=15; l^=9; return l; }' 0 0 6
chkf 'long f(){ long l; l=3;  l<<=4; return l; }' 0 0 48
chkf 'long f(){ long l; l=80; l>>=2; return l; }' 0 0 20
chkf 'long f(){ long l; l=5; l++; return l; }' 0 0 6
chkf 'long f(){ long l; l=5; ++l; return l; }' 0 0 6
chkf 'long f(){ long l; l=5; l--; return l; }' 0 0 4
# pointer compound-assign + inc/dec (offset scaled by element size)
chkf 'int f(){ int b[3]; int*p; p=b; p+=2; *p=9; return b[2]; }' 0 0 9
chkf 'int f(){ int b[4]; int*p; p=&b[3]; p-=2; *p=9; return b[1]; }' 0 0 9
chkf 'int f(){ int b[3]; int*p; p=b; b[1]=7; p++; return *p; }' 0 0 7
chkf 'int f(){ int b[3]; int*p; p=&b[2]; b[1]=7; p--; return *p; }' 0 0 7
chkf 'int f(){ char d[3]; char*p; p=d; d[1]=7; p++; return *p; }' 0 0 7
# deref of a PRE-incremented pointer in a value context: *++p / *--p
chkf 'int f(){ int b[3]; int*p; b[1]=7; p=b; return *++p; }' 0 0 7
chkf 'int f(){ int b[3]; int*p; b[1]=9; p=&b[2]; return *--p; }' 0 0 9
chkf 'int f(){ char d[3]; char*p; p=d; d[1]=7; return *++p; }' 0 0 7
# far-pointer truth test if(p)/while(p): TESTL the pair, no fixup loop
chkf 'int f(x) int x; { int*p; p=&x; if(p) return 7; return 9; }' 0 0 7
chkf 'int f(x) int x; { int*p; p=&x; if(!p) return 7; return 9; }' 0 0 9
chkf 'int f(x) int x; { int*p; int n; p=&x; n=0; while(p){n++;if(n>2)p=&x;if(n>4)break;} return n; }' 0 0 5
# (long)far-pointer conversion (units.c:145 `units[n].u_name += (long)sstart').  LPTR and
# S32 are bit-identical 2-word pairs (HI=seg/high, LO=offset/low), so modkind() must treat them
# the same kind -- else the CAST/CONVERT emits no terminating rule (botch CAST/CONVERT/ASSIGN/ADD).
chkf 'int f(x) int x; { int *p; long v; p=&x; v=(long)p; p=(int *)v; return *p; }' 8 0 8
chkf 'int f(x) int x; { int *p; long v; p=&x; v=(long)p; return (int)v == (int)p; }' 5 0 1
chkf 'int f(x) int x; { int *p; long v; p=&x; v=(long)p + 4; return (int)v == (int)p + 4; }' 9 0 1

# ---- carry / borrow across the 32-bit word boundary (long add/sub/inc/dec) ----
# Build 0x0000FFFF as 65536-1 to dodge the int-constant sign trap; >>16 reads the high word.
chkf 'long f(){ long l; l=65536; l-=1; l+=1; return l>>16; }' 0 0 1
chkf 'long f(){ long l; l=65536; l-=1; return l>>16; }'       0 0 0
chkf 'long f(){ long l; l=65536; l-=1; l++; return l>>16; }'  0 0 1
chkf 'long f(){ long l; l=65536; l--; return l>>16; }'        0 0 0
chkf 'long f(){ long a,b; a=65536; a-=1; b=1; return (a+b)>>16; }' 0 0 1
chkf 'long f(){ long a,b; a=65536; b=1; return (a-b)>>16; }'  0 0 0
chkf 'long f(){ long l; l=131072; return l>>16; }'            0 0 2
# 32-bit compound multiply/divide/remainder `l *= / /= / %=' (time.c:97 `tsec %= 3600').
# MULTL/DIVL on RQ0: ldl lvalue into RR2, extend RR0, MULTL/DIVL, store RR2 (product/quotient)
# or RR0 (remainder) back.  amul/adiv/arem.t had WORD rules only.
chkf 'int f(){ long l; l=100; l *= 7; return (int)l; }' 0 0 700
chkf 'int f(){ long l; l=100; l /= 7; return (int)l; }' 0 0 14
chkf 'int f(){ long l; l=100; l %= 7; return (int)l; }' 0 0 2
chkf 'int f(d){ long l; l=100; l /= d; return (int)l; }' 7 0 14
chkf 'int f(){ long l; l=0; l-=100; l %= 7; return (int)l; }' 0 0 -2
chkf 'int f(){ long l; l=300000; l /= 3; return (int)(l>>16); }' 0 0 1
# `(p-q)*sizeof *p' = far-ptr difference scaled back to a byte count (prof.c:192
# `realloc(dict,(dpp+1-dict)*sizeof *dpp)').  sizeof is UNSIGNED, so cc0 makes the element-
# size `>>' an unsigned (logical SRL) shift over the SIGNED pointer-difference operand -- the
# shr.t UWORD rule must accept a WORD (either-sign) left operand, not UWORD only.
chkf 'struct s{int a,b;}; int g(p,q) struct s *p; struct s *q; { return (p-q)*sizeof *p; } int f(){ struct s a[3]; return g(&a[2],&a[0]); }' 0 0 8
chkf 'int g(p,q) int *p; int *q; { return (p-q)*sizeof *p; } int f(){ int a[5]; return g(&a[4],&a[1]); }' 0 0 6
chkf 'int f(x) int x; { unsigned u; u = x >> 2; return u; }' 40 0 10

# far-pointer null assignment + null-terminated ptr-array walk
chkf 'int f(a) int a; { int*p; p=&a; p=0; return p==0; }' 0 0 1
chkf 'long f(){ long l; l=5; l=0; return l; }' 0 0 0
chkf 'int f(){ int x; int*a[3]; int**p; a[0]=&x; a[1]=&x; a[2]=0; p=a; { int n; n=0; while(*p){n++;p++;} return n; } }' 0 0 2

# ---- long (32-bit) POST inc/dec whose OLD value is used (LDL/SUBL/LDL/ADDL) ----
chkf 'long f(){ long l; l=5; return l--; }' 0 0 5
chkf 'long f(){ long l; l=5; return l++; }' 0 0 5
chkf 'long f(){ long l,m; l=5; m=l--; return l*10+m; }' 0 0 45
chkf 'long f(){ long l,m; l=5; m=l++; return l*10+m; }' 0 0 65
chkf 'int f(){ long s; int n; s=3; n=0; while(s--) n++; return n; }' 0 0 3
chkf 'int f(){ long l; l=5; if(l--) return l; return 99; }' 0 0 4
chkf 'int f(){ long l; l=0; if(l--) return 7; return 1; }' 0 0 1
# plain long truth-test in a flow context (if/while/?: -- was a selfix<->iselect crash)
chkf 'int f(){ long l; l=3; if(l) return 1; return 0; }' 0 0 1
chkf 'int f(){ long l; l=0; if(l) return 1; return 0; }' 0 0 0
chkf 'int f(){ long l; l=3; return l ? 7 : 9; }' 0 0 7
chkf 'int f(){ long l; l=0; return l ? 7 : 9; }' 0 0 9

# ---- audit: target the appropriate long opcode (no generic shortcut) ----
# long ==0 / !=0 -> TESTL (1 word), not CPL against a 32-bit zero immediate (3 words)
chkf 'int f(){ long l; l=5; if(l==0) return 7; return 9; }' 0 0 9
chkf 'int f(){ long l; l=0; if(l==0) return 7; return 9; }' 0 0 7
chkf 'int f(){ long l; l=0; if(l!=0) return 7; return 9; }' 0 0 9
# long ~l : COM both halves (no COML); low word read back
chkf 'long f(){ long l; l=5; return ~l; }' 0 0 -6
chkf 'long f(){ long l; l=0; return ~l; }' 0 0 -1
# long -l : two's complement (COM both + ADDL 1); low word + high-word(>>16) checks
chkf 'long f(){ long l; l=5; return -l; }' 0 0 -5
chkf 'long f(){ long l; l=65536; return (-l)>>16; }' 0 0 -1
chkf 'long f(){ long l; l=3; return (-l)&255; }' 0 0 253

# ---- LDK shortcut: small constant 0..15 into a register is 1-word LDK, not LD #imm ----
chklist 'int f(){ return 7; }'   'ldk '  yes   # 7 in 0..15 -> LDK
chkdis  'int f(){ return 0; }'   'clr '  yes   # 0 -> CLR (1 word), the dedicated zero
chklist 'int f(){ return 15; }'  'ldk '  yes   # boundary
chklist 'int f(){ return 5000; }' 'ldk ' no    # >15 -> LD #imm
chklist 'int f(a,b) int a; int b; { return a < b; }' 'ldk ' yes  # boolean true value
# value still correct (LDK loads the same constant)
chkf 'int f(){ return 7; }' 0 0 7
chkf 'int f(){ return 15; }' 0 0 15

# ---- single-operand op on a GLOBAL (pooled far-ptr deref @RRn): TEST/CLR/... ----
# Word/byte global truth-test if(g)/while(g)/g==0 -- ZTEST @RRn was an encode error
# (unhandled in BOTH run and -c paths); long globals already worked via ZTESTL.
chkf 'int g; int f(){ g=5; if(g) return 7; return 9; }' 0 0 7
chkf 'int g; int f(){ g=0; if(g) return 7; return 9; }' 0 0 9
chkf 'int g; int f(){ g=5; return g==0; }' 0 0 0
chkf 'int g; int f(){ g=5; return g!=0; }' 0 0 1
chkf 'char g; int f(){ g=3; if(g) return 7; return 9; }' 0 0 7
chkf 'int g; int f(){ int n; g=3; n=0; while(g){g=g-1;n++;} return n; }' 0 0 3

# ---- long-typed GLOBAL at a non-zero offset: LDL base+disp (load 0x35 / store 0x37) ----
chkf 'long g[5]; int f(){ g[2]=7; return g[2]; }' 0 0 7
chkf 'long g[5]; int f(){ g[0]=11; g[2]=7; return g[0]+g[2]; }' 0 0 18
chkf 'struct S{int a; long b;} gs; int f(){ gs.b=7; return gs.b; }' 0 0 7
chkf 'long g; int f(){ g=5; g++; return g; }' 0 0 6

# ---- far-pointer difference p - q (subtract offset halves; MI applies /elementsize) ----
chkf 'int f(){ char b[10]; char *p,*q; p=b; q=b+3; return q-p; }' 0 0 3
chkf 'int f(){ int b[10]; int *p,*q; p=b; q=b+3; return q-p; }' 0 0 3
chkf 'int f(){ long b[10]; long *p,*q; p=b; q=b+2; return q-p; }' 0 0 2
chkf 'int f(){ char b[10]; char *p,*q; p=b+8; q=b+3; return p-q; }' 0 0 5
chkf 'int n; char m[20]; int f(){ char *p; p=m+7; n=p-m; return n; }' 0 0 7

# ---- byte ordering compare between two MEMORY bytes (was miscompiled: the relop
# ---- forced the byte into RH0 but compared RL0 -- register-half mismatch) ----
chkf 'int f(){ char x[2]; x[0]=1; x[1]=2; return x[0]<x[1]; }' 0 0 1
chkf 'int f(){ char x[2]; x[0]=5; x[1]=2; return x[0]<x[1]; }' 0 0 0
chkf 'int f(){ char x[2]; x[0]=7; x[1]=7; return x[0]<=x[1]; }' 0 0 1
chkf 'int f(){ char x[3]; char *p,*q; x[0]=3; x[1]=9; p=x; q=x+1; return *p<*q; }' 0 0 1

# ---- CPB char-compare optimization: char-from-memory == / != byte-const compares
# ---- the byte in place (CPB), no int-promotion (no LDB+EXTSB+CP) ----
chkf 'int f(){ char b[2]; b[0]=0x2D; return b[0]==0x2D; }' 0 0 1
chkf 'int f(){ char b[2]; b[0]=0x2D; return b[0]==0x2E; }' 0 0 0
chkf 'int f(){ char b[2]; b[0]=0x2D; return b[0]!=0x2E; }' 0 0 1
chkf 'int f(){ char x; char *p; x=65; p=&x; return *p==0x41; }' 0 0 1
chkf 'int f(){ char b[2]; b[0]=0; return b[0]==0; }' 0 0 1
# signedness: an out-of-range constant must NOT narrow (stay an int compare)
chkf 'int f(){ char c; c=200; return c==200; }' 0 0 0
chkf 'int f(){ char c; c=200; return c==-56; }' 0 0 1
chkf 'int f(){ unsigned char c; c=200; return c==200; }' 0 0 1
# memory-direct byte compare (modelled on the i8086 ADR-byte rule): a char in memory
# compared to a constant is CPB mem,#k IN PLACE -- no LDB into a register first.  Covers a far
# deref (@RRn) and a frame/global byte; the MMX exact-match on the constant keeps mem-vs-mem
# and ordering compares on the register-load path (they are not encodable as CPB mem,mem).
chkdis 'int f(p) register char *p; { return *p == 0x2D; }' 'cpb @rr[0-9]+, \$45' yes
chkdis 'int f(p) register char *p; { return *p == 0x2D; }' 'ldb' no
chkf 'int f(p) char *p; { return *p == 0x41; } ' 0 0 0
chkf 'char gb; int f(x) int x; { gb=x; return gb == 0x41; }' 65 0 1
chkf 'char gb; int f(x) int x; { gb=x; return gb == 0x41; }' 66 0 0
# byte-zero store -> CLRB mem, not LDB mem,#0 (#16n idiom; matches the original `CLRB off').
# `char = 0' is WORD-typed (int-const promotion), so the byte-typed CLRB rule is bypassed --
# add a WORD-node/byte-lvalue/zero rule before the byte-immediate store.  Nonzero keeps LDB.
chkdis 'char g; int f() { g=0; return 0; }' 'clrb ' yes
chkdis 'char g; int f() { g=0; return 0; }' 'ldb' no
chkdis "char g; int f() { g='A'; return 0; }" 'ldb ' yes
chkf 'char g; int f() { g=0; return g+7; }' 0 0 7
chkf 'int f() { char c; c=0; return c; }' 0 0 0
# VALUE-CONTEXT byte truth-test: `!c' / `c==0' / `c!=0' as a VALUE (not flow) must
# test only the BYTE.  The char holds the low byte of x; the high byte is undefined, so a
# word TEST read garbage (f(256): c=0 but !c gave 0): the
# CPB narrowing wrongly fired on the ZERO constant too, dropping the protective widen and
# letting the value-context byte ==0 select a WORD test; guarded to nonzero so ==0/!=0 fall
# through to the byte truth-test rule (TESTB).  x has the low byte clear (c==0) when 256|x.
chkf 'int f(x) int x; { char c; c=x; return !c; }' 256 0 1
chkf 'int f(x) int x; { char c; c=x; return !c; }' 257 0 0
chkf 'int f(x) int x; { char c; c=x; return c==0; }' 512 0 1
chkf 'int f(x) int x; { char c; c=x; return c!=0; }' 512 0 0
chkf 'int f(x) int x; { unsigned char c; c=x; return !c; }' 256 0 1
chkf 'int f(x) int x; { char c; int r; c=x; r = !c; return r; }' 256 0 1
chkf 'int f(x) int x; { char c; c=x; return !!c; }' 256 0 0
# the emitted form: == const drops the EXTSB and uses CPB; ordering keeps the widen
chkdis 'int f(p) char *p; { return *p==0x2D; }' 'cpb '   yes
chkdis 'int f(p) char *p; { return *p==0x2D; }' 'extsb ' no
chkdis 'int f(p) char *p; { return *p<0x2D; }'  'extsb ' yes

# byte store-immediate `c=<const>' -> LDB mem,#imm directly (not LDK+LDB).
# Runnable across DA / frame / @RR / X-mode addressing; byte replicated in both
# halves, sim reads the high byte.
chkf 'char g; int f(){ g=0x41; return g; }' 0 0 65
chkf 'int f(){ char c; c=7; return c; }' 0 0 7
chkf 'int f(){ char x; char *p; p=&x; *p=0x55; return *p; }' 0 0 85
chkf 'int f(){ char a[4]; a[3]=9; a[0]=2; return a[3]+a[0]; }' 0 0 11
chkdis  'char g; int f(){ g=5; }'           'ldb '  yes
chklist 'char g; int f(){ g=5; }'           'ldk '  no
chkdis  'int f(p) char *p; { *p=0x20; }'    'ldb '  yes
chkdis  'int f(a) char a[]; { a[3]=7; }'    'ldb '  yes

# cross-branch copy-prop: `*++p' (far-ptr regvar, deref/test in one expr) must not leave a
# dead pair copy across the following branch.  Runnable: the value must stay correct.
chkf 'int g(x) char *x; { return *x; } int f() { char b[3]; char *q[3]; register char **p; b[0]=65; b[1]=66; q[0]=b; q[1]=b+1; q[2]=0; p=q; if (*++p && g(*p)) return **p; return 9; }' 0 0 66
chkf 'int f() { char b[2]; char *q[2]; register char **p; b[0]=88; q[0]=b; q[1]=0; p=q; if (*p) return **p; return 7; }' 0 0 88

# push-from-memory fold: a far-pointer deref passed as a call arg becomes PUSHL @R15,@Rs.
# Runnable: the callee must receive the correct pointer/value.
chkf 'int chk(s) char *s; { return *s; } int f() { static char x; char *q[2]; char **p; x=42; q[0]=&x; q[1]=0; p=q; return chk(*p); }' 0 0 42
chklist 'int g(s) char *s; { return *s; } int f(p) char **p; { return g(*p); }' 'pushl @rr[0-9]+' yes

# redundant-load peephole must NOT delete a far-pointer reload after the OFFSET half was
# bumped (INC R11 on RR10): `s[0]' and `s[1]' on a char* share the base, and a destructive
# bump for one deref clobbers the other unless the reload survives.  Was a live miscompile.
chkf 'int chk(s) char *s; { return s[0]+s[1]; } int f(){ char b[2]; b[0]=3; b[1]=7; return chk(b); }' 0 0 10
chkf 'int chk(s) char *s; { return s[0]*100+s[1]; } int f(){ char b[2]; b[0]=3; b[1]=7; return chk(b); }' 0 0 307
chkf 'int chk(s) char *s; { return s[2]+s[5]; } int f(){ static char b[6]; b[2]=3; b[5]=7; return chk(b); }' 0 0 10

# register coalescing (adjacent copy-forwarding): a regvar far-ptr passed as an arg is
# pushed directly (PUSHL @R15,RRp) instead of `LDL RR0,RRp ; PUSHL RR0'.  Runnable so the
# coalescing is execution-validated (the userland firings are object-mode only).
chkf 'int g(p) char *p; { return *p; } int f() { register char *p; static char c; c=99; p=&c; return g(p)+g(p); }' 0 0 198
chkf 'int g(p,q) char *p; char *q; { return *p + *q; } int f() { register char *p; register char *q; static char a,b; a=10;b=5; p=&a;q=&b; return g(p,q); }' 0 0 15
chklist 'int g(p) char *p; { return *p; } int f() { register char *p; static char c; p=&c; return g(p); }' 'ldl rr0, rr' no

# cross-block register coalescing (deletable register-source redirect): a regvar far pointer
# stored to memory must store the pair register HALVES directly (`LD D(R),Rhi ; LD @R,Rlo')
# instead of `LDL RR0,RRp ; LD D(R),R1 ; LD @R,R0'.  Runtime-validated so the d+1->s+1 half
# mapping is execution-checked: the value written through the stored pointer reads back right.
chkf 'char *gp,*gp2; char buf[40]; int f(x,y) int x; int y; { register char *p; register int n; p=buf; n=0; do { *p++ = n+y; n++; } while (n<x); gp=p; gp2=p; return p[-1] + (gp==gp2); }' 3 10 13
chkf 'char *gp,*gp2; char buf[40]; int f(x,y) int x; int y; { register char *p; register int n; p=buf; n=0; do { *p++ = n+y; n++; } while (n<x); gp=p; gp2=p; return p[-1] + (gp==gp2); }' 1 7 8
chkdis 'char *gp,*gp2; char buf[40]; int f(x) int x; { register char *p; p=buf; while(p<buf+x)*p++=x; gp=p; gp2=p; return p[-1]; }' 'ldl rr0, rr' no

# whole-function available-copies coalescer: a struct-return value assigned then read
# exercises an RR0-pair copy chain the coalescer rewrites; runtime-validated so the R0-base
# guard (an @RRd deref must NOT be repointed to the unencodeable @RR0) and the quad-op kill
# stay correct (line ~462's mk(x).a+mk(x).b is the matching effect-context case).
chkf 'struct s{int a;int b;}; struct s mk(x) int x;{ struct s r; r.a=x*2;r.b=x*3; return r;} int f(x) int x;{ struct s v; v=mk(x); return v.a + v.b; }' 4 0 20

# char `*=' / `/=' / `%=': MULT and DIV are word/long only on this ISA, so a byte lvalue is
# widen-compute-store-narrow.  MULT needs no widening (the low byte of a product depends only
# on the low bytes of the factors); DIV does, and the widening follows the LVALUE's signedness
# while the node stays int-typed.  All lvalue shapes (global / frame / array / far deref) and
# both the value and the plain-statement contexts.
chkf 'int f(){ char c; c=5;  c *= 3; return c; }' 0 0 15
chkf 'int f(){ char c; c=100; c *= 3; return c; }' 0 0 44
chkf 'int f(){ char c; c=-7; c *= 3; return c; }' 0 0 -21
chkf 'f(){ unsigned char c; c=100; c *= 3; return c; }' 0 0 44
chkf 'int f(d){ char c; c=7; c *= d; return c; }' 5 0 35
chkf 'int f(){ char c; c=100; c /= 3; return c; }' 0 0 33
chkf 'int f(){ char c; c=-100; c /= 3; return c; }' 0 0 -33
chkf 'int f(){ char c; c=100; c /= -3; return c; }' 0 0 -33
chkf 'f(){ unsigned char c; c=200; c /= 3; return c; }' 0 0 66
chkf 'int f(d){ char c; c=-100; c /= d; return c; }' 3 0 -33
chkf 'f(d){ unsigned char c; c=200; c /= d; return c; }' 3 0 66
chkf 'int f(){ char c; c=100; c %= 7; return c; }' 0 0 2
chkf 'int f(){ char c; c=-100; c %= 7; return c; }' 0 0 -2
chkf 'f(){ unsigned char c; c=200; c %= 7; return c; }' 0 0 4
chkf 'int f(d){ char c; c=-100; c %= d; return c; }' 7 0 -2
chkf 'char g; int f(d) int d; { g=100; g *= d; return g; }' 3 0 44
chkf 'char g; int f(d) int d; { g=-100; g /= d; return g; }' 3 0 -33
chkf 'char g; int f(d) int d; { g=-100; g %= d; return g; }' 7 0 -2
chkf 'char a[3]; int f(d) int d; { a[1]=50; a[1] *= d; return a[1]; }' 3 0 -106
chkf 'char a[3]; int f(d) int d; { a[1]=-99; a[1] /= d; return a[1]; }' 3 0 -33
chkf 'int g(p,d) char *p; int d; { *p *= d; return *p; } int f(d) int d; { char c; c=9; return g(&c,d); }' 4 0 36
chkf 'int g(p,d) char *p; int d; { *p /= d; return *p; } int f(d) int d; { char c; c=-90; return g(&c,d); }' 4 0 -22
chkf 'int g(p,d) char *p; int d; { *p %= d; return *p; } int f(d) int d; { char c; c=-90; return g(&c,d); }' 4 0 -2
# the truth/relational consumers of a char compound multiply-divide (the relop takes the
# rvalue, so these only need the PRVALUE byte rules to exist)
chkf 'int f(d){ char c; c=6; if (c *= d) return 1; return 0; }' 0 0 0
chkf 'int f(d){ char c; c=6; if (c *= d) return 1; return 0; }' 3 0 1
chkf 'int f(d){ char c; c=90; if ((c /= d) < 10) return 1; return 0; }' 10 0 1

# a char compound assign USED AS A VALUE yields the STORED char widened back to int, not the
# undropped word the arithmetic left in the temp.  Every operator, both signednesses.
chkf 'int f(){ char c; int v; c=100; v = (c += 100); return v; }' 0 0 -56
chkf 'int f(){ char c; int v; c=-100; v = (c -= 100); return v; }' 0 0 56
chkf 'int f(){ char c; int v; c=100; v = (c *= 3); return v; }' 0 0 44
chkf 'int f(){ char c; int v; c=-100; v = (c /= 3); return v; }' 0 0 -33
chkf 'int f(){ char c; int v; c=-100; v = (c %= 7); return v; }' 0 0 -2
chkf 'int f(){ char c; int v; c=64; v = (c <<= 1); return v; }' 0 0 -128
chkf 'int f(){ char c; int v; c=-1; v = (c &= -1); return v; }' 0 0 -1
chkf 'int f(){ char c; int v; c=0; v = (c |= 255); return v; }' 0 0 -1
chkf 'int f(){ char c; int v; c=-100; v = (c ^= 15); return v; }' 0 0 -109
chkf 'int f(){ char c; int v; c=127; v = ++c; return v; }' 0 0 -128
chkf 'int f(){ char c; int v; c=-128; v = --c; return v; }' 0 0 127
chkf 'f(){ unsigned char c; int v; c=200; v = (c += 100); return v; }' 0 0 44
chkf 'f(){ unsigned char c; int v; c=200; v = (c *= 3); return v; }' 0 0 88
chkf 'f(){ unsigned char c; int v; c=200; v = (c /= 3); return v; }' 0 0 66
chkf 'f(){ unsigned char c; int v; c=200; v = (c <<= 1); return v; }' 0 0 144
chkf 'f(){ unsigned char c; int v; c=200; v = (c |= 55); return v; }' 0 0 255
chkf 'f(){ unsigned char c; int v; c=255; v = ++c; return v; }' 0 0 0
# the same, with a runtime rhs and a global lvalue (register/memory operand rules)
chkf 'char g; int y; int f(d) int d; { int v; g=100; y=d; v = (g += y); return v; }' 100 0 -56
chkf 'char g; int y; int f(d) int d; { int v; g=64; y=d; v = (g <<= y); return v; }' 1 0 -128
chkf 'char g; int y; int f(d) int d; { int v; g=100; y=d; v = (g *= y); return v; }' 3 0 44

# BIGOFF: constant displacements past 32K into a >32K static object.  The i1
# symbol-relative offset is two words (32 bits, afield.c/gen1.c); a displacement
# in [0x8000, 0xFFFF] keeps the symbol's segment -- no borrow on a positive
# addend.  Boundary below/at/above 0x8000, char and int arrays, decimal-long
# and hex-unsigned index spellings, deep displacement, and runtime-vs-constant
# indexing agreeing on the same cell.
chkf 'char a[40000]; int f(d) int d; { a[0x7FFE]=d; return a[0x7FFE]; }' 42 0 42
chkf 'char a[40000]; int f(d) int d; { a[0x7FFF]=d; return a[0x7FFF]; }' 43 0 43
chkf 'char a[40000]; int f(d) int d; { a[0x8000]=d; return a[0x8000]; }' 44 0 44
chkf 'char a[40000]; int f(d) int d; { a[0x8001]=d; return a[0x8001]; }' 45 0 45
chkf 'char a[40000]; int f(d) int d; { a[32768]=d; return a[32768]; }' 46 0 46
chkf 'char a[40000]; int f(d) int d; { a[39999]=d; return a[39999]; }' 47 0 47
chkf 'int w[20000]; int f(d) int d; { w[16383]=d; return w[16383]; }' 48 0 48
chkf 'int w[20000]; int f(d) int d; { w[16384]=d; return w[16384]; }' 49 0 49
chkf 'int w[20000]; int f(d) int d; { w[17000]=d+1; w[19999]=d; return w[17000]+w[19999]; }' 51 0 103
chkf 'char a[40000]; int f(d) int d; { int i; i=39999; a[i]=d; return a[39999]; }' 52 0 52
chkf 'char a[40000]; char *p; int f(d) int d; { p = a; p[39999L] = d; return a[39999]; }' 53 0 53
# the static-initializer path (gen2.c iexpr): a far pointer datum &a[39999]
chkf 'char a[40000]; char *p = &a[39999]; int f(d) int d; { *p = d; return a[39999]; }' 54 0 54
# negative symbol-relative folds still borrow correctly (the other horn, 7.46)
chkf 'char a[40000]; int f(d) int d; { a[3]=d; return *(&a[4]-1); }' 55 0 55
chkf 'int f(d) int d; { char b[10]; char *p; p = &b[5]; p[-1] = d; return b[4]; }' 56 0 56

# BIGOFF linked-object gates.  The segment borrow lives in cc2's DA segword and
# ld's flat relocation arithmetic -- the Go run harness resolves globals itself
# in one segment (mod 64K) and cannot see it -- so these go cc2 -> ld -> run.
# Each stores through a CONSTANT displacement past 0x8000 and reads the cell
# back through a RUNTIME index (whose address is always right); a borrowed
# segment loses the store and the readback misses.
AS="$O/../as-z8001"; LD="$O/../ld-z8001"
LT="$(mktemp -d)"
printf '\t.globl\tSS\nSS = 0\n' > "$LT/ss.s"; "$AS" -o "$LT/ss.o" "$LT/ss.s" 2>/dev/null
chklnk() { # "<full source defining f()>" want
  printf '%s\n' "$1" > "$LT/f.c"
  "$O/cc0-z8001" $VAR "$LT/f.c" "$LT/f.z0" 2>/dev/null
  timeout 5 "$O/cc1-z8001" $VAR "$LT/f.z0" "$LT/f.z1" 2>/dev/null || { echo "  FAIL(cc1) [$1]"; fail=$((fail+1)); return; }
  "$O/cc2-z8001" 0010 "$LT/f.z1" "$LT/f.o" "$LT/f.scr" 0 2>/dev/null || { echo "  FAIL(cc2) [$1]"; fail=$((fail+1)); return; }
  "$LD" -R 0x200 -e f_ -o "$LT/f.out" "$LT/f.o" "$LT/ss.o" 2>/dev/null || { echo "  FAIL(ld) [$1]"; fail=$((fail+1)); return; }
  g=$("$N2" -runobjint "$LT/f.out" 2>/dev/null | grep -oE 'R1 = -?[0-9]+' | grep -oE '\-?[0-9]+$')
  if [ "$g" = "$2" ]; then pass=$((pass+1)); else echo "  FAIL(lnk) [$1] ->[$g] want $2"; fail=$((fail+1)); fi
}
chklnk 'char a[40000]; int f(){ int i; a[0x7FFF]=41; a[0x8000]=42; a[39999]=43; i=0x7FFF; if (a[i]!=41) return 1; i=0x8000; if (a[i]!=42) return 2; i=39999; if (a[i]!=43) return 3; return 90; }' 90
chklnk 'int w[20000]; int f(){ int i; w[16383]=311; w[16384]=312; w[17000]=313; w[19999]=314; i=16383; if (w[i]!=311) return 1; i=16384; if (w[i]!=312) return 2; i=17000; if (w[i]!=313) return 3; i=19999; if (w[i]!=314) return 4; return 91; }' 91
chklnk 'char a[40000]; char *p = &a[39999]; int f(){ int i; *p=77; i=39999; if (a[i]!=77) return 1; return 92; }' 92
chklnk 'char a[40000]; int f(){ int i; char *q; i=4; a[3]=88; q = &a[i]; return q[-1]; }' 88

# the half that only a LINK can see.  A single object tells you nothing about what
# its SYMBOL TABLE says: an encoder can bind a static's address correctly in memory and
# still publish the wrong name for it, or none.  The failure this pins is a static whose
# name is dropped -- it becomes an undefined external (ld fails, loud) and its entry
# address gets published under the PREVIOUS global's still-pending name, so an unrelated
# global resolves to the static's code (silent, and only visible across objects).  Two
# objects, linked by ld, run as a real a.out: file A defines a global, a static behind a
# function-pointer table, and a caller; file B calls the global by name.  When this
# breaks it dies `Ld: symbol shidden_: undefined', and had it linked, B's gread(31)
# would have entered shidden().  1031 + (31+7) = 1069.
chkgo2() { # "<file A>" "<file B, defines f()>" want
  printf '%s\n' "$1" > "$LT/a.c"; printf '%s\n' "$2" > "$LT/b.c"
  for m in a b; do
    "$O/cc0-z8001" $VAR "$LT/$m.c" "$LT/$m.z0" 2>/dev/null
    timeout 5 "$O/cc1-z8001" $VAR "$LT/$m.z0" "$LT/$m.z1" 2>/dev/null \
      || { echo "  FAIL(cc1) [go2 $m]"; fail=$((fail+1)); return; }
    "$O/cc2-z8001" ${PEEP:-0010} "$LT/$m.z1" "$LT/$m.o" "$LT/$m.scr" 0 >/dev/null 2>&1 \
      || { echo "  FAIL(cc2) [go2 $m]"; fail=$((fail+1)); return; }
  done
  "$LD" -R 0x200 -e f_ -o "$LT/g.out" "$LT/b.o" "$LT/a.o" "$LT/ss.o" 2>/dev/null \
    || { echo "  FAIL(ld) [go2] -- a static's name is undefined or unbound"; fail=$((fail+1)); return; }
  g=$("$N2" -runobjint "$LT/g.out" 2>/dev/null | grep -oE 'R1 = -?[0-9]+' | grep -oE '\-?[0-9]+$')
  if [ "$g" = "$3" ]; then pass=$((pass+1)); else echo "  FAIL(go2) ->[$g] want $3"; fail=$((fail+1)); fi
}
chkgo2 'int gread(n) int n; { return n + 1000; }
static int shidden(n) int n; { return n + 7; }
int (*hook)() = shidden;
int callhook(n) int n; { return (*hook)(n); }' \
       'extern int gread(); extern int callhook();
int f() { return gread(31) + callhook(31); }' 1069

# the data half of the same class: a symbol table derived from the FUNCTION names
# alone never exports a defined data global, so another object's `extern int hook;' has
# nothing to resolve against.  Single-object gates cannot see this -- they compile one
# file and never link.  When this breaks it dies `Ld: symbol hook_: undefined' /
# `garr_: undefined'.
# 4100 (returned) + 4100 (read by name) + 7 (stored through the array) = 8207.
chkgo2 'int hook = 4100;
int garr[3];
int gset(v) int v; { garr[0] = v; return hook; }' \
       'extern int hook; extern int garr[]; extern int gset();
int f() { int r; r = gset(7); return r + hook + garr[0]; }' 8207
# a char array + an initialized far pointer INTO it: the exported symbol is read
# through a data-segment relocation as well as from code.
chkgo2 'char msg[6];
char *mp = msg;
int mset() { msg[0] = 60; msg[1] = 9; return 0; }' \
       'extern char msg[]; extern char *mp; extern int mset();
int f() { mset(); return msg[0] + mp[1]; }' 69
# a file-scope static datum must stay OUT of the symbol table even though it now
# shares one table with the exported globals: file B defines its own `hidden'
# (matching A's static in the first 16 characters ld compares) and must see 5.
chkgo2 'static int hiddencounterxx = 1;
int abump() { hiddencounterxx = hiddencounterxx + 1; return hiddencounterxx; }' \
       'int hiddencounterxy = 5; extern int abump();
int f() { abump(); return hiddencounterxy; }' 5

# An encoder whose symbol table comes out of an unordered container
# produces different object BYTES for identical input (3 distinct md5s in 8 runs of
# the OS tree's cmd/wc.c, when this was last live).  That silently removes byte-comparison as a
# way to A/B any other change to the encoder, so it is gated: same input, six runs,
# identical objects.
chkdet() { # "<full source>"
  printf '%s\n' "$1" > "$LT/d.c"
  "$O/cc0-z8001" $VAR "$LT/d.c" "$LT/d.z0" 2>/dev/null
  timeout 5 "$O/cc1-z8001" $VAR "$LT/d.z0" "$LT/d.z1" 2>/dev/null \
    || { echo "  FAIL(cc1) [det]"; fail=$((fail+1)); return; }
  m1=""; m2=""
  for k in 1 2 3 4 5 6; do
    "$O/cc2-z8001" ${PEEP:-0010} "$LT/d.z1" "$LT/d$k.o" "$LT/d.scr" 0 >/dev/null 2>&1 \
      || { echo "  FAIL(cc2) [det]"; fail=$((fail+1)); return; }
    h=$(md5sum < "$LT/d$k.o")
    if [ -z "$m1" ]; then m1=$h; elif [ "$h" != "$m1" ]; then m2=$h; fi
  done
  if [ -z "$m2" ]; then pass=$((pass+1));
  else echo "  FAIL(det) -- cc2 object not reproducible: $m1 vs $m2"; fail=$((fail+1)); fi
}
chkdet 'int alpha; int bravo = 2; char charlie[5]; int delta = 4; int echo7[3];
static int foxtrot = 6;
int ga() { return alpha; } int gb() { return bravo; } int gc() { return charlie[0]; }
int gd() { return delta; } int ge() { return echo7[0]; }
static int gf() { return foxtrot; }
int f() { return ga() + gb() + gc() + gd() + ge() + gf(); }'
rm -rf "$LT"

# a modify-phase temporary (the far-double-index hoist) is live across code()'s
# per-statement curtemp restart; selection temporaries of the SAME statement must
# allocate beyond it, not on top of it.  Shaped like libcurses makech(): the 4-byte
# far-pointer temp holding cur->rows[wy+begy] and the 2-byte spill of w->begx must
# get disjoint frame slots.  First gate reads the pointer back, second stores
# through it (the libcurses corruption wrote the data-segment base).
mkch='struct win {
	short cury, curx, maxy, maxx, begy, begx, flags, attrs, choff;
	char clear, leave, scroll, keypad, nodelay;
	char **rows; short *firstch, *lastch; struct win *nextp, *orig;
};
char r0[8], r1[8], r2[8];
char *rowv[4];
struct win curw, thew;
struct win *cur;
short fc[4], lc[4];
static int
step(w, wy)
register struct win *w;
short wy;
{
	register char *nsp, *csp, *ce;
	register short wx, lch, y;
	register int nlsp, clsp;

	wx = w->firstch[wy] - w->choff;
	lch = w->lastch[wy] - w->choff;
	y = wy + w->begy;
	csp = &cur->rows[wy + w->begy][wx + w->begx];
	nsp = &w->rows[wy][wx];
	ce = &w->rows[wy][w->maxx - 1];
	nlsp = ce - w->rows[wy];
	clsp = nlsp + lch + y + wx;
	RESULT
}
int f(x, y) int x; int y; {
	cur = &curw;
	rowv[0] = r0; rowv[1] = r1; rowv[2] = r2;
	curw.rows = rowv; thew.rows = rowv; thew.maxx = 4;
	thew.firstch = fc; thew.lastch = lc;
	fc[1] = 0; lc[1] = 3;
	return step(&thew, 1);
}'
chkf "$(printf '%s' "$mkch" | sed 's/RESULT/return (csp == r1) + clsp;/')" 0 0 8
chkf "$(printf '%s' "$mkch" | sed 's/RESULT/*csp = 42; return r1[0] + clsp;/')" 0 0 49


# ---- == / != against a byte-width CAST operand.  The cast leaves the byte in a
# ---- REGISTER (low half, RLn); T_ADR covers a register as well as memory, so the
# ---- memory-direct CPB rule matches it and must dial the low half out ([LO AL]/[LO AR])
# ---- rather than encode the register number as a byte register (which names RHn).
# ---- Ordering compares, a byte VARIABLE and a short cast take other paths and are the
# ---- guard that the low-half selector did not overshoot.
chk 'return (char)x == 36;' 36 0 1
chk 'return (char)x == 36;' 37 0 0
chk 'return (char)x != 36;' 36 0 0
chk 'return (char)x != 36;' 37 0 1
chk 'return (int)(char)x == 36;' 36 0 1
chk 'return (unsigned char)x == 36;' 36 0 1
chk 'return (char)x == y;' 36 36 1
chk 'return (char)x == y;' 36 37 0
chk 'return (char)x == 36;' 292 0 1
chk 'return (char)x == (char)y;' 36 36 1
chk 'return (char)x == (char)y;' 36 292 1
chk 'return (char)x != (char)y;' 36 37 1
chk 'return (char)x;' 36 0 36
chk 'return (char)x < 100;' 36 0 1
chk 'return (char)x > 10;' 36 0 1
chk 'return (short)x == 36;' 36 0 1
chk 'return x == 36;' 36 0 1
chk 'char d; d = x; return d == 36;' 36 0 1
chk 'return (char)x == 0;' 36 0 0
chk 'return (char)x == 0;' 256 0 1
chk 'return (char)x == -1;' 255 0 1
chk 'return (unsigned char)x == 255;' 511 0 1
chk 'return (unsigned char)x > 200;' 250 0 1
chkf 'char gb; int f(x,y) int x; int y; { gb = x; return (char)x == gb; }' 36 0 1
chkf 'int f(x,y) int x; int y; { char b[4]; b[1] = x; return (char)x == b[1]; }' 36 0 1
chkf 'int f(x,y) int x; int y; { char b[4]; char *p; b[2] = x; p = &b[2]; return (char)x == *p; }' 36 0 1
chkf 'int f(x,y) int x; int y; { char b[4]; char *p; b[2] = x; p = &b[2]; return *p == (char)x; }' 36 0 1
# the memory-direct form is unchanged: still one in-place CPB, no LDB into a register
chkdis 'int f(p) register char *p; { return *p == 0x2D; }' 'cpb @rr[0-9]+, \$45' yes
chkdis 'char gb; int f() { return gb == 0x2D; }' 'ldb' no

# double subscript through a POINTER-TO-ARRAY-OF-CHAR with both subscripts in
# registers.  cc0 left-associates the char (scale-1 inner index) case as
# (base + i*64) + j, grouping a SCALED term against a far base gencoll cannot encode
# -- cc1 aborted with "collect" (1006).  Found porting unzip's LoadFollowers.
chkf 'unsigned char tab[3][4]; unsigned char (*fp)[4];
int f(x,y) int x; int y; { register int i, j; fp = tab; i = x; j = y;
	fp[i][j] = 7; return fp[i][j] + fp[0][0] + tab[x][y]; }' 2 3 14

# `p[k] + n' where p[k] is a far pointer LOADED out of memory and the sum is used as a
# VALUE -- stored to a pointer variable, or passed as an argument.  The int-LEFT 32-bit
# rule reads its pointer operand as a MEMORY OPERAND, and this one has no memory-operand
# form: its address is a pool-mediated base plus a SCALED index, which the Z8000 has no
# addressing mode for, so the encoder aborted ("collect", 1006).  The corpus had loaded
# far pointers only in ADDRESS position (`*(p[k] + n)', where the parent dereferences the
# sum), which takes a different rule, so nothing here reached the value rule with one --
# that is why `make check' passed while screen/ansi.c, atc/input.c and ttycity/nc_menu.c
# could not be compiled at all.  Each form below is a separate operand position: an
# array of pointers, a pointer variable, a struct field, and a call argument.
chkf 'char *rows[3]; char r1[8];
int f(x,y) int x; int y; { register char *i; register int k;
	rows[1] = r1; r1[3] = 42; k = 1;
	i = rows[k] + x; return *i + y; }' 3 5 47
chkf 'char **pp; char *rows[3]; char r1[8];
int f(x,y) int x; int y; { register char *i; register int k;
	rows[1] = r1; r1[3] = 42; pp = rows; k = 1;
	i = pp[k] + x; return *i + y; }' 3 5 47
chkf 'struct s { char *image[3]; }; struct s sv; struct s *curr; char r1[8];
int f(x,y) int x; int y; { register char *i; register int k;
	curr = &sv; curr->image[1] = r1; r1[3] = 42; k = 1;
	i = curr->image[k] + x; return *i + y; }' 3 5 47
chkf 'char **pp; char *rows[3]; char r1[8];
int g(p) char *p; { return *p; }
int f(x,y) int x; int y; { register int k;
	rows[1] = r1; r1[3] = 42; pp = rows; k = 1;
	return g(pp[k] + x) + y; }' 3 5 47

# byte narrow of a `register' variable that landed in R8..R12, which have no
# byte half -- genadr dialed ramode[-1] and cc2 botched ("genins: reg-dest source
# mode", 2C59).  Seven word regvars exhaust the byte-capable R6/R7 so `h' has none.
# Found porting pico's LineEdit.  (char)200 = -56, plus 6*1 = -50.
chkf 'int add6(a,b,c,d,e,g) int a; int b; int c; int d; int e; int g; { return a+b+c+d+e+g; }
int f(x,y) int x; int y; { register int a,b,c,d,e,g,h; a=x;b=x;c=x;d=x;e=x;g=x;h=y;
	return (char)h + add6(a,b,c,d,e,g); }' 1 200 -50

# A pointer-typed STATIC named as itself is a pointer OBJECT and
# loads/stores directly (DA); it used to be pooled like an array's address, so every
# read of one burned a register PAIR on the pool base.  With three far-pointer
# `register' variables holding RR6/RR8/RR10, that extra pair was the one the selector
# no longer had -- selrv() spilled the argument to a stack temp, the spill assignment
# needed the same pair again, and selection looped to the "more than 20 stores" botch.
# Found porting awk's xfield().  ev(NFp)=*B=3, i1=10-3=7, 7*10 + (s1-as) + (s2-as) = 73.
chkf 'long ev(p) char *p; { return ((long)*p); }
char *NFp; char B[4];
int f(x,y) int x; int y; { register char *as, *s1, *s2; register int i1;
	B[0] = 3; NFp = B; as = B; s1 = B+1; s2 = B+2; i1 = x;
	if (0 < (i1 -= ev(NFp))) return (i1*10 + (s1-as) + (s2-as));
	return (y); }' 10 0 73
# the same DA-direct rule must NOT reach the CALLEE position: a directly addressable
# callee is the call TARGET, so a function pointer read that way would call the
# variable's own address instead of its contents (mtree2.c poolcallee).
chkf 'int so(m) int m; { return m+37; } int sw(m,n) int m; int n; { return m*100+n; }
int (*gfp)(); int (*ct[2])();
int f(x,y) int x; int y; { gfp = y ? sw : so; ct[0] = so; ct[1] = sw;
	return (*gfp)(x,3) + (*ct[0])(x) + (*ct[1])(x,1); }' 5 0 585
# a pointer-typed static read, written, indexed and dereferenced -- the DA-direct
# forms of each.  q=NFp, *NFp, NFp[2], NFp+n, and a store through it.
chkf 'char *NFp; char B[6]; char *q;
int f(x,y) int x; int y; { B[0]=x; B[2]=y; NFp = B; q = NFp; *q = x+1;
	NFp = NFp + 1; *NFp = 9;
	return (q == B) + B[0]*10 + B[1] + B[2]; }' 4 7 67

# memory-left word compare `CP mem,#k'.  A global compared against a constant with
# nothing already holding it is compared IN PLACE -- the Z8000 compare has a memory
# destination (DA 8 bytes segmented, X 6) against `LD R0,mem ; CP R0,#k' at 10 and 8 -- as
# the original MWC backend does (`CP 0x03:0x35A0,#0x0002').  No LD is emitted for it.
chkdis 'int gw; int f() { return gw == 2; }' 'cp gw_, \$2$' yes
chkdis 'int gw; int f() { return gw == 2; }' 'ld r[0-9]+, gw_' no

# ...and the other half: when the value IS already in a register the n2 peephole (cpstate's
# cmpmem) folds the operand back to that register, so the in-place form never costs the
# extra memory read.  Here `a' is computed into a register and STORED to its frame slot
# just before the compare -- the store is what tells the peephole the register still holds
# the slot -- so the compare must read the REGISTER, not the slot.
chklist 'int f(x,y) int x; int y; { int a; a = x + y; if (a > 2) return 1; return 0; }' \
	'cp -?[0-9]+\(r13\), \$2$' no

# Both forms must still compute the right answer (ordering, not just equality: CP is a real
# subtract-compare and sets V/C).
chkf 'int gwv;
int f(x,y) int x; int y; { gwv = x; if (gwv > 2) return gwv * 10; return -1; }' 7 0 70
chkf 'int gwv;
int f(x,y) int x; int y; { gwv = x; if (gwv > 2) return gwv * 10; return -1; }' 2 0 -1
chk 'int a; a = x + y; if (a > 2) return a; return -1;' 5 4 9
chk 'int a; a = x + y; if (a > 2) return a; return -1;' 1 0 -1


# a store through an absolute address built as `<long constant> + (long)<int>'
# -- the ROM-video / memory-mapped-device idiom, `*(char *)(0x3a000000L + (long)i)'.
# The (char *) cast sinks onto the sum's left operand, so the sum keeps its C type
# (LONG) while its left operand is typed LPTX, and no 32-bit add rule admitted that
# pair of types in an LVALUE context.  select() fell through to seltree(MRVALUE) +
# selfix, whose FIXUP had no lvalue rule either, and the two re-entered each other
# until the stack ran out: cc1 SEGFAULTED (no ICE, no message).  Found in the CP/M
# console driver (cpm8000/c900/src/crsr.c) and in libc's monitor.c, which could not
# be compiled at all.  Both halves of the address must survive: the constant carries
# the SEGMENT, so a rule that adds only the offset word silently writes elsewhere.
# Every case below DEREFERENCES the sum -- that is the shape that crashed.  Writing
# it to a long variable instead does not (it is then ordinary long arithmetic, and it
# compiled before this fix), so a value-only check here would pass either way.
chkf 'int f(x,y) int x; int y; { *(char *)(0x00030000L + (long)x) = y; return (*(char *)(0x00030000L + (long)x) & 0xff); }' 18 90 90
chkf 'int f(x,y) int x; int y; { *(int *)(0x00030000L + (long)x) = y; return (*(int *)(0x00030000L + (long)x)); }' 18 42 42
chkf 'int f(x,y) int x; int y; { *(char *)(0x00030000L + (long)(x * 2)) = y; return (*(char *)(0x00030000L + (long)(x * 2)) & 0xff); }' 9 90 90
chkf 'int f(x,y) int x; int y; { *(char *)(0x00030100L - (long)x) = y; return (*(char *)(0x00030100L - (long)x) & 0xff); }' 16 90 90
chkf 'int g(){ return (0x0012); } int f(x,y) int x; int y; { *(char *)(0x00030000L + (long)g()) = y; return (*(char *)0x00030012L & 0xff); }' 0 90 90
# the WHOLE 32-bit constant must reach the address in one ADDL/SUBL.  A rule that
# adds only the offset word (the LPTX + WORD form) would drop the SEGMENT and store
# somewhere else entirely, and no value check inside one 64K segment would notice.
chkdis 'f(off,ch) int off; int ch; { *(char *)(0x3a000000L + (long)off) = ch; }' 'addl rr[0-9]+, \$973078528' yes
chkdis 'f(off,ch) int off; int ch; { *(char *)(0x3a000000L - (long)off) = ch; }' 'subl rr[0-9]+, rr[0-9]+' yes
# libc/gen/monitor.c line 44 in miniature: an address-typed value plus an int width
chkf 'int f(x,y) int x; int y; { long a; a = ((long)&x) + sizeof(x); return (*(int *)a != 0 || 1); }' 1 0 1

# The sibling case: `<long constant> + <long VARIABLE>' folded into a deref.
# Where the widened int is a CONVERT the walk stops at, a long lvalue lets
# findoffs walk on: the ADD's constant right operand is T_NUM, so it is collected into
# the addressing mode as a DISPLACEMENT.  A Z8000 displacement is 16 bits and is added
# to the OFFSET word alone -- it cannot reach the SEGMENT -- so genadr emitted the low
# half only.  For 0x3a000000L, whose low half is zero, NOTHING was emitted: the store
# became a bare `LDB @RRn,RLs' into segment 0, correct-looking code with no diagnostic.
# Fixed in findoffs (n1/z8001/amd.c): a long constant whose upper half is neither 0 nor
# a sign extension is a segment, not a displacement, so it stays in the tree for ADDL.
# A value round trip through the sum CANNOT see this -- store and load drop the segment
# alike and agree with each other -- so the two run cases below plant a marker in
# segment 0 through a known-good path and check that the shape does NOT touch it.
chkf 'char buf[4]; int f(x,y) int x; int y; { long o; buf[0] = 0; o = (long)buf & 0xFFFFL; *(char *)(0x03000000L + o) = y; return (buf[0] & 0xff); }' 0 65 0
chkf 'char buf[4]; int f(x,y) int x; int y; { long o; buf[0] = y; o = (long)buf & 0xFFFFL; return (*(char *)(0x03000000L + o) & 0xff); }' 0 65 255
# the whole 32-bit constant must reach the address, exactly as above
chkdis 'f(off,ch) int off; int ch; { long o; o = (long)off; *(char *)(0x3a000000L + o) = ch; }' 'addl rr[0-9]+, \$973078528' yes
chkdis 'f(o,ch) long o; int ch; { *(char *)(0x3a000000L + o) = ch; }' 'addl rr[0-9]+, \$973078528' yes
chkdis 'int f(o) long o; { return (*(char *)(0x3a000000L + o) & 0xff); }' 'addl rr[0-9]+, \$973078528' yes
# ... and a constant that DOES fit the displacement must still fold, or the fix would
# have cost an instruction on every far-pointer field access.
chkdis 'f(off,ch) int off; int ch; { long o; o = (long)off; *(char *)(0x00002000L + o) = ch; }' 'ldb rr[0-9]+\(8192\), rl[0-9]+' yes
chkdis 'f(off,ch) int off; int ch; { long o; o = (long)off; *(char *)(0x00002000L + o) = ch; }' 'addl' no

# ------------------------------------------------- ICE 5149, and the pressure that found it
# store() spills an unaddressable subtree to a stack temp and enqueues an assignment whose
# right side is THAT SAME subtree; when the subtree still cannot be addressed the next round
# stores it again, so the list grew without converging and NSTORE only said how long it took.
# Reached by exhausting the register PAIRS: three far-pointer register variables plus a
# `register int' take R6..R12, and inside the call argument a word temp took R5 -- stranding
# RR4 -- and the long call result took RR2, leaving only RR0, which is not a legal Z8000
# base register.  The far dereference in the argument then had no pair to address through.
#
# Both halves of the fix are asserted here.  store() now refuses a second store of one
# subtree, so non-convergence is impossible rather than merely bounded; and rallo() spends
# the least capable register that will do, so the long result takes RR0 -- which can hold a
# long but can never be an address -- and leaves RR2 to address with.  The three shapes are
# value assertions, not compile checks: the register the fix frees is the one the dereference
# uses, so only running the code proves it addressed the right memory.
#
# `evalint' returns long: the narrowing of a long call result to an int is what allocates the
# word temp that used to strand a pair, so a version returning int does not reproduce this.
ice5149='struct s { char *p; };
char *cp;
char **PP;
struct s SS1;
struct s *SP;
long evalint(q) char *q; { return ((long)(q[0] & 0xff)); }
g(i, pp) int i; char **pp;
{
	register char *as, *s1, *s2;
	register int i1;
	i1 = i;
	if (0 < (i1 -= evalint(%s)))
		return (i1);
	return (-1);
}
int f(x,y) int x; int y; { cp = "A"; PP = &cp; SS1.p = cp; SP = &SS1; return (g(x, &cp)); }'
chkf "$(printf "$ice5149" '*PP')"   100 0 35
chkf "$(printf "$ice5149" '*PP')"    50 0 -1
chkf "$(printf "$ice5149" '*pp')"   100 0 35
chkf "$(printf "$ice5149" '*pp')"    50 0 -1
chkf "$(printf "$ice5149" 'SP->p')" 100 0 35
chkf "$(printf "$ice5149" 'SP->p')"  50 0 -1
# The pressure itself: three far-pointer register variables plus a register int, saved as
# R6..R12.  Without this the six cases above could pass by not being under pressure at all.
chkdis 'struct s { char *p; };
char **PP;
struct s *SP;
long evalint();
f(i, pp) int i; char **pp;
{
	register char *as, *s1, *s2;
	register int i1;
	as = *pp; s1 = *PP; s2 = SP->p;
	i1 = i;
	if (0 < (i1 -= evalint(as)))
		return (1);
	return (s1[0] + s2[0]);
}' 'autos 0 r6 r7 r8 r9 r10 r11 r12' yes
# The long call result belongs in RR0 -- it can hold a long and can never be an address, so
# spending it costs no addressing capability and saves the copy out of the return pair.
chkdis 'long evalint(); f(i) int i; { register char *as, *s1, *s2; register int i1;
	i1 = i; if (0 < (i1 -= evalint(as))) return (1); return (0); }' 'ldl rr2, rr0' no

# Every assertion in this file runs in every checkout, so the totals are the whole
# story and the summary line says only what happened.  There was a skip counter
# here, carried on the SAME line as the totals because a transcript is read by its
# last line and "719 passed, 0 failed" over a suite that quietly skipped a third of
# its instruction-stream assertions is a lie of omission.  It counted chkdis
# assertions given up when the Go disassembler was unbuildable -- it decodes through
# a simulator, which is not here.  The oracle is now cc3's selection dump and cc2's
# emit listing,
# both built from src/ here, so nothing can be absent and nothing can skip: the
# counter could only ever print 0, and a branch that is never taken is not a
# safeguard, it is an unread claim that one exists.
echo "=== regression: $pass passed, $fail failed ==="
[ $fail = 0 ]
