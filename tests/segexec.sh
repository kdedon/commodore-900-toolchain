#!/bin/sh
# segexec.sh -- END-TO-END execution gate: build a FULL crt0+main program at the Coherent
# seg-3 userbase (ccz default) and run it through the sim's syscall shim (-runexec), checking
# the program's stdout.  This exercises the whole deliverable pipeline -- cc0->cc1->cc2 (seg-3
# LR_LONG relocations) -> ld (crt0 + libc @ segment 3) -> execute with syscall emulation.
#
# Scope: programs that emit via the raw write() syscall.  Buffered stdio (printf) additionally
# needs libc FILE/_iob init in the minimal sim environment (a separate follow-on), so the cases
# here use write() directly.
H="$(cd "$(dirname "$0")/.." && pwd)"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
# built artifact, not a /tmp scratch file (see segrun.sh)
LOUTDIS=$(sh "$H/host/loutdis.sh")
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
run() { "$N2" -runexec "$1" 2>/dev/null; }		# program stdout only (exit line is on stderr)
chk() {	# "<full C source with main()>" "<expected stdout>"
	printf '%s\n' "$1" > "$T/e.c"
	"$CCZ" -o "$T/e" "$T/e.c" >/dev/null 2>&1 || { echo "  FAIL(build) [$2]"; fail=$((fail+1)); return; }
	es=$("$LOUTDIS" -hdr "$T/e" 2>/dev/null | grep -oE 'entry=0x3[0-9a-f]+')
	[ -n "$es" ] || { echo "  FAIL(not seg 3) [$2]"; fail=$((fail+1)); return; }
	got=$(run "$T/e")
	if [ "$got" = "$2" ]; then pass=$((pass+1)); else echo "  FAIL got=[$got] want=[$2]"; fail=$((fail+1)); fi
}

chk 'main(){ write(1, "hello, seg3!\n", 13); }' 'hello, seg3!'
chk 'main(){ char b[4]; b[0]=65; b[1]=66; b[2]=67; b[3]=10; write(1, b, 4); }' 'ABC'
chk 'main(){ char b[6]; int i; for(i=0;i<5;i=i+1) b[i]=i+48; b[5]=10; write(1,b,6); }' '01234'
chk 'main(){ write(1,"seg",3); write(1,"=",1); write(1,"3\n",2); }' 'seg=3'

# Far-pointer postinc through a MEMORY lvalue: `*fp->_cp++ = c' must advance the field's
# OFFSET word (not the segment) AND land the byte at the OLD pointer.  A struct-field far pointer
# and a global far pointer both go through the memory (load-modify-store) path.
chk 'struct F { char *p; }; char b[8]; struct F g;
     put(fp,c) struct F *fp; int c; { *fp->p++ = c; }
     main(){ g.p=b; put(&g,72); put(&g,105); put(&g,10); write(1,b,g.p-b); }' 'Hi'
chk 'char *gp; char b[8];
     main(){ gp=b; *gp++=88; *gp++=89; *gp++=10; write(1,b,gp-b); }' 'XY'
# Prefix (bef.t) memory far pointer: `*++p' advances before use.
chk 'char *gp; char b[8];
     main(){ gp=b; b[0]=63; *++gp=90; *++gp=10; write(1,b,3); }' '?Z'

# Data-segment word alignment: an ODD-length string literal must not misalign the
# word/long data that follows it (the Z8000 masks the low address bit on word access, so a
# far pointer read one byte off corrupts stdio's FILE state).  Exercise via buffered stdio,
# which reads _stdout's pointer fields -- odd- AND even-length strings must both print.
chk '#include <stdio.h>
     main(){ fputs("odd\n", stdout); return 0; }' 'odd'
chk '#include <stdio.h>
     main(){ fputs("even\n", stdout); return 0; }' 'even'
chk 'main(){ puts("puts"); return 0; }' 'puts'
chk 'main(){ putchar(104); putchar(105); putchar(10); return 0; }' 'hi'

# printf: the K&R stack-walking varargs + an indirect call through _stdout->_pt (a
# function-pointer field at a NONZERO struct offset).  The call target load `LDL RR0,disp(@RRn)'
# must not drop the base when the far pointer sits in RR0 (R0 is not a valid BA base register).
chk '#include <stdio.h>
     main(){ printf("hi %d %s\n", 42, "there"); return 0; }' 'hi 42 there'
chk '#include <stdio.h>
     main(){ printf("%x %c %d\n", 255, 65, -7); return 0; }' 'FF A -7'
# Indirect call through a far-field function pointer at a nonzero offset (the core case).
chk 'struct F { int pad[9]; int (*fn)(); };
     char ob[2]; struct F g;
     hit(){ ob[0]=89; ob[1]=10; return 0; }
     int (*init)() = hit;   /* static-init avoids the separate runtime-store issue */
     call(fp) struct F *fp; { (*fp->fn)(); }
     main(){ g.fn = init; call(&g); write(1, ob, 2); return 0; }' 'Y'
# Runtime store of a function's ADDRESS: `gp = fn' / `g.fn = fn' must pool a real
# far pointer (code SEGMENT relocated), not two immediate word stores whose seg word stays
# 0 -- else the indirect call jumps into seg 0 in a segmented link.
chk 'int mk; char ob[2]; int (*gp)();
     target(){ mk=88; return 0; }
     main(){ gp = target; mk=0; (*gp)(); ob[0]="0"[0]+(mk==88); ob[1]=10; write(1,ob,2); return 0; }' '1'
chk 'struct F { int pad[9]; int (*fn)(); }; struct F g; int mk; char ob[2];
     sethit(){ mk=88; return 0; }
     call(fp) struct F *fp; { (*fp->fn)(); }
     main(){ g.fn = sethit; mk=0; call(&g); ob[0]="0"[0]+(mk==88); ob[1]=10; write(1,ob,2); return 0; }' '1'

echo "=== end-to-end seg-3 execution (syscall shim): $pass passed, $fail failed ==="
[ "$fail" = 0 ]
