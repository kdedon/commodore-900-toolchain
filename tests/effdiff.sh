#!/bin/sh
# effdiff.sh -- userland EFFICIENCY comparison by DISASSEMBLY (no sim).  For every
# cmd/*.c that has an exported original binary, disassemble cc2's object and compare
# per-function byte sizes to the ORIGINAL MWC-compiled binary.  The original binaries
# are the only meaningful efficiency baseline: comparing our backend to another of our
# own encoders says nothing about whether we are fast enough for the machine.  Uses
# loutdis on both sides; the sim is never invoked.
#
# The originals are STRIPPED, so there is no name to match on.  Functions are split out
# of the text by their FP-setup prologue and paired by opcode-profile signature: each
# cc2 function takes the unused original whose (top-opcode profile, instruction count)
# is nearest, and the pair is ACCEPTED ONLY if that distance is within $EFFDIFF_MAXDIST.
# That threshold is the whole character of this instrument, and its blind spots below
# are consequences of it.
#
# WHAT THIS HARNESS CANNOT SEE
#
#   * A defect that changes a function's shape by more than the match threshold.  The
#     matcher pairs on SIMILARITY, so a function our backend compiles badly enough stops
#     resembling its original and is dropped as unmatched rather than reported as worse.
#     A codegen defect large enough to matter is therefore the kind most likely to fall
#     out of the comparison.  This is why unmatched counts are reported as prominently
#     as matched ones: a rise in unmatched is itself the signal.  The self-test measures
#     the exact point where it goes blind and prints it every run.
#   * STRUCT COPY specifically.  Our inline word-at-a-time struct copy against the
#     original's LDIRB block moves both the instruction count and the opcode profile,
#     and the affected functions land beyond the threshold.  Deliberately perturbing
#     struct-copy codegen does not move the matched-function totals.  Read the unmatched
#     line, not the delta, for that class.
#   * Anything the pairing gets WRONG.  The signature is loutdis's top-four opcodes plus
#     an instruction count, which is not an identity: two same-sized leaf functions can
#     pair with each other's originals and both compare clean.  There is no name-level
#     confirmation available on a stripped binary.
#   * Addressing-mode cost that only linking resolves.  This compares an unlinked cc2
#     object against a fully linked original, so displacement widths and call forms
#     differ for reasons that are not codegen quality.  tests/effdiff-linked.sh links
#     both sides and is the accurate size comparison; this one is the fast sweep.
#   * Speed.  Bytes are the only axis here.  A smaller function is not a faster one.
#   * Anything not compiled: sources cc0/cc1/cc2 reject, and sources with no exported
#     original.  Both are counted in the coverage block rather than passed over.
#
# A run that compared nothing REFUSES.  Zero readable originals, zero matched functions,
# or fewer than $EFFDIFF_MIN_MATCH matches is an error naming what was missing, not a
# summary -- "no functions compared" must never read like "no differences found".
#
# Inputs, all external and none assumed:
#   $Z8001_DONOR   the userland corpus, cmd/ and include/       (tests/donor.sh)
#   $LOUTDIS       the l.out disassembler                       (host/loutdis.sh)
#   $ORIG_BIN      the original MWC-compiled binaries; defaults to $Z8001_DONOR/bin
#
# Usage:
#   sh tests/effdiff.sh              compare, after the self-test
#   sh tests/effdiff.sh --selftest   the self-test alone; needs python3 and nothing else
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"

MODE=run
case "$1" in
--selftest) MODE=selftest ;;
"") ;;
*) echo "usage: $0 [--selftest]" >&2; exit 2 ;;
esac

