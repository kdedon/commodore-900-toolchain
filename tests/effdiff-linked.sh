#!/bin/sh
# effdiff-linked.sh -- whole-binary EFFICIENCY comparison by DISASSEMBLY (no sim).  For
# each cmd/*.c that has an exported original binary: cc0->cc1->cc2 -> ld (crt0 + cmd.o +
# libc-z8001.a) -> a complete l.out, then disassemble that AND the original 1985
# MWC-compiled binary and size-match per function by opcode signature.
#
# Linking is the point.  It resolves real addresses, so cc2's addressing modes take the
# forms the original's do, and the same libc SOURCE is on both sides -- a matched libc
# function is a clean cc2-vs-original codegen comparison.  tests/effdiff.sh is the fast
# unlinked sweep; this is the accurate size comparison.
#
# The originals are STRIPPED, so there is no name to match on.  Functions are split out
# of the text by their FP-setup prologue and paired by signature: each cc2 function takes
# the unused original whose (top-opcode profile, instruction count) is nearest, and the
# pair is ACCEPTED ONLY if that distance is within $EFFDIFF_MAXDIST, which here is 2 --
# near-exact.  That threshold is the whole character of this instrument.
#
# WHAT THIS HARNESS CANNOT SEE
#
#   * A defect that changes a function's shape by more than the match threshold.  Pairing
#     is by RESEMBLANCE, so a function our backend compiles badly enough stops resembling
#     its original and is dropped as UNMATCHED rather than reported as worse.  The codegen
#     defects large enough to matter are therefore the ones most likely to leave the
#     comparison altogether.  This harness is MORE exposed to that than effdiff.sh, not
#     less: its threshold is 2 where effdiff.sh's is 8, so a function needs only a couple
#     of instructions of divergence to fall out.  Read the PAIRING COUNT, not the delta.
#     The self-test measures the exact perturbation at which pairing goes blind and prints
#     it on every run.
#   * Consequently, the pairing count is a MEASUREMENT, not bookkeeping.  Against the
#     compiler before the frame re-base only 20 functions could be paired with the
#     originals; against the current one, 137.  That jump is evidence the codegen took the
#     original's shape, and a summary that printed only the byte delta would have thrown
#     the signal away.  A fall in pairing is a regression report even when the delta on
#     what still pairs looks fine.
#   * Anything the pairing gets WRONG.  The signature is loutdis's top opcodes plus an
#     instruction count, which is not an identity: two same-shaped leaf functions can pair
#     with each other's originals and both compare clean.  A stripped binary offers no
#     name-level confirmation.
#   * Whole-binary composition.  Both sides are linked, so a matched pair may be a libc
#     function neither compiler's codegen owns equally -- our libc archive and the 1985
#     one are not member-for-member the same library.
#   * Speed.  Bytes are the only axis.  A smaller function is not a faster one.
#   * Anything not compiled or not linked: sources cc0/cc1/cc2 reject and programs ld
#     cannot resolve.  Both are counted in the coverage block rather than passed over.
#
# A run that compared nothing REFUSES.  Zero programs linked, zero matched functions, or
# fewer than $EFFDIFF_MIN_MATCH matches is an error naming what was missing, not a summary
# -- "no functions compared" must never read like "no differences found".
#
# SS is the stack segment: cc2 emits frame addresses with a segment byte of 0 and a byte
# relocation against the external symbol SS, and the LINK supplies the value.  csu/crts0.s
# defines it, so crt0.o carries it and a program links without help.  A crt0 that does not
# define it needs a stub object that does; the link probe below settles which of the two
# this build is, once, rather than assuming, so neither an undefined SS nor a redefined
# one can turn into an empty comparison reported as clean.
#
# Inputs, all external and none assumed:
#   $Z8001_DONOR   the userland corpus, cmd/ and include/       (tests/donor.sh)
#   $LOUTDIS       the l.out disassembler                       (host/loutdis.sh)
#   $ORIG_BIN      the original MWC-compiled binaries; defaults to $Z8001_DONOR/bin
#
# Usage:
#   sh tests/effdiff-linked.sh              compare, after the self-test
#   sh tests/effdiff-linked.sh --selftest   the self-test alone; needs python3 and nothing else
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"

