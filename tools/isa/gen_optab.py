#!/usr/bin/env python3
"""Generate a DRAFT n2/z8001 optab.c + OF_styles.h.

Inputs (all verified/authoritative):
  - src/cc/generated/opcode.h     : the Z* index order (rows must match it)
  - tools/isa/OPCODE_INVENTORY.md : operand shapes + base opcodes (from the sim decoder)
  - src/as/z8001/pst.c            : MWC's own base opcodes + S_* format classes

Each opcode.h row gets {OF_style, base, flags}. The OF_* style is assigned by the
operand-shape signature (the clustering in the analysis); the base is pst.c's
form-0 opcode where available (the authentic MWC value; the asm/coder ORs the
addressing hi-nibble), else the inventory's form-0 base. This is a DRAFT: the
codegen-critical families are assigned confidently; asm-only/privileged ops get
OF_ASMONLY and are flagged for review.
"""
import os, re, pathlib, collections

HERE = pathlib.Path(__file__).resolve().parent          # tools/isa
ROOT = HERE.parent.parent
GEN  = HERE                                             # the inventory lives here
CCGEN = ROOT / "src" / "cc" / "generated"                # opcode.h is compiled into cc2
PST  = ROOT / "src" / "as" / "z8001" / "pst.c"

# ---- read opcode.h order ----
zorder = []  # [(Zsym, MNEM)]
for L in (CCGEN / "opcode.h").read_text().splitlines():
    m = re.match(r'#define\s+(Z\w+)\s+\d+', L)
    if m and m.group(1) != "NZOPCODE":
        zorder.append(m.group(1))

# ---- inventory: MNEM -> {shapes}, {bases}; plus per-(mnem,shape) rows ----
shapes = collections.defaultdict(set)
bases  = collections.defaultdict(set)
inv_rows = []  # (mnem, shape, base, varmask, words)
row = re.compile(r'^\|\s*([A-Z0-9]+)\s*\|\s*`([^`]*)`\s*\|\s*`0x([0-9A-Fa-f]+)`'
                 r'\s*\|\s*`0x([0-9A-Fa-f]+)`\s*\|\s*(\d+)')
for L in (GEN / "OPCODE_INVENTORY.md").read_text().splitlines():
    m = row.match(L)
    if m:
        shapes[m.group(1)].add(m.group(2))
        bases[m.group(1)].add(int(m.group(3), 16))
        inv_rows.append((m.group(1), m.group(2), int(m.group(3), 16),
                         int(m.group(4), 16), int(m.group(5))))

# ---- pst.c: MNEM -> (base, S_fmt) ----
pst = {}
prow = re.compile(r'\{\s*[^,]+,\s*"([^"]+)"\s*,\s*(S_\w+)\s*,\s*([^,]+),\s*(E_\w+)\s*,\s*'
                  r'(0x[0-9A-Fa-f]+|\d+)\s*\}')
for m in prow.finditer(PST.read_text()):
    name, sfmt, mod, ec, val = m.groups()
    if not name.startswith('.') and sfmt != 'S_REG':
        pst[name.upper()] = (int(val, 0), sfmt)

def norm(sh):
    return re.sub(r'\b(F|LT|LE|ULE|OV|MI|EQ|ULT|T|GE|GT|UGT|NOV|PL|NE|UGE|PE|Z|C|PO|NZ|NC)\b',
                  'cc', sh)

def width(mn, S):
    # A Z8000 byte op is named <word-mnemonic>+'B' (SUBB, CPB, LDIRB, EXTSB...).  A
    # bare trailing 'B' on a base mnemonic (SUB, the 'B' of S-U-B) is NOT a width tag,
    # and a byte block op (LDIRB) has @RR pointer operands -- so the byte test must use
    # the name convention AND run before the @RR/long test.  (MNEMONICS is the full
    # inventory mnemonic set, built before this is called.)
    if mn.endswith('B') and mn[:-1] in MNEMONICS: return 'B'
    if any(s.startswith(('RR', '@RR')) or ',RR' in s for s in S) or mn.endswith('L'): return 'L'
    if any(s.startswith('RQ') for s in S): return 'Q'
    return 'W'