O=; VAR=; CMD=; INC=; BIN=; LD=
if [ "$MODE" = run ]; then
	. "$(dirname "$0")/donor.sh"
	B="${C900_TC_BUILD:-$H/host/build}"	# the lane's build dir; see host/publish.sh
	O="$B/z8001"; VAR="${VAR:-800000000800}"
	# $LOUTDIS wins over the search, the way every other caller resolves it.
	LD="${LOUTDIS:-$(sh "$H/host/loutdis.sh")}"
	CMD="$Z8001_DONOR/cmd"; INC="$Z8001_DONOR/include"
	BIN="${ORIG_BIN:-$Z8001_DONOR/bin}"

	for p in cc0-z8001 cc1-z8001 cc2-z8001; do
		[ -x "$O/$p" ] && continue
		echo "effdiff.sh: $O/$p is not built.  Run \`make' first," >&2
		echo "  or point \$C900_TC_BUILD at the build directory that has it." >&2
		exit 2
	done
	if [ ! -d "$CMD" ]; then
		echo "effdiff.sh: no cmd/ under \$Z8001_DONOR=$Z8001_DONOR" >&2
		exit 2
	fi
	# The baseline is the point of the harness; an absent or empty one is an
	# error here rather than an empty comparison reported later as clean.
	if [ ! -d "$BIN" ]; then
		echo "effdiff.sh: no original-binary directory to compare against." >&2
		echo "  ORIG_BIN=$BIN is not a directory." >&2
		echo "  Set ORIG_BIN to the extracted 1985 MWC-compiled binaries:" >&2
		echo "     ORIG_BIN=/path/to/original/bin $0" >&2
		exit 2
	fi
	n=$(find "$BIN" -maxdepth 1 -type f | wc -l)
	if [ "$n" -eq 0 ]; then
		echo "effdiff.sh: ORIG_BIN=$BIN holds no files." >&2
		echo "  It must contain the original MWC-compiled binaries, named as" >&2
		echo "  the commands are (cat, ls, wc, ...)." >&2
		exit 2
	fi
fi

python3 - "$MODE" "$O" "$VAR" "$CMD" "$INC" "$BIN" "$LD" <<'PY'
import subprocess,sys,os,glob,tempfile,copy
MODE,O,VAR,CMD,INC,BIN,LD=sys.argv[1:8]

MAXDIST =int(os.environ.get("EFFDIFF_MAXDIST","8"))
MINMATCH=int(os.environ.get("EFFDIFF_MIN_MATCH","25"))
MINBINS =int(os.environ.get("EFFDIFF_MIN_BINS","5"))

def sh(c): return subprocess.run(c,shell=True,capture_output=True,text=True)

def funcs(p):
    """loutdis -funcs, parsed.  Empty means unreadable or textless, and the
    caller distinguishes that from a file that is simply absent."""
    r=sh(f"{LD} -funcs {p}")
    out=[]
    for ln in r.stdout.splitlines():
        ln=ln.strip()
        if len(ln)>=8 and all(ch in '0123456789abcdef' for ch in ln[:8]):
            f=ln.split()
            # addr bytes insns far call ...opcode:count
            ops={}
            for tok in f[5:]:
                if ':' in tok:
                    k,v=tok.split(':'); ops[k]=int(v)
            out.append({'bytes':int(f[1]),'insns':int(f[2]),'ops':ops})
    return out

def dist(a,b):
    """Opcode-profile distance plus instruction-count distance.  loutdis reports
    only the top opcodes, so this is a resemblance, never an identity."""
    ks=set(a['ops'])|set(b['ops'])
    return sum(abs(a['ops'].get(k,0)-b['ops'].get(k,0)) for k in ks)+abs(a['insns']-b['insns'])

def match(cf,of,maxdist=None):
    """Greedy nearest-signature pairing of cc2 functions to original functions.
    Returns (pairs, unmatched-count).  Every caller -- the sweep and the
    self-test both -- goes through this, so the control exercises the code the
    summary is computed from."""
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
    """A struct-copy-shaped regression: the same work in more instructions and
    more bytes.  Used only to perturb a KNOWN function set for the control."""
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
        # Negative leg: same functions, each 6 bytes and 1 instruction fatter.
        # The pairing must survive it and the summary must SAY so.
        per=base
        pb=bloat(base,6,1,'LDIRB')
        pairs,un=match(pb,per)
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
            pairs2,un2=match(p2,per)
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
# The sweep.
skips={}
def skip(why): skips[why]=skips.get(why,0)+1

srcs=sorted(glob.glob(CMD+"/*.c"))
tools=compiled=0
bins_named=bins_present=bins_readable=0
nfun_cc2=nfun_orig=0; tot_c=0
matched=0; unmatched_no_bin=0; unmatched_no_cand=0
tot_c_m=tot_o_m=0; worse=better=0
losses=[]
control_real=None

