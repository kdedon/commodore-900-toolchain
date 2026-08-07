#!/bin/sh
# cc3tab.sh -- assert that everything indexed by generated/opcode.h is in step.
#
# opcode.h is an INDEX, not a name list: its numbers are the ROW NUMBERS of four
# separate tables, and it is machine-generated (gotools/cmd/genz8001tab,
# from the simulator's decoder) while all four tables are kept by hand.  So a
# regeneration that renumbers one mnemonic and lands without them does not fail
# to build and does not mis-print a line -- cc2 encodes a DIFFERENT INSTRUCTION
# than cc1 asked for, and nothing anywhere says so.  That is what this checks,
# and it must land as one commit.
#
# The tables:
#   n2/z8001/optab.c  opinfo[]  the encoder: operand count, flags, opcode, style
#   n2/z8001/optab.c  opname[]  cc2's emit-time listing mnemonics
#   n3/z8001/icode.c  ins[]     cc3's copy -- cc3 links none of n2.  Load-bearing
#                               in a way a name table is not: cc3 READS the i1
#                               stream, which is self-delimiting only if the
#                               reader knows how many address fields each opcode
#                               takes, so one wrong operand count desynchronizes
#                               the reader and everything after it is garbage.
#   tools/isa/optab.c           the draft table, row-parallel to opcode.h
#
# and tools/isa/OPCODE_INVENTORY.md, the generator's OTHER output: it is written
# by the same run as opcode.h, so a mnemonic set that disagrees with opcode.h's
# means one of the two was hand-edited or committed alone.
#
# This gate does NOT need the simulator -- it compares committed artifacts only,
# so it runs in every checkout as part of `make check'.  What it cannot see is
# the decoder itself changing under a table that is internally consistent; that
# is `genz8001tab -check', which does need the simulator and so runs where that
# generator lives, not here.
#
# Usage: tests/cc3tab.sh
set -e
H=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$H" <<'EOF'
import re, sys
H = sys.argv[1]
bad = 0
def err(s):
    global bad
    bad += 1
    print("cc3tab: " + s)

# ---- generated/opcode.h: the index everything else is a row of ----
opc, nz = {}, None
for l in open(H + '/src/cc/generated/opcode.h'):
    m = re.match(r'#define\s+(\S+)\s+(\d+)\s*$', l)
    if not m:
        continue
    if m.group(1) == 'NZOPCODE':
        nz = int(m.group(2)); continue
    sym = m.group(1)
    if not re.match(r'^Z[A-Za-z0-9_]*$', sym):
        err("opcode.h: %r is not a C identifier -- it defines a DIFFERENT macro "
            "and every table checker skips the row" % sym)
        continue
    opc[int(m.group(2))] = sym
if nz != len(opc):
    err("opcode.h: NZOPCODE is %s but %d opcodes are defined" % (nz, len(opc)))
if set(opc) != set(range(len(opc))):
    err("opcode.h: indices are not 0..%d" % (len(opc) - 1))
PSEUDO = 0xC0
if len(opc) > PSEUDO:
    err("opcode.h: %d opcodes reach the pseudo-op base 0x%X" % (len(opc), PSEUDO))

# ---- the two n2 tables and the n3 copy ----
def rows(path, pat):
    out = {}
    for l in open(path):
        m = re.match(pat, l)
        if m:
            out[int(m.group(1))] = m.groups()[1:]
    return out

tab = rows(H + '/src/cc/n2/z8001/optab.c',
           r'\s*/\*\s*(\d+)\s+(\S+)\s*\*/\s*(\d+),\s*([^,]+),')
nam = rows(H + '/src/cc/n2/z8001/optab.c',
           r'\s*/\*\s*(\d+)\s+(\S+)\s*\*/\s*(?:"([^"]*)"|0),\s*$')
ins = rows(H + '/src/cc/n3/z8001/icode.c',
           r'\s*/\*\s*(\d+)\s+(\S+)\s*\*/\s*(?:"([^"]*)"|0),\s*(\d+),\s*([^,]+),')

if set(ins) != set(range(0xC4)):
    err("icode.c ins[] does not cover 0..0xC3 (%d rows)" % len(ins))
for i in opc:
    for what, t in (("optab.c opinfo[]", tab), ("optab.c opname[]", nam),
                    ("icode.c ins[]", ins)):
        if i not in t:
            err("opcode.h row %d (%s) has no %s row" % (i, opc[i], what))
        elif t[i][0] != opc[i]:
            err("row %d: opcode.h %s vs %s %s -- ROW ORDER DIVERGED"
                % (i, opc[i], what, t[i][0]))
for i, r in tab.items():
    if r[0] == '--':                    # unused slot: must be blank everywhere
        if (i in ins and ins[i][1]) or (i in nam and nam[i][1]):
            err("row %d is unused in opcode.h but named in a table" % i)
        continue
    if i not in ins:
        err("optab row %d (%s) has no icode.c row" % (i, r[0])); continue
    nm, naddr, flag = r[0], int(r[1]), r[2].strip()
    inm, txt, inaddr, iflag = ins[i][0], ins[i][1], int(ins[i][2]), ins[i][3].strip()
    if inm != nm:
        err("row %d: optab %s vs icode.c %s -- ROW ORDER DIVERGED" % (i, nm, inm))
    if inaddr != naddr:
        err("row %d (%s): operand count %d in optab, %d in icode.c" % (i, nm, naddr, inaddr))
    if iflag != flag:
        err("row %d (%s): flags %s in optab, %s in icode.c" % (i, nm, flag, iflag))
    if not txt:
        err("row %d (%s): icode.c has no mnemonic" % (i, nm))
    if i in nam and not nam[i][1]:
        err("row %d (%s): optab.c opname[] has no mnemonic" % (i, nm))
for i in ins:
    if ins[i][0] != '--' and i not in tab and ins[i][1]:
        err("row %d: icode.c names \"%s\" but optab has no such opcode" % (i, ins[i][1]))

# ---- the draft table: row-parallel to opcode.h, no index in the comment ----
draft = [m.group(1) for m in
         (re.search(r'\{[^}]*\},\s*/\*\s*(\S+)', l)
          for l in open(H + '/tools/isa/optab.c')) if m]
if len(draft) != len(opc):
    err("tools/isa/optab.c has %d rows, opcode.h has %d" % (len(draft), len(opc)))
for i, sym in enumerate(draft):
    if opc.get(i) != sym:
        err("tools/isa/optab.c row %d is %s, opcode.h row %d is %s"
            % (i, sym, i, opc.get(i))); break

# ---- the generator's other output: same run, so the same mnemonic set ----
def zsym(mn):
    return "Z" + re.sub(r'[^A-Z0-9_]', '', mn.upper().replace('/', '_'))
inv = set()
for l in open(H + '/tools/isa/OPCODE_INVENTORY.md'):
    m = re.match(r'\|\s*([A-Za-z][^|]*?)\s*\|\s*`', l)
    if m:
        inv.add(zsym(m.group(1)))
if inv != set(opc.values()):
    err("OPCODE_INVENTORY.md and opcode.h disagree: only in the inventory %s; "
        "only in opcode.h %s -- they are written by ONE genz8001tab run, so one "
        "of them was hand-edited or committed alone"
        % (sorted(inv - set(opc.values())), sorted(set(opc.values()) - inv)))

print("cc3tab: %d opcode rows checked across opcode.h, n2/z8001/optab.c "
      "(opinfo+opname), n3/z8001/icode.c, tools/isa/optab.c and the inventory, "
      "%d problem(s)" % (len(tab), bad))
sys.exit(1 if bad else 0)
EOF