def classify(mn, S):
    """Return OF_* style. S = set of normalized operand shapes."""
    has = lambda *xs: all(x in S for x in xs)
    any_ = lambda *xs: any(x in S for x in xs)
    if S == {''}:                                   return 'OF_IMPL'
    if S == {'#i'}:                                 return 'OF_FLAG'   # SC/SETFLG/COMFLG/RESFLG
    if mn in ('HALT','IRET','NOP','DI','EI','MBIT','MREQ','MRES','MSET'): return 'OF_IMPL'
    if mn in ('JP',):                               return 'OF_JP'
    if mn in ('JR',):                               return 'OF_JR'
    if mn in ('CALR',):                             return 'OF_CALR'
    if mn in ('DJNZ',):                             return 'OF_DJNZ'
    if mn in ('CALL','LDPS'):                       return 'OF_CALL'
    if mn in ('RET',):                              return 'OF_RET'
    if mn in ('TCC','TCCB'):                        return 'OF_TCC'
    if mn in ('LDA','LDAR','LDR'):                  return 'OF_LDA'
    if mn in ('LDK',):                              return 'OF_LDK'
    if mn in ('LDM',):                              return 'OF_LDM'
    if mn in ('LDCTL',):                            return 'OF_CTL'
    if mn in ('EX','EXB'):                          return 'OF_EX'
    if mn.startswith('EXTS'):                       return 'OF_EXTS'
    if mn in ('PUSH','PUSHL'):                      return 'OF_PUSH'
    if mn in ('POP','POPL'):                        return 'OF_POP'
    if re.fullmatch(r'(RL|RR|RLC|RRC|DA|RLDB|RRDB)B?', mn): return 'OF_ROT'
    if re.fullmatch(r'(IN|OUT|SIN|SOUT)B?', mn):    return 'OF_IO'
    if mn.startswith('LD') and len(S) > 3:          return 'OF_LD'      # LD/LDB/LDL big cluster
    if mn in ('MULT','MULTL','DIV','DIVL'):         return 'OF_MUL'
    if re.fullmatch(r'(SLA|SLL|SRA|SRL)[BL]?', mn): return 'OF_SHIFT'   # static, R,#count
    if re.fullmatch(r'(SDA|SDL)[BL]?', mn):         return 'OF_SHIFTD'  # dynamic, R,R
    if mn in ('INC','DEC','INCB','DECB'):           return 'OF_INCDEC'
    if mn in ('BIT','RES','SET','BITB','RESB','SETB'): return 'OF_BIT'
    if mn in ('CP','CPB'):                          return 'OF_CP'
    if mn in ('ADC','SBC','ADCB','SBCB'):           return 'OF_DOP'     # carry arith, ALU forms
    # two-operand ALU (ADD/AND/OR/SUB/XOR + L/B) and CPL
    if has('R,R') or has('Rb,Rb') or has('RR,RR') or mn in ('ADDL','SUBL','CPL'):
        w = width(mn, S)
        return {'B':'OF_DOPB','L':'OF_DOPL'}.get(w, 'OF_DOP')
    # single-operand (CLR/COM/NEG/TEST/TSET + B, TESTL).  A SOP op's shapes are all
    # one-operand (R/Rb/RR/@R/addr/addr(R)/'') -- NONE has a comma -- which is what
    # separates it from the multi-operand block ops (@RR,@RR,R) that fall through to
    # OF_ASMONLY.  (The decoder reports the register-indirect @R form, so keying on a
    # bare '' missed CLR/COM once that shape appeared.)
    if any_('R','Rb','RR','@R','addr') and not any(',' in s for s in S):
        return 'OF_SOPB' if width(mn, S) == 'B' else 'OF_SOP'
    return 'OF_ASMONLY'