MODE=run
case "$1" in
--selftest) MODE=selftest ;;
"") ;;
*) echo "usage: $0 [--selftest]" >&2; exit 2 ;;
esac

O=; AS=; LDD=; LIBC=; V2=; CMD=; INC=; BIN=; LDIS=
if [ "$MODE" = run ]; then
	. "$(dirname "$0")/donor.sh"
	B="${C900_TC_BUILD:-$H/host/build}"	# the lane's build dir; see host/publish.sh
	O="$B/z8001"; AS="$B/as-z8001"; LDD="$B/ld-z8001"
	LIBC="$B/libc-z8001"; V2="${VAR:-800000020800}"
	# $LOUTDIS wins over the search, the way every other caller resolves it.
	LDIS="${LOUTDIS:-$(sh "$H/host/loutdis.sh")}"
	D="$Z8001_DONOR"; CMD="$D/cmd"; INC="$D/include"
	BIN="${ORIG_BIN:-$Z8001_DONOR/bin}"

	for p in "$O/cc0-z8001" "$O/cc1-z8001" "$O/cc2-z8001" "$AS" "$LDD"; do
		[ -x "$p" ] && continue
		echo "effdiff-linked.sh: $p is not built.  Run \`make' first," >&2
		echo "  or point \$C900_TC_BUILD at the build directory that has it." >&2
		exit 2
	done
	for f in "$LIBC/crt0.o" "$LIBC/libc-z8001.a"; do
		[ -f "$f" ] && continue
		echo "effdiff-linked.sh: no $f." >&2
		echo "  Run host/build-libc-z8001.sh: this harness links both sides," >&2
		echo "  so it needs crt0.o and the libc archive." >&2
		exit 2
	done
	if [ ! -d "$CMD" ]; then
		echo "effdiff-linked.sh: no cmd/ under \$Z8001_DONOR=$Z8001_DONOR" >&2
		exit 2
	fi
	# The baseline is the point of the harness; an absent or empty one is an
	# error here rather than an empty comparison reported later as clean.
	if [ ! -d "$BIN" ]; then
		echo "effdiff-linked.sh: no original-binary directory to compare against." >&2
		echo "  ORIG_BIN=$BIN is not a directory." >&2
		echo "  Set ORIG_BIN to the extracted 1985 MWC-compiled binaries:" >&2
		echo "     ORIG_BIN=/path/to/original/bin $0" >&2
		exit 2
	fi
	n=$(find "$BIN" -maxdepth 1 -type f | wc -l)
	if [ "$n" -eq 0 ]; then
		echo "effdiff-linked.sh: ORIG_BIN=$BIN holds no files." >&2
		echo "  It must contain the original MWC-compiled binaries, named as" >&2
		echo "  the commands are (cat, ls, wc, ...)." >&2
		exit 2
	fi
fi

python3 - "$MODE" "$O" "$AS" "$LDD" "$LIBC" "$V2" "$CMD" "$INC" "$BIN" "$LDIS" <<'PY'
import subprocess,sys,os,glob,tempfile,copy
MODE,O,AS,LD,LIBC,V2,CMD,INC,BIN,LDIS=sys.argv[1:11]

MAXDIST  =int(os.environ.get("EFFDIFF_MAXDIST","2"))
MINMATCH =int(os.environ.get("EFFDIFF_MIN_MATCH","40"))
MINLINKED=int(os.environ.get("EFFDIFF_MIN_LINKED","5"))

def sh(c): return subprocess.run(c,shell=True,capture_output=True,text=True)

def funcs(p):
    """loutdis -funcs, parsed.  Empty means unreadable or textless, and the
    caller distinguishes that from a file that is simply absent."""
    out=[]
    for ln in sh(f"{LDIS} -funcs {p}").stdout.splitlines():
        ln=ln.strip()
        if len(ln)>=8 and all(c in '0123456789abcdef' for c in ln[:8]):
            f=ln.split(); ops={}
            # addr bytes insns far call ...opcode:count
            for t in f[5:]:
                if ':' in t: k,v=t.split(':'); ops[k]=int(v)
            out.append({'bytes':int(f[1]),'insns':int(f[2]),'ops':ops})
    return out

