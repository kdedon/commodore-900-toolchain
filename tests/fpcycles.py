#!/usr/bin/env python3
# fpcycles.py N2 LOUTDIS TABLE PROG  ->  "CLOCKS INSTRUCTIONS SOFTFLOATCALLS"
#
# Clock cycles of the code PROG runs between returning from mark1() and
# calling mark2(), summed from the Z8001 segmented-mode figures in TABLE over
# the executed path.  The path is read from the runner one instruction at a
# time: CSIM_BREAK_INSNS=k reports the k-th instruction's PC and the
# registers after it.  Straight-line code is followed through the listing;
# the runner is asked again only after a branch, call or return, and before
# an instruction whose time depends on register values.
import os, re, subprocess, sys

n2, loutdis, table, prog = sys.argv[1:5]
# The stock board's DRAM answers in the CPU's 3-clock cycle, with no wait
# states.  The boot ROM sets the refresh rate to 15: a 3-clock refresh cycle
# every 60 clocks.
REFRESH = 60

cyc = {}
for ln in open(table):
    f = ln.split()
    if f and not f[0].startswith("#"):
        cyc[(f[0], f[1])] = [int(x) for x in f[2:]]

lst = {}
for ln in subprocess.run([loutdis, prog, "-v"], capture_output=True, text=True).stdout.splitlines():
    m = re.match(r"\s+([0-9a-f]{4}):\s+(\S+)\s*(.*)", ln)
    if m:
        lst[int(m.group(1), 16)] = (m.group(2), [o for o in m.group(3).split(",") if o])
offs = sorted(lst)
size = {a: b - a for a, b in zip(offs, offs[1:])}
syms = {}
for ln in subprocess.run([loutdis, prog, "-syms"], capture_output=True, text=True).stdout.splitlines():
    f = ln.split()
    if len(f) == 3:
        syms[f[2]] = int(f[0], 16) >> 8 & 0xFF0000 | int(f[0], 16) & 0xFFFF
text = open(prog, "rb").read()[48:]

def word(a):
    return text[a] << 8 | text[a + 1]

probes = {}
def probe(k):
    if k not in probes:
        e = dict(os.environ, CSIM_BREAK_INSNS=str(k), N2QUIET="1")
        r = subprocess.run([n2, "-runexec", prog], env=e, capture_output=True, text=True).stderr
        m = re.search(r"\[brk\] insns=\d+ pc=([0-9A-F]{2}):([0-9A-F]{4}).*\n\s+R:((?: [0-9A-F]{4}){16})", r)
        if not m:
            sys.exit("fpcycles: no instruction %d in %s" % (k, prog))
        probes[k] = (int(m.group(1), 16) << 16 | int(m.group(2), 16), [int(x, 16) for x in m.group(3).split()])
    return probes[k]

def mode(o):
    if re.fullmatch(r"R[RQHL]?\d+", o): return "R"
    if o.startswith("#"): return "IM"
    if o.startswith("@"): return "IR"
    if re.fullmatch(r"0x[0-9A-F]{2}:0x[0-9A-F]{4}", o): return "DA"
    if re.fullmatch(r"0x[0-9A-F]{2}:0x[0-9A-F]{4}\(R\d+\)", o): return "X"
    if re.fullmatch(r"0x[0-9A-F]{4}\(R\d+\)", o): return "BA"
    if re.fullmatch(r"R\d+\(R\d+\)", o): return "BX"
    return "R"

def popcount16(v):
    if v & 0x8000:
        v = -v & 0xFFFF
    return bin(v).count("1")

CTL = {"JR", "JP", "CALR", "CALL", "RET", "DJNZ", "DBJNZ", "SC"}

