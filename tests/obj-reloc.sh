#!/bin/sh
# object-emit relocations: a cc2 object must relocate CALLs, &fn function
# addresses (immFix) and data references (gidFix) so ld can place the segments.
# We link a small program and decode the linked l.out, checking each relocated
# word resolved into the CORRECT segment (code -> text range, data -> data range),
# not the run-mode absolute 0xC000 nor an unrelocated in-segment offset.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
B="${C900_BUILD:-$H/host/build}"	# the lane's build dir; see host/publish.sh
O="$B/z8001"; AS="$B/as-z8001"
LD="$B/ld-z8001"; VAR="${VAR:-800000000800}"
CC2="$O/cc2-z8001"; PEEP="${PEEP:-0010}"
[ -x "$CC2" ] || { echo "obj-reloc: cc2-z8001 not built"; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '\t.globl\tSS\nSS = 0\n' > "$T/ss.s"; "$AS" -o "$T/ss.o" "$T/ss.s" 2>/dev/null
fail=0
encode() { # <stem> : .z1 -> .o
	"$CC2" $PEEP "$T/$1.z1" "$T/$1.o" "$T/$1.scr" 0 2>/dev/null
}
# relocation count, read from the OBJECT's own l.out header rather than from encoder
# chatter: ss[8] (REL) is at byte 40, and records are 5 or 7 bytes, so a nonzero REL
# section means at least one relocation was emitted.  cc2 emits no diagnostics at all,
# so there is no encoder chatter to read this off instead.
relsize() { python3 -c 'import sys;b=open(sys.argv[1],"rb").read();print((b[40]|b[41]<<8)<<16|(b[42]|b[43]<<8))' "$T/$1.o"; }
link() { # <name> <csrc>
	printf '%s\n' "$2" > "$T/$1.c"
	"$O/cc0-z8001" $VAR "$T/$1.c" "$T/$1.z0" 2>/dev/null
	"$O/cc1-z8001" $VAR "$T/$1.z0" "$T/$1.z1" 2>/dev/null
	encode "$1"
	"$LD" -R 0x200 -e f_ -o "$T/$1.out" "$T/$1.o" "$T/ss.o" 2>/dev/null
}

# Data reference: every SL data-address word must land in the linked data segment.
link dref 'int gv 5; int f() { gv = gv + 37; return gv; }'
r=$(python3 - "$T/dref.out" <<'PY'
import sys
b=open(sys.argv[1],'rb').read()
tb=b[6]|b[7]<<8; pdp=lambda o:(b[o]|b[o+1]<<8)<<16|(b[o+2]|b[o+3]<<8)
ts=pdp(8); ds=pdp(8+16)
base=0x200; dlo=base+ts; dhi=dlo+ds
w=[ (b[tb+i]<<8|b[tb+i+1]) for i in range(0,ts,2) ]
addrs=[w[i+1] for i in range(len(w)-1) if w[i]==0x8000]
ok=addrs and all(dlo<=a<dhi for a in addrs)
print("PASS" if ok else "FAIL data addrs=%s want[%#x,%#x)"%([hex(a) for a in addrs],dlo,dhi))
PY
)
echo "  data-ref reloc (gv in data segment)   $r"; [ "$r" = PASS ] || fail=1

# Function address (&g) stored to a pointer + indirect CALL: `&g' is a far CODE pointer
# consumed as a VALUE, so (like &data) it is POOLED into the data segment as a real
# far pointer whose OFFSET word relocates to g's linked code address (0x200 with -R 0x200)
# and whose SEGMENT word relocates to the code segment (0 flat).  Assert the reloc is
# emitted, the link succeeds, and g's address 0x200 appears in the pooled DATA literal.
src='int g(x) int x; { return x+1; } int f() { int (*p)(); p = g; return (*p)(41); }'
printf '%s\n' "$src" > "$T/fref.c"
"$O/cc0-z8001" $VAR "$T/fref.c" "$T/fref.z0" 2>/dev/null
"$O/cc1-z8001" $VAR "$T/fref.z0" "$T/fref.z1" 2>/dev/null
encode fref
nrel=$(relsize fref)
"$LD" -R 0x200 -e f_ -o "$T/fref.out" "$T/fref.o" "$T/ss.o" 2>/dev/null
r=$(python3 - "$T/fref.out" <<'PY'
import sys
b=open(sys.argv[1],'rb').read()
tb=b[6]|b[7]<<8; pdp=lambda o:(b[o]|b[o+1]<<8)<<16|(b[o+2]|b[o+3]<<8)
ts=pdp(8); ds=pdp(8+16)
data=b[tb+ts:tb+ts+ds]
dw=[data[i]<<8|data[i+1] for i in range(0,len(data),2)]
print("PASS" if 0x0200 in dw else "FAIL (&g addr 0x200 not in pooled data %s)"%[hex(w) for w in dw])
PY
)
[ "${nrel:-0}" -ge 1 ] || r="FAIL (no reloc emitted)"
echo "  &fn reloc (&g pooled, relsize=$nrel B)  $r"; [ "$r" = PASS ] || fail=1

# Pointer baked IN the data segment (ZGPTR): taking &global pools a far pointer in
# data; its offset word must relocate to point at the global inside the data segment.
link zgptr 'int gv 5; int *f() { return &gv; }'
r=$(python3 - "$T/zgptr.out" <<'PY'
import sys
b=open(sys.argv[1],'rb').read()
tb=b[6]|b[7]<<8; pdp=lambda o:(b[o]|b[o+1]<<8)<<16|(b[o+2]|b[o+3]<<8)
ts=pdp(8); ds=pdp(8+16)
base=0x200; dlo=base+ts; dhi=dlo+ds
data=b[tb+ts:tb+ts+ds]
dw=[data[i]<<8|data[i+1] for i in range(0,len(data),2)]
ptrs=[w for w in dw if dlo<=w<dhi]  # a data word that points back into the data segment
print("PASS" if ptrs else "FAIL (ZGPTR offset not relocated into data %s)"%[hex(w) for w in dw])
PY
)
echo "  ZGPTR-in-data reloc (&gv pooled)      $r"; [ "$r" = PASS ] || fail=1

[ $fail = 0 ] && echo "obj-reloc: ALL PASS" || { echo "obj-reloc: FAIL"; exit 1; }
