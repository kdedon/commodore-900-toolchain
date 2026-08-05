#!/bin/sh
# effdiff.sh -- userland EFFICIENCY regression by DISASSEMBLY (no sim).  For every cmd/*.c
# that has an exported original binary, disassemble cc2's object and compare per-function
# byte sizes to the ORIGINAL stripped binary (matched by opcode signature).  The original
# MWC-compiled binaries are the only meaningful efficiency baseline: comparing our backend
# to another of our own encoders says nothing about whether we are fast enough for the
# machine.  Uses loutdis on both sides; the sim is never invoked.
H="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/donor.sh"
B="${C900_BUILD:-$H/host/build}"	# the lane's build dir; see host/publish.sh
O="$B/z8001"; VAR="${VAR:-800000000800}"; LD=$(sh "$H/host/loutdis.sh")
# BIN: the ORIGINAL MWC-compiled binaries, the only honest efficiency baseline.
CMD="$Z8001_DONOR/cmd"; INC="$Z8001_DONOR/include"; BIN="${ORIG_BIN:-$Z8001_DONOR/bin}"
T=$(mktemp -d); trap 'rm -rf $T' EXIT
funcs(){ "$LD" -funcs "$1" 2>/dev/null | grep -E '^  [0-9a-f]{8}'; }
python3 - "$O" "$VAR" "$CMD" "$INC" "$BIN" "$LD" <<'PY'
import subprocess,sys,os,glob,tempfile
O,VAR,CMD,INC,BIN,LD=sys.argv[1:7]
def sh(c): return subprocess.run(c,shell=True,capture_output=True,text=True)
def funcs(p):
    r=sh(f"{LD} -funcs {p}")
    out=[]
    for ln in r.stdout.splitlines():
        ln=ln.strip()
        if len(ln)>=8 and all(ch in '0123456789abcdef' for ch in ln[:8]):
            f=ln.split()
            # addr bytes insns far call ...opcodes
            ops={}
            for tok in f[5:]:
                if ':' in tok:
                    k,v=tok.split(':'); ops[k]=int(v)
            out.append({'bytes':int(f[1]),'insns':int(f[2]),'ops':ops})
    return out
def sig(a,b):  # opcode-profile distance
    ks=set(a['ops'])|set(b['ops']); return sum(abs(a['ops'].get(k,0)-b['ops'].get(k,0)) for k in ks)
tot_c=tot_o=0; worse_orig=0; nfun=0; matched_orig=0; tools=0
for src in sorted(glob.glob(CMD+"/*.c")):
    u=os.path.basename(src)[:-2]
    raw=open(src,'rb').read()
    if sum(1 for b in raw if b not in b'\t\n\r' and not(32<=b<127))>64: continue
    d=tempfile.mkdtemp()
    if sh(f"{O}/cc0-z8001 {VAR} {src} {d}/z0 -I{INC}").returncode: continue
    if sh(f"{O}/cc1-z8001 {VAR} {d}/z0 {d}/z1").returncode: continue
    if sh(f"{O}/cc2-z8001 0010 {d}/z1 {d}/c.o {d}/scr 0").returncode: continue
    cf=funcs(f"{d}/c.o")
    if not cf: continue
    tools+=1
    for c in cf: tot_c+=c['bytes']; nfun+=1
    # cc2 vs original: greedy signature-match each cc2 func to the closest original func
    of=funcs(f"{BIN}/{u}") if os.path.exists(f"{BIN}/{u}") else []
    used=set()
    for i,c in enumerate(cf):
        best=-1;bd=1e9
        for j,o in enumerate(of):
            if j in used: continue
            dd=sig(c,o)+abs(c['insns']-o['insns'])
            if dd<bd: bd=dd;best=j
        if best>=0 and bd<=8:  # accept only close matches
            used.add(best); matched_orig+=1; tot_o+=of[best]['bytes']
            if c['bytes']>of[best]['bytes']+0: worse_orig+= (1 if c['bytes']>of[best]['bytes'] else 0)
print(f"tools={tools} funcs(cc2)={nfun} cc2total={tot_c}B")
print(f"[cc2 vs original, signature-matched] matched={matched_orig} funcs"
      f"  origsum(matched)={tot_o}B  cc2-worse-than-orig={worse_orig}")
PY