# OF_* styles in definition order, with a one-line role
STYLES = [
 ('OF_IMPL',   'no operands (HALT/IRET/NOP/DI/EI/MBIT...)'),
 ('OF_FLAG',   'immediate-only flag op (SC/SETFLG/COMFLG/RESFLG)'),
 ('OF_DOP',    'two-operand ALU, word (ADD/AND/OR/SUB/XOR/ADC/SBC); reg|imm|IR|DA|X'),
 ('OF_DOPB',   'two-operand ALU, byte'),
 ('OF_DOPL',   'two-operand ALU, long (ADDL/SUBL/CPL)'),
 ('OF_CP',     'compare (CP/CPB): ALU forms + addr,#i'),
 ('OF_SOP',    'single-operand, word (CLR/COM/NEG/TEST/TSET/TESTL)'),
 ('OF_SOPB',   'single-operand, byte'),
 ('OF_INCDEC', 'INC/DEC: 4-bit immediate count in opcode'),
 ('OF_MUL',    'MULT/DIV (RR/RQ pair/quad result)'),
 ('OF_SHIFT',  'static shift SLA/SLL/SRA/SRL, signed count word'),
 ('OF_SHIFTD', 'dynamic shift SDA/SDL, count in register'),
 ('OF_ROT',    'rotate RL/RR/RLC/RRC/RLDB/RRDB/DAB'),
 ('OF_EXTS',   'sign extend EXTS/EXTSB/EXTSL'),
 ('OF_BIT',    'bit BIT/SET/RES (static or dynamic bit#)'),
 ('OF_LD',     'load LD/LDB/LDL (all addressing forms)'),
 ('OF_LDA',    'load address/relative LDA/LDAR/LDR'),
 ('OF_LDK',    'load constant nibble LDK'),
 ('OF_LDM',    'load/store multiple LDM (built specially)'),
 ('OF_LDCTL_', 'control-register load LDCTL (privileged)'),
 ('OF_EX',     'exchange EX/EXB'),
 ('OF_PUSH',   'PUSH/PUSHL (@RR15)'),
 ('OF_POP',    'POP/POPL'),
 ('OF_JP',     'JP cc (DA/IR/X)'),
 ('OF_JR',     'JR cc, relative-8'),
 ('OF_CALR',   'CALR relative-12'),
 ('OF_DJNZ',   'DJNZ r, relative-7'),
 ('OF_CALL',   'CALL/LDPS (DA/IR/X)'),
 ('OF_RET',    'RET cc'),
 ('OF_TCC',    'test condition code TCC/TCCB'),
 ('OF_IO',     'IN/OUT/SIN/SOUT (privileged; not C-emitted)'),
 ('OF_ASMONLY','block/privileged/special, asm-only (CPDx, LDCTL, ...); review'),
]
# map OF_CTL -> OF_LDCTL_ name used in STYLES
STYLE_ALIAS = {'OF_CTL':'OF_LDCTL_'}

# ---- emit OF_styles.h ----
oh = ["/* OF_styles.h - n2/z8001 instruction-style codes for optab.c (DRAFT).",
      " * Analogous to the i8086 cc2mch.h OF_* set; asm.c dispatches on these to",
      " * fuse the optab base opcode with the packed a_mode address field. */",
      "#ifndef OF_STYLES_H",
      "#define OF_STYLES_H", ""]
for i, (name, role) in enumerate(STYLES):
    oh.append(f"#define\t{name:<11} {i}\t/* {role} */")
oh.append(f"\n#define\tNOF_STYLE\t{len(STYLES)}")
oh.append("\n#endif /* OF_STYLES_H */")
(CCGEN / "OF_styles.h").write_text("\n".join(oh) + "\n")

# ---- emit optab.c ----
def zsym(mn): return "Z" + re.sub(r'[ ./]', '', mn.upper())
def base_of(mn, S):
    if mn in pst: return pst[mn][0], 'pst'
    if bases.get(mn):  # inventory form-0 = the minimum base (hi-nibble 0x0/0x1)
        return min(bases[mn]), 'inv'
    return 0, 'none'

oc = ["/* optab.c - n2/z8001 opcode table (DRAFT, GENERATED by tools/gen_optab.py).",
      " * Row order MUST match generated/opcode.h. Each row: { style, base, flags }.",
      " * base = MWC pst.c form-0 opcode (authentic) where available, else the",
      " * decoder inventory form-0; asm.c ORs the addressing hi-nibble at emit.",
      " * style assigned by operand-shape cluster; OF_ASMONLY/OF_IO = review. */",
      '#include "opcode.h"',
      '#include "OF_styles.h"', "",
      "struct optab { short style; unsigned short base; short flags; } optab[] = {"]
# build MNEM lookup from Zsym
sym2mn = {}
MNEMONICS = set(list(shapes) + list(pst))   # full inventory mnemonic set (for width())
for mn in MNEMONICS:
    sym2mn[zsym(mn)] = mn