def cost(pc, mn, ops, regs, taken):
    w0, w1 = word(pc), word(pc + 2)
    ms = [mode(o) for o in ops]
    if mn in ("PUSH", "PUSHL"):
        ms = ms[1:]                     # the stack pointer is not the mode
    elif mn in ("POP", "POPL"):
        ms = ms[:1]
    if mn in ("JR", "CALR", "DJNZ", "DBJNZ"):
        md = "RA"
    else:
        md = next((m for m in ms if m not in ("R", "IM")), "IM" if "IM" in ms else "R")
    if not ops or mn in ("SETFLG", "RESFLG", "COMFLG"):
        md = "IR" if mn in ("MULTL", "DIVL", "MULT", "DIV") else "-"
    if md == "IM" and re.fullmatch(r"(BIT|SET|RES|INC|DEC)B?", mn):
        md = "R"
    lng = md in ("DA", "X") and word(pc + (4 if mn == "LDM" else 2)) & 0x8000 != 0
    if mn in ("LD", "LDB", "LDL") and md in ("IR", "DA", "X", "BA", "BX") and ms[0] == md:
        mn += "<"
    if mn == "RET":
        return 13 if taken else 7
    if mn == "JP" and md == "IR":
        return 15 if taken else 7
    if mn == "LDB" and md == "IM":
        return 5 if w0 >> 12 == 0xC else 7
    if mn in ("RLC", "RRC", "RL", "RR", "RLCB", "RRCB", "RLB", "RRB"):
        return 7 if w0 & 2 else 6
    if re.fullmatch(r"S[LR][LA][BL]?", mn):
        return 13 + 3 * abs(w1 - 0x10000 if w1 & 0x8000 else w1)
    if re.fullmatch(r"SD[LA][BL]?", mn):
        c = regs[(w1 >> 8) & 15]
        return 15 + 3 * abs(c - 0x10000 if c & 0x8000 else c)
    if mn == "LDM":
        n = (w1 & 15) + 1
        return {"IR": 11, "DA": 17 if lng else 15, "X": 18 if lng else 15}[md] + 3 * n
    if mn in ("MULT", "DIV"):
        add = {"R": 0, "IM": 0, "IR": 0, "DA": 4 if lng else 2, "X": 5 if lng else 2}[md]
        zero = md == "IM" and w1 == 0 or md == "R" and regs[(w0 >> 4) & 15] == 0
        return (18 if zero else 70) + add if mn == "MULT" else (13 if zero else 107) + add
    if mn in ("MULTL", "DIVL"):
        d = w0 & 0x0C
        zero = md == "R" and regs[(w0 >> 4) & 14] == 0 and regs[((w0 >> 4) & 14) + 1] == 0
        if mn == "DIVL":
            return 30 if zero else 744 + {"R": 0, "IM": 0, "IR": 0, "DA": 3 if lng else 2, "X": 3 if lng else 2}[md]
        add = {"R": 0, "IM": 0, "IR": 0, "DA": 4 if lng else 2, "X": 5 if lng else 2}[md]
        return (30 if zero else 282 + 7 * popcount16(regs[d + 3])) + add
    k = (mn, md)
    if k not in cyc and mn.rstrip("<").endswith("B"):
        k = (mn.rstrip("<")[:-1] + ("<" if mn.endswith("<") else ""), md)
    if k not in cyc:
        sys.exit("fpcycles: no timing for %s %s at %04X in %s" % (mn, md, pc, prog))
    c = cyc[k]
    return c[1] if lng else c[0]

m1, m2 = syms["mark1_"], syms["mark2_"]
soft = {syms[s] for s in ("dladd", "dlsub", "dlmul", "dldiv", "dradd", "drsub", "drmul", "drdiv") if s in syms}
calls = 0
k, (pc, _) = 1, probe(1)
inside, total, n = False, 0, 0
while True:
    if pc >> 16 != m1 >> 16:            # the runner's own start-up code
        k, pc = k + 1, probe(k + 1)[0]
        continue
    mn, ops = lst[pc & 0xFFFF]
    regs = probe(k - 1)[1] if inside and re.fullmatch(r"SD[LA][BL]?|MULTL?|DIVL?", mn) else None
    sz = size[pc & 0xFFFF]
    npc = probe(k + 1)[0] if mn in CTL else pc + sz
    if npc == m2 and inside:
        break
    if inside:
        total += cost(pc & 0xFFFF, mn, ops, regs, npc != pc + sz)
        n += 1
        calls += pc in soft
    if mn == "RET" and m1 <= pc < m2:
        inside = True
    k, pc = k + 1, npc
print(total + total * 3 // (REFRESH - 3), n, calls)