def dist(a,b):
    """Opcode-profile distance plus instruction-count distance.  loutdis reports
    only the top opcodes, so this is a resemblance, never an identity."""
    ks=set(a['ops'])|set(b['ops'])
    return sum(abs(a['ops'].get(k,0)-b['ops'].get(k,0)) for k in ks)+abs(a['insns']-b['insns'])

def match(cf,of,maxdist=None):
    """Greedy nearest-signature pairing of linked-cc2 functions to original
    functions.  Returns (pairs, unmatched-count).  The sweep and the self-test
    both go through this, so the control exercises the code the summary is
    computed from."""
    if maxdist is None: maxdist=MAXDIST
    used=set(); pairs=[]; unmatched=0
    for c in cf:
        best=-1; bd=None
        for j,o in enumerate(of):
            if j in used: continue
            d=dist(c,o)
            if bd is None or d<bd: bd=d; best=j
        if best>=0 and bd<=maxdist:
            used.add(best); pairs.append((c,of[best]))
        else:
            unmatched+=1
    return pairs,unmatched

def score(pairs):
    cb=sum(c['bytes'] for c,_ in pairs); ob=sum(o['bytes'] for _,o in pairs)
    worse=sum(1 for c,o in pairs if c['bytes']>o['bytes'])
    better=sum(1 for c,o in pairs if c['bytes']<o['bytes'])
    return cb,ob,worse,better

def bloat(fs,nbytes,ninsns,op):
    """A regression shaped like a lost peephole: the same work in more
    instructions and more bytes.  Perturbs a KNOWN function set for the control."""
    out=copy.deepcopy(fs)
    for f in out:
        f['bytes']+=nbytes; f['insns']+=ninsns
        f['ops'][op]=f['ops'].get(op,0)+ninsns
    return out

def synth():
    """A function set with the shape loutdis produces, for the dependency-free
    leg of the control."""
    out=[]
    for i in range(24):
        out.append({'bytes':40+6*i,'insns':14+2*i,
                    'ops':{'LDL':3+i%5,'JR':2+i%3,'INC':2,'CALL':1+i%2}})
    return out

def selftest(real=None):
    """Negative control.  A harness that has never been shown to FAIL is not an
    instrument.  Asserts that identical inputs report no difference, that a
    perturbed input reports the difference, and reports the perturbation size at
    which pairing stops seeing the function at all -- the blind spot the header
    describes, measured rather than asserted."""
    ok=True
    legs=[("synthesised",synth())]
    if real: legs.append(real)
    for name,base in legs:
        n=len(base)
        # Positive leg: a function set against itself must pair completely and
        # report a zero delta.  A control that cannot report SAME is no control.
        pairs,un=match(base,base)
        cb,ob,worse,better=score(pairs)
        if len(pairs)!=n or un or cb!=ob or worse or better:
            print(f"SELF-TEST FAILED [{name}]: identical input did not compare equal "
                  f"(paired {len(pairs)}/{n}, unmatched {un}, delta {cb-ob:+d}, worse {worse})")
            ok=False
            continue
        # Negative leg: same functions, each 6 bytes and 1 instruction fatter --
        # a divergence the threshold still pairs through.  The pairing must
        # survive it and the summary must SAY the functions grew.
        pb=bloat(base,6,1,'LDIRB')
        pairs,un=match(pb,base)
        cb,ob,worse,better=score(pairs)
        if len(pairs)!=n or worse!=n or cb-ob!=6*n:
            print(f"SELF-TEST FAILED [{name}]: a {6*n}B regression over {n} functions "
                  f"was not reported (paired {len(pairs)}/{n}, worse {worse}, delta {cb-ob:+d})")
            ok=False
            continue
        # Blind spot, measured: grow the perturbation until pairing loses the
        # functions, and print where that is.
        lost=None
        for k in range(1,64):
            p2=bloat(base,4*k,k,'LDIRB')
            pairs2,un2=match(p2,base)
            if len(pairs2)<n: lost=(k,4*k,len(pairs2)); break
        print(f"self-test [{name}]: {n} functions; identical compares equal; "
              f"+{6*n}B over {n} functions is reported")
        if lost:
            k,b,still=lost
            print(f"  goes blind at +{k} insns/+{b}B per function: pairing keeps "
                  f"{still}/{n} and loses the rest from the comparison entirely")
        else:
            print(f"  pairing never lost a function up to +63 insns/+252B (threshold {MAXDIST})")
    return ok