counts = collections.Counter()
review = []
for zs in zorder:
    mn = sym2mn.get(zs)
    if mn is None:
        oc.append(f"    {{ OF_ASMONLY, 0x0000, 0 }},\t/* {zs} (no inventory row) */")
        continue
    S = set(norm(s) for s in shapes.get(mn, {''}))
    style = classify(mn, S)
    style = STYLE_ALIAS.get(style, style)
    base, src = base_of(mn, S)
    flags = []
    w = width(mn, S)
    if w == 'B': flags.append('OP_BYTE')
    if w in ('L','Q'): flags.append('OP_DWORD')
    fl = '|'.join(flags) if flags else '0'
    counts[style] += 1
    if style in ('OF_ASMONLY','OF_IO'): review.append(mn)
    oc.append(f"    {{ {style:<11}, 0x{base:04X}, {fl:<16} }},\t"
              f"/* {zs:<10} {' '.join(sorted(S))[:30]} [{src}] */")
oc.append("};")
(GEN / "optab.c").write_text("\n".join(oc) + "\n")

print(f"opcode.h rows: {len(zorder)} | OF_* styles: {len(STYLES)}")
print("style distribution:")
for st, n in counts.most_common():
    print(f"  {st:<12} {n}")
print(f"asm-only/IO (review): {len(review)} -> {', '.join(sorted(review))}")
print(f"wrote {CCGEN/'OF_styles.h'}, {GEN/'optab.c'}")

# ---- emit Go data file for the round-trip driver (rt_z8001) ----
# Single source of truth: every inventory (mnem, shape) row with its verified
# per-shape base + varmask + word count + assigned OF_* style. The Go harness
# (rt_z8001 driveInventory) consumes this to round-trip every codegen row against
# the decoder -- no hand-typed bases.
#
# rt_z8001 is NOT in this repository: it decodes through the private z8000
# simulator, so it lives in c900oses/gotools with the other simulator-dependent
# Go instruments. The tree is resolved by NAME ($C900_GOTOOLS, else a search
# beside this checkout), and when it is not on this machine the C outputs above
# are still written and the Go row emission is SKIPPED OUT LOUD -- which is the
# whole difference between an absent optional consumer and a silent one.
def gotools_root():
    e = os.environ.get("C900_GOTOOLS")
    if e:
        if (pathlib.Path(e) / "cmd" / "rt_z8001").is_dir():
            return pathlib.Path(e)
        print(f"gen_optab: C900_GOTOOLS={e} has no cmd/rt_z8001")
        return None
    for d in (ROOT.parent.parent, ROOT.parent.parent / "c900oses",
              ROOT.parent.parent.parent, ROOT.parent.parent.parent / "c900oses"):
        if (d / "gotools" / "cmd" / "rt_z8001").is_dir():
            return d / "gotools"
    return None

gt = gotools_root()
GO = gt / "cmd" / "rt_z8001" / "inv_data.go" if gt else None
gd = ["// Code generated by tools/gen_optab.py from generated/OPCODE_INVENTORY.md",
      "// (itself generated from the verified z8000/cpu decoder). DO NOT EDIT.",
      "package main", "",
      "type invRow struct {",
      "\tMnem, Shape, Style string",
      "\tBase, Varmask      uint16",
      "\tWords              int",
      "}", "",
      "var invRows = []invRow{"]
for mn, shape, base, vm, words in inv_rows:
    S = set(norm(s) for s in shapes.get(mn, {''}))
    style = STYLE_ALIAS.get(classify(mn, S), classify(mn, S))
    sh = shape.replace('\\', '\\\\').replace('"', '\\"')
    gd.append(f'\t{{"{mn}", "{sh}", "{style}", 0x{base:04X}, 0x{vm:04X}, {words}}},')
gd.append("}")
if GO is None:
    print(f"SKIPPED inv_data.go ({len(inv_rows)} rows): no c900oses/gotools tree "
          f"here.  Set $C900_GOTOOLS to it; rt_z8001 needs the private simulator "
          f"and is not in this repository.")
else:
    GO.write_text("\n".join(gd) + "\n")
    print(f"wrote {GO} ({len(inv_rows)} rows)")
