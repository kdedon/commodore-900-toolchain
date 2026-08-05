#!/bin/sh
# effdiff-linked.sh -- whole-binary EFFICIENCY diff (no sim).  For each cmd/*.c that has an
# exported original binary: cc0->cc1->cc2 -> ld (crt0 + cmd.o + libc-z8001.a) -> a complete
# l.out, disassemble it AND the original, and per-function size-match by opcode signature.
# Linking resolves real addresses, so cc2's addressing modes match the original's -- the
# signature match is reliable (unlike the object-level compare).  Same libc SOURCE both
# sides, so matched libc functions are a clean cc2-vs-original codegen comparison.
H="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/donor.sh"
B="${C900_BUILD:-$H/host/build}"	# the lane's build dir; see host/publish.sh
O="$B/z8001"; AS="$B/as-z8001"; LD="$B/ld-z8001"
LIBC="$B/libc-z8001"; V2="${VAR:-800000020800}"
D="$Z8001_DONOR"; CMD="$D/cmd"; INC="$D/include"
BIN="${ORIG_BIN:-$Z8001_DONOR/bin}"; LDIS=$(sh "$H/host/loutdis.sh")
[ -f "$LIBC/libc-z8001.a" ] || { echo "run build-libc-z8001.sh first"; exit 1; }
python3 - "$O" "$AS" "$LD" "$LIBC" "$V2" "$CMD" "$INC" "$BIN" "$LDIS" <<'PY'
import subprocess,sys,os,glob,tempfile
O,AS,LD,LIBC,V2,CMD,INC,BIN,LDIS=sys.argv[1:10]
def sh(c): return subprocess.run(c,shell=True,capture_output=True,text=True)
def funcs(p):
    out=[]
    for ln in sh(f"{LDIS} -funcs {p}").stdout.splitlines():
        ln=ln.strip()
        if len(ln)>=8 and all(c in '0123456789abcdef' for c in ln[:8]):
            f=ln.split(); ops={}
            for t in f[5:]:
                if ':' in t: k,v=t.split(':'); ops[k]=int(v)
            out.append({'bytes':int(f[1]),'insns':int(f[2]),'ops':ops})
    return out
def dist(a,b):
    ks=set(a['ops'])|set(b['ops'])
    return sum(abs(a['ops'].get(k,0)-b['ops'].get(k,0)) for k in ks)+abs(a['insns']-b['insns'])
T=tempfile.mkdtemp()
sh(f"printf '\\t.globl\\tSS\\nSS = 0\\n' > {T}/ss.s && {AS} -o {T}/ss.o {T}/ss.s")
tools=linked=0; mtot_c=mtot_o=0; nm=0; wins=ties=losses=0; lossmag=[]
for src in sorted(glob.glob(CMD+"/*.c")):
    u=os.path.basename(src)[:-2]
    if not os.path.exists(f"{BIN}/{u}"): continue
    raw=open(src,'rb').read()
    if sum(1 for b in raw if b not in b'\t\n\r' and not(32<=b<127))>64: continue
    tools+=1; d=tempfile.mkdtemp()
    if sh(f"{O}/cc0-z8001 {V2} {src} {d}/z0 -I{INC}").returncode: continue
    if sh(f"{O}/cc1-z8001 {V2} {d}/z0 {d}/z1").returncode: continue
    if sh(f"{O}/cc2-z8001 0010 {d}/z1 {d}/o {d}/scr 0").returncode: continue
    r=sh(f"{LD} -R 0x100 -o {d}/a.out {LIBC}/crt0.o {d}/o {T}/ss.o {LIBC}/libc-z8001.a")
    if r.returncode or not os.path.exists(f"{d}/a.out"): continue
    linked+=1
    cf=funcs(f"{d}/a.out"); of=funcs(f"{BIN}/{u}")
    if not cf or not of: continue
    used=set()
    for c in cf:
        best=-1; bd=1e9
        for j,o in enumerate(of):
            if j in used: continue
            dd=dist(c,o)
            if dd<bd: bd=dd; best=j
        if best>=0 and bd<=2:   # near-exact opcode+insn match => same function
            used.add(best); o=of[best]; nm+=1; mtot_c+=c['bytes']; mtot_o+=o['bytes']
            if c['bytes']<o['bytes']: wins+=1
            elif c['bytes']>o['bytes']: losses+=1; lossmag.append((u,c['bytes']-o['bytes']))
            else: ties+=1
print(f"tools-with-original={tools}  linked-ok={linked}")
print(f"matched functions (opcode+insn near-exact): {nm}")
print(f"  cc2 vs original on matched: cc2={mtot_c}B  orig={mtot_o}B  delta={mtot_c-mtot_o:+d}")
print(f"  wins(cc2 smaller)={wins}  ties={ties}  losses={losses}")
if lossmag:
    print(f"  loss total={sum(m for _,m in lossmag)}B; worst:", sorted(lossmag,key=lambda x:-x[1])[:8])
PY