if MODE=="selftest":
    sys.exit(0 if selftest() else 1)

# ---------------------------------------------------------------------------
T=tempfile.mkdtemp()

def compile_c(src,d,tag):
    """cc0 -> cc1 -> cc2.  Returns the object path, or (None, reason)."""
    if sh(f"{O}/cc0-z8001 {V2} {src} {d}/z0 -I{INC}").returncode:
        return None,"cc0 rejected the source"
    if sh(f"{O}/cc1-z8001 {V2} {d}/z0 {d}/z1").returncode:
        return None,"cc1 failed"
    if sh(f"{O}/cc2-z8001 0010 {d}/z1 {d}/{tag}.o {d}/scr 0").returncode:
        return None,"cc2 failed"
    return f"{d}/{tag}.o",None

def link(obj,out,extra):
    r=sh(f"{LD} -R 0x100 -o {out} {LIBC}/crt0.o {obj} {extra} {LIBC}/libc-z8001.a")
    if r.returncode or not os.path.isfile(out):
        return (r.stderr or r.stdout).strip().splitlines()
    return None

# SS probe.  Link a trivial program of our own two ways -- with crt0 alone, and
# with a stub object defining SS -- and adopt whichever resolves.  Which one it
# is depends on the crt0 this build has, and getting it wrong fails EVERY link.
pd=tempfile.mkdtemp()
open(f"{pd}/probe.c","w").write("main(){return 0;}\n")
pobj,why=compile_c(f"{pd}/probe.c",pd,"probe")
if pobj is None:
    print(f"effdiff-linked.sh: the SS link probe would not compile: {why}")
    print("  A trivial `main(){return 0;}' does not survive cc0/cc1/cc2, so no")
    print("  program in the corpus will either.  Nothing was compared.")
    sys.exit(1)
sh(f"printf '\\t.globl\\tSS\\nSS = 0\\n' > {T}/ss.s && {AS} -o {T}/ss.o {T}/ss.s")
SSOBJ=None; probe_note=None
e_plain=link(pobj,f"{pd}/plain.out","")
if e_plain is None:
    SSOBJ=""; probe_note="crt0.o defines SS; no stub object is linked in"
elif os.path.isfile(f"{T}/ss.o"):
    e_stub=link(pobj,f"{pd}/stub.out",f"{T}/ss.o")
    if e_stub is None:
        SSOBJ=f"{T}/ss.o"; probe_note="crt0.o leaves SS undefined; a stub object supplies it"
if SSOBJ is None:
    print("effdiff-linked.sh: no program links, so nothing can be compared.")
    print("  A trivial `main(){return 0;}' fails to link both with and without")
    print("  the SS stub object.  ld said, without the stub:")
    for ln in (e_plain or ["(no output)"])[:6]: print(f"    {ln}")
    print("  Rebuild crt0.o and libc-z8001.a (host/build-libc-z8001.sh) against")
    print("  the compiler in $C900_TC_BUILD; they must be the same generation.")
    sys.exit(1)

# The sweep.
skips={}
def skip(why): skips[why]=skips.get(why,0)+1

srcs=sorted(glob.glob(CMD+"/*.c"))
have_orig=0; attempted=0; linked=0
nfun_cc2=nfun_orig=0
matched=0; unmatched=0
mtot_c=mtot_o=0; wins=ties=losses=0; lossmag=[]
ldfail=[]
control_real=None

