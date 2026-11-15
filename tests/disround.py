#!/usr/bin/env python3
# disround.py AS LOUTDIS -- every instruction form as-z8001 writes, through
# loutdis and back.
#
# tools/loutdis/gentab.py --samples lists source lines for every form in the
# disassembly table, each with the words the table says it encodes to.  For
# each batch of them this checks
#   1. as-z8001 assembles every line to exactly those words, so the table
#      describes the assembler's encoding;
#   2. loutdis decodes one instruction per line, at the same offsets;
#   3. loutdis's text, respelled in the assembler's syntax, assembles to the
#      same bytes, so the text names every field the encoding has.
# The respelling is mechanical: case, `#' for `$', a segmented address
# 0xSS:0xOO (short) or 0xSS:0xOOOO (long) as SS|0xOO or the 32-bit constant,
# BA `0xDDDD(Rn)' as `rrn(0xDDDD)', a relative target as an offset from `.', the
# condition T as `un', and INDRB as the assembler's `indbr'.
import os, re, subprocess, sys, tempfile

AS, DIS = sys.argv[1:3]
H = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(H, "tools", "loutdis", "gentab.py")
HDR = 48            # l.out header; the text follows
BATCH = 2000

samples = []
for ln in subprocess.run([sys.executable, GEN, "--samples"], check=True,
                         capture_output=True, text=True).stdout.splitlines():
    f = ln.split("\t")
    samples.append(("\t".join(f[:-1]), bytes.fromhex(f[-1].replace(" ", ""))))

T = tempfile.mkdtemp()
fails = []

def assemble(lines, name):
    s = os.path.join(T, name + ".s")
    o = os.path.join(T, name + ".o")
    with open(s, "w") as fp:
        fp.write("\t.globl\tSS\nf:\n")
        for l in lines:
            fp.write("\t%s\n" % l)
    r = subprocess.run([AS, "-o", o, s], capture_output=True, text=True)
    if r.returncode or not os.path.exists(o):
        return None, r.stdout + r.stderr
    return open(o, "rb").read(), o

CC = {"F", "LT", "LE", "ULE", "OV", "MI", "EQ", "ULT", "T", "GE", "GT", "UGT",
      "NOV", "PL", "NE", "UGE"}
RELBR = {"JR", "CALR", "DJNZ", "DBJNZ"}
RELLD = {"LDR", "LDRB", "LDRL", "LDAR"}
REG = re.compile(r"@?R[HLRQ]?\d+$")

def addr(t):
    m = re.fullmatch(r"0x([0-9A-F]{2}):0x([0-9A-F]{2}|[0-9A-F]{4})(\(R\d+\))?", t)
    if not m:
        return None
    seg, off, x = m.groups()
    a = "0x%s|0x%s" % (seg, off) if len(off) == 2 else "0x%s00%s" % (seg, off)
    return a + (x.lower() if x else "")

def rel(t, pc):
    d = (int(t.split("0x")[-1], 16) - pc) & 0xFFFF
    return ".%+d" % (d - 0x10000 if d & 0x8000 else d)

def respell(pc, mn, ops):
    out = []
    for t in [o for o in ops.split(",") if o]:
        if mn in RELBR and t.startswith("0x") and ":" in t:
            out.append(rel(t, pc))
        elif mn in RELLD and re.fullmatch(r"0x[0-9A-F]{4}", t):
            out.append(rel(t, pc))
        elif t == "T":
            out.append("un")
        elif t in CC:
            out.append(t.lower())
        elif REG.match(t):
            out.append(t.lower())
        elif t.startswith("#"):
            out.append(t[1:] if mn == "SC" else "$" + t[1:])
        elif addr(t):
            out.append(addr(t))
        elif re.fullmatch(r"0x[0-9A-F]{4}\(R\d+\)", t):
            d, r = t[:-1].split("(R")
            out.append("rr%s(%s)" % (r, d))
        elif re.fullmatch(r"R\d+\(R\d+\)", t):
            b, x = t[1:-1].split("(R")
            out.append("rr%s(r%s)" % (b, x))
        else:
            out.append(t)            # ports, FLAGS and control registers, flags, VI/NVI
    mn = {"INDRB": "indbr"}.get(mn, mn.lower())
    return mn + ("\t" + ",".join(out) if out else "")

def report(what, i, extra=""):
    fails.append("  FAIL %s [%s]%s" % (what, samples[i][0], extra))

ninsn = 0
for b0 in range(0, len(samples), BATCH):
    batch = samples[b0:b0 + BATCH]
    want = b"".join(w for _, w in batch)
    obj, o = assemble([s for s, _ in batch], "a")
    if obj is None:
        fails.append("  FAIL as: %s" % o.strip().replace("\n", "\n       "))
        continue
    got = obj[HDR:HDR + len(want)]
    pos = 0
    for i, (s, w) in enumerate(batch):
        if got[pos:pos + len(w)] != w:
            report("encoding", b0 + i, ": as %s, table %s" % (got[pos:pos + len(w)].hex(), w.hex()))
            break
        pos += len(w)
    else:
        pass
    if got != want:
        continue
    lst = []
    for ln in subprocess.run([DIS, o, "-v"], capture_output=True, text=True).stdout.splitlines():
        m = re.match(r"\s+([0-9a-f]{4}):\s+(\S+)\s*(.*)$", ln)
        if m:
            lst.append((int(m.group(1), 16), m.group(2), m.group(3).strip()))
    pos, ok = 0, True
    for i, (s, w) in enumerate(batch):
        if i >= len(lst) or lst[i][0] != pos:
            report("decode", b0 + i, ": loutdis %s" % (lst[i] if i < len(lst) else "ended"))
            ok = False
            break
        pos += len(w)
    if not ok:
        continue
    text = [respell(pc, mn, ops) for pc, mn, ops in lst[:len(batch)]]
    obj2, o2 = assemble(text, "b")
    if obj2 is None:
        fails.append("  FAIL as (respelled): %s" % o2.strip().replace("\n", "\n       "))
        continue
    got2 = obj2[HDR:HDR + len(want)]
    pos = 0
    for i, (s, w) in enumerate(batch):
        if got2[pos:pos + len(w)] != w:
            report("round trip", b0 + i, ": %s %s -> %s -> %s" % (
                w.hex(), lst[i][1] + " " + lst[i][2], text[i], got2[pos:pos + len(w)].hex()))
        pos += len(w)
    ninsn += len(batch)

for f in fails[:40]:
    print(f)
print("=== disround: %d of %d instructions round-tripped, %d failed ===" % (
    ninsn, len(samples), len(fails)))
sys.exit(1 if fails else 0)