for src in srcs:
    u=os.path.basename(src)[:-2]
    raw=open(src,'rb').read()
    if sum(1 for b in raw if b not in b'\t\n\r' and not(32<=b<127))>64:
        skip("source is not C text"); continue
    d=tempfile.mkdtemp()
    if sh(f"{O}/cc0-z8001 {VAR} {src} {d}/z0 -I{INC}").returncode:
        skip("cc0 rejected the source"); continue
    if sh(f"{O}/cc1-z8001 {VAR} {d}/z0 {d}/z1").returncode:
        skip("cc1 failed"); continue
    if sh(f"{O}/cc2-z8001 0010 {d}/z1 {d}/c.o {d}/scr 0").returncode:
        skip("cc2 failed"); continue
    compiled+=1
    cf=funcs(f"{d}/c.o")
    if not cf:
        skip("loutdis found no function in cc2's object"); continue
    tools+=1
    nfun_cc2+=len(cf); tot_c+=sum(c['bytes'] for c in cf)

    bins_named+=1
    op=f"{BIN}/{u}"
    if not os.path.isfile(op) or not os.access(op,os.R_OK):
        skip("no readable original binary"); unmatched_no_bin+=len(cf); continue
    bins_present+=1
    of=funcs(op)
    if not of:
        skip("loutdis could not read the original binary")
        unmatched_no_bin+=len(cf); continue
    bins_readable+=1
    nfun_orig+=len(of)
    if control_real is None: control_real=(f"original {u}",of)

    pairs,un=match(cf,of)
    matched+=len(pairs); unmatched_no_cand+=un
    cb,ob,w,bt=score(pairs)
    tot_c_m+=cb; tot_o_m+=ob; worse+=w; better+=bt
    for c,o in pairs:
        if c['bytes']>o['bytes']: losses.append((u,c['bytes']-o['bytes']))

# The control runs on every sweep, not when somebody remembers it, and it runs
# on a REAL disassembled function set when the sweep read one.
print("== self-test (negative control) ==")
ctl=selftest(control_real)
print()

print("== coverage ==")
print(f"  cmd sources seen              {len(srcs)}")
print(f"  compiled through cc0/cc1/cc2  {compiled}")
print(f"  contributing cc2 functions    {tools} tools, {nfun_cc2} functions, {tot_c}B")
print(f"  original binaries looked for  {bins_named}")
print(f"  original binaries present     {bins_present}")
print(f"  original binaries readable    {bins_readable}")
print(f"  original functions read       {nfun_orig}")
print(f"  matched pairs                 {matched}")
print(f"  cc2 functions NOT compared    {unmatched_no_bin+unmatched_no_cand}"
      f"  (no original binary: {unmatched_no_bin};"
      f" no signature within {MAXDIST}: {unmatched_no_cand})")
if skips:
    print("  sources and binaries skipped:")
    for why,n in sorted(skips.items(),key=lambda x:-x[1]):
        print(f"    {n:5d}  {why}")
print()

fail=[]
if not ctl:
    fail.append("the negative control did not report a difference it was given")
if bins_readable==0:
    fail.append(f"no original binary under ORIG_BIN={BIN} could be read "
                f"({bins_present} present of {bins_named} looked for)")
elif bins_readable<MINBINS:
    fail.append(f"only {bins_readable} original binaries readable, below the "
                f"minimum of {MINBINS} (EFFDIFF_MIN_BINS)")
if matched==0:
    fail.append("no function was matched, so nothing was compared")
elif matched<MINMATCH:
    fail.append(f"matched functions: {matched}, below the minimum of "
                f"{MINMATCH} (EFFDIFF_MIN_MATCH); a sweep this thin cannot "
                f"support a conclusion either way")
if fail:
    print("== REFUSING TO SUMMARISE ==")
    for f in fail: print(f"  {f}")
    print("  A run that compared nothing is not a run that found nothing.")
    sys.exit(1)

print("== cc2 vs original, on matched pairs only ==")
print(f"  matched={matched} functions   cc2={tot_c_m}B  orig={tot_o_m}B  "
      f"delta={tot_c_m-tot_o_m:+d}B ({100.0*(tot_c_m-tot_o_m)/tot_o_m:+.1f}%)")
print(f"  cc2 smaller={better}  same={matched-better-worse}  cc2 larger={worse}")
if losses:
    print(f"  larger by {sum(m for _,m in losses)}B in total; worst:",
          ", ".join(f"{u}+{m}B" for u,m in sorted(losses,key=lambda x:-x[1])[:8]))
print(f"  covered {matched} of {nfun_cc2} cc2 functions "
      f"({100.0*matched/nfun_cc2:.0f}%); the rest are listed above as not compared.")
PY