for src in srcs:
    u=os.path.basename(src)[:-2]
    op=f"{BIN}/{u}"
    if not os.path.isfile(op) or not os.access(op,os.R_OK):
        skip("no readable original binary to compare against"); continue
    have_orig+=1
    raw=open(src,'rb').read()
    if sum(1 for b in raw if b not in b'\t\n\r' and not(32<=b<127))>64:
        skip("source is not C text"); continue
    attempted+=1
    d=tempfile.mkdtemp()
    obj,why=compile_c(src,d,"o")
    if obj is None: skip(why); continue
    err=link(obj,f"{d}/a.out",SSOBJ)
    if err is not None:
        skip("ld could not link the program")
        if len(ldfail)<8: ldfail.append((u,err[0] if err else "(no output)"))
        continue
    linked+=1
    cf=funcs(f"{d}/a.out"); of=funcs(op)
    if not cf:
        skip("loutdis found no function in the linked program"); continue
    if not of:
        skip("loutdis could not read the original binary"); continue
    nfun_cc2+=len(cf); nfun_orig+=len(of)
    if control_real is None: control_real=(f"original {u}",of)
    pairs,un=match(cf,of)
    matched+=len(pairs); unmatched+=un
    cb,ob,w,bt=score(pairs)
    mtot_c+=cb; mtot_o+=ob; wins+=bt; losses+=w; ties+=len(pairs)-bt-w
    for c,o in pairs:
        if c['bytes']>o['bytes']: lossmag.append((u,c['bytes']-o['bytes']))

# The control runs on every sweep, not when somebody remembers it, and it runs
# on a REAL disassembled function set when the sweep read one.
print("== self-test (negative control) ==")
ctl=selftest(control_real)
print()

print("== coverage ==")
print(f"  cmd sources seen              {len(srcs)}")
print(f"  with a readable original      {have_orig}")
print(f"  link attempted                {attempted}")
print(f"  linked ok                     {linked}")
print(f"  SS resolution                 {probe_note}")
print(f"  linked cc2 functions read     {nfun_cc2}")
print(f"  original functions read       {nfun_orig}")
print(f"  PAIRED with an original       {matched}")
print(f"  cc2 functions NOT compared    {unmatched}  (no signature within {MAXDIST})")
if skips:
    print("  sources skipped:")
    for why,n in sorted(skips.items(),key=lambda x:-x[1]):
        print(f"    {n:5d}  {why}")
if ldfail:
    print("  first link failures:")
    for u,m in ldfail: print(f"    {u}: {m}")
print()

fail=[]
if not ctl:
    fail.append("the negative control did not report a difference it was given")
if linked==0:
    fail.append(f"no program linked, so nothing was compared "
                f"({attempted} attempted, {have_orig} had an original)")
elif linked<MINLINKED:
    fail.append(f"only {linked} programs linked, below the minimum of "
                f"{MINLINKED} (EFFDIFF_MIN_LINKED)")
if matched==0:
    fail.append("no function was paired with an original, so nothing was compared")
elif matched<MINMATCH:
    fail.append(f"paired functions: {matched}, below the minimum of "
                f"{MINMATCH} (EFFDIFF_MIN_MATCH); a sweep this thin cannot "
                f"support a conclusion either way")
if fail:
    print("== REFUSING TO SUMMARISE ==")
    for f in fail: print(f"  {f}")
    print("  A run that compared nothing is not a run that found nothing.")
    sys.exit(1)

print("== cc2 vs original, on paired functions only ==")
print(f"  paired={matched} functions   cc2={mtot_c}B  orig={mtot_o}B  "
      f"delta={mtot_c-mtot_o:+d}B ({100.0*(mtot_c-mtot_o)/mtot_o:+.1f}%)")
print(f"  cc2 smaller={wins}  same={ties}  cc2 larger={losses}")
if lossmag:
    print(f"  larger by {sum(m for _,m in lossmag)}B in total; worst:",
          ", ".join(f"{u}+{m}B" for u,m in sorted(lossmag,key=lambda x:-x[1])[:8]))
print(f"  covered {matched} of {nfun_cc2} linked cc2 functions "
      f"({100.0*matched/nfun_cc2:.0f}%); the rest are above as not compared.")
print("  The pairing count is itself a measurement: it falls when codegen stops")
print("  resembling the original, which is the same event as a regression.")
PY
