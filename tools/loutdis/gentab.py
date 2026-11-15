#!/usr/bin/env python3
"""gentab.py -- generate z8ktab.h, the Z8001 disassembly table, from as-z8001.

    gentab.py               write tools/loutdis/z8ktab.h
    gentab.py --check       fail unless the committed z8ktab.h is what this writes
    gentab.py --samples     print assembler test lines: SOURCE <tab> EXPECTED HEX

The assembler is the encoding authority.  Opcodes, mnemonics, condition codes,
flag, interrupt and control-register names are read from its own tables,
src/as/z8001/pst.c and asmch.h.  How each instruction kind (S_*) lays its
operands out is in machine.c, which is code rather than a table; the functions
below transcribe it case by case, and the round trip in tests/disround.sh
assembles every form listed here and checks the assembler produces the bytes
predicted (--samples) and that loutdis's text assembles back to the same bytes.

Page numbers are those printed in the Z8000 CPU User's Reference Manual (Zilog,
1982), section 6.7.  The manual is a reference for the few things the assembler
does not decide: which register width an operand names, and the documented
forms the assembler cannot write (CPU, below).
"""
import pathlib, random, re, sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
AS = ROOT / "src" / "as" / "z8001"
OUT = HERE / "z8ktab.h"

# ---------------------------------------------------------------- inputs

def parse_defines(path):
    d = {}
    for m in re.finditer(r"^#define\s+(\w+)\s+(0x[0-9A-Fa-f]+|0[0-7]*|\d+)\b",
                         path.read_text(), re.M):
        v = m.group(2)
        d[m.group(1)] = int(v, 8) if v[0] == "0" and v[1:2].isdigit() else int(v, 0)
    return d

def parse_pst(path):
    row = re.compile(r'\{\s*[^,]+,\s*"([^"]+)"\s*,\s*(S_\w+)\s*,\s*([^,]+?)\s*,'
                     r'\s*(E_\w+)\s*,\s*(0x[0-9A-Fa-f]+|\d+)\s*\}')
    return [(m.group(1), m.group(2), m.group(3), int(m.group(5), 0))
            for m in row.finditer(path.read_text())]

DEF = parse_defines(AS / "asmch.h")
PST = parse_pst(AS / "pst.c")

def flagval(s):
    v = 0
    for t in s.split("|"):
        t = t.strip()
        v |= DEF[t] if t in DEF else (int(t, 0) if t[0].isdigit() else 0)
    return v

W = DEF["W"]                    # 0x0100: the word bit of a byte/word pair

def names(kind, prefer=()):
    """value -> name for one pst.c symbol kind, first spelling unless one in
    `prefer' is listed for that value."""
    out = {}
    for n, k, _, v in PST:
        if k != kind:
            continue
        if v not in out or n in prefer:
            out[v] = n
    return out

# Condition codes: pst.c spells each value one or more ways.  The table prints
# the manual's names (6.4, p.54); `un' (8, always) prints as T, and 0 (never),
# which the assembler cannot spell, as F.
CC = names("S_CC", prefer=("lt", "le", "ule", "ov", "mi", "eq", "ult", "ge",
                           "gt", "ugt", "nov", "pl", "ne", "uge"))
CC[8], CC[0] = "t", "f"
CCNAME = [CC[i].upper() for i in range(16)]
FLAGS = names("S_FLGN", prefer=("P",))                  # C Z S P, bits 7..4
INTS = names("S_IVN")                                   # NVI 1, VI 2
CTLR = {v: n for n, k, _, v in PST if k == "S_USER" and n.isupper()
        and n not in ("PSAP", "NSP")}                   # segmented names

# ---------------------------------------------------------------- operands

# Operand kinds; z8kdis.c renders each.  (word, shift, width) locate a field;
# word is counted as if every segmented address were short.
KINDS = ["R", "RB", "RR", "RQ", "IR", "IRR", "IM8", "IM16", "IM32", "NUM",
         "DA", "X", "BA", "BX", "PORT", "RA16", "RA8", "RA12", "RA7", "CC",
         "FLG", "INT", "SHIFT", "LIT"]
K = {k: i + 1 for i, k in enumerate(KINDS)}

class Op:
    def __init__(self, kind, word=0, shift=0, width=4, aux=0, w0bits=0):
        self.kind, self.word, self.shift, self.width, self.aux = kind, word, shift, width, aux
        self.w0bits = w0bits        # bits of w0 this operand owns

def fld(word, shift, width):
    return ((1 << width) - 1) << shift if word == 0 else 0

def reg(cls, nib, word=0):
    """a register field: nibble 0..3 (bits 15..12 .. 3..0) of `word'."""
    sh = 12 - 4 * nib
    return Op(cls, word, sh, 4, 0, fld(word, sh, 4))

def num(word, shift, width, add=0):        # #n, decimal
    return Op("NUM", word, shift, width, add, fld(word, shift, width))

def im(width, word):
    return Op({8: "IM8", 16: "IM16", 32: "IM32"}[width], word, 0, 16)

def da(word):
    return Op("DA", word)

def x(word, nib=2):
    sh = 12 - 4 * nib
    return Op("X", word, sh, 4, 0, fld(0, sh, 4))

def ba(word, nib=2):
    sh = 12 - 4 * nib
    return Op("BA", word, sh, 4, 0, fld(0, sh, 4))

def bx(nib=2):
    """base in w0, index in bits 11..8 of w1"""
    sh = 12 - 4 * nib
    return Op("BX", 1, 8, 4, sh, fld(0, sh, 4))

def cc(word, nib):
    sh = 12 - 4 * nib
    return Op("CC", word, sh, 4, 0, fld(word, sh, 4))

def lit(s):
    return Op("LIT", aux=s)

# ---------------------------------------------------------------- forms

class Form:
    def __init__(self, mn, val, ops, nw=1, nz=0, segw=0, m1=0, v1=0, alt="",
                 free=0, asm=True):
        # the manual's spelling where the assembler's differs
        self.asmn = mn.lower()
        mn = {"indbr": "indrb"}.get(self.asmn, mn)
        self.mn, self.val, self.ops, self.nw = mn.upper(), val, ops, nw
        self.sval = val
        self.nz, self.segw, self.m1, self.v1, self.alt = nz, segw, m1, v1, alt.upper()
        own = free
        for o in ops:
            own |= o.w0bits
        self.mask = 0xFFFF & ~own
        self.val = val & self.mask
        self.asm = asm             # False: the assembler cannot write it

FORMS = []

def add(*a, **k):
    FORMS.append(Form(*a, **k))

# Register classes the manual gives each instruction (6.7).  The assembler
# checks only alignment (S_2/S_4 in pst.c), so the width an operand names is
# taken from the mnemonic: a B suffix is a byte register, L a pair, and the
# multiply and divide destinations are a pair or a quadruple.
LONGOPS = {"addl", "subl", "cpl", "ldl", "pushl", "popl", "testl", "slal",
           "sral", "slll", "srll", "sdal", "sdll", "ldrl"}

def width(mn):
    if mn in ("extsb", "exts", "extsl"):
        return {"extsb": "R", "exts": "RR", "extsl": "RQ"}[mn]
    if mn in ("dab", "rldb", "rrdb", "dbjnz") or mn.endswith("b") and mn != "sub":
        return "RB"
    return "RR" if mn in LONGOPS else "R"

def dstw(mn, flag):
    """the destination register of S_RSRC/S_CP/S_LD: pst.c's S_2/S_4 say pair or quad."""
    f = flag & 3
    if f == DEF["S_4"]:
        return "RQ"
    if f == DEF["S_2"]:
        return "RR"
    return width(mn)

def srcw(mn, flag):
    """the source of S_RSRC: MULT/DIV take a word, MULTL/DIVL a pair."""
    if mn in ("mult", "div"):
        return "R"
    if mn in ("multl", "divl"):
        return "RR"
    return dstw(mn, flag)

# machine.c outxx(): the mode bits 15..14 are 10 for R, 00 for IR and IM, 01
# for DA and X; the register goes to bits 7..4 under UP4, else 3..0.  IM and
# DA leave the field 0, which is what tells them from IR and X.  An immediate
# follows as a word, a replicated byte (W clear) or, under LONG, two words; an
# address follows as one segmented word (short) or two (long, bit 15 set).
R_, IR_, IM_, DA_, X_ = "R", "IR", "IM", "DA", "X"

def outxx(mn, op, modes, cls, rnib, other, imw=16, srcpos=1, nwbase=1):
    """the forms outxx(op, operand, flags) emits.  `other' are the operands
    already in the first word, `srcpos' is where the outxx operand appears in
    the source text."""
    sh = 12 - 4 * rnib
    for m in modes:
        ops = list(other)
        if m == R_:
            o = reg(cls, rnib)
            ops.insert(srcpos, o)
            add(mn, op | 0x8000, ops, nw=nwbase)
        elif m == IR_:
            ops.insert(srcpos, reg(cls if cls.startswith("IR") else "IR", rnib))
            add(mn, op, ops, nw=nwbase, nz=1 << sh)
        elif m == IM_:
            n = {8: 1, 16: 1, 32: 2}[imw]
            ops.insert(srcpos, im(imw, nwbase))
            add(mn, op, ops, nw=nwbase + n)
        elif m == DA_:
            ops.insert(srcpos, da(nwbase))
            add(mn, op | 0x4000, ops, nw=nwbase + 1,
                segw=nwbase)
        elif m == X_:
            ops.insert(srcpos, x(nwbase, rnib))
            add(mn, op | 0x4000, ops, nw=nwbase + 1,
                segw=nwbase, nz=1 << sh)

ALLMEM = (R_, IR_, DA_, X_)

def immw(op, flag):
    if flag & DEF["LONG"]:
        return 32
    return 16 if op & W else 8

def build():
    for name, kind, flagtxt, op in PST:
        flag = flagval(flagtxt)
        mn = name
        if kind in ("S_USER", "S_REG", "S_CC", "S_IVN", "S_FLGN", "S_BYTE",
                    "S_WORD", "S_LONG", "S_ASCII", "S_BLK", "S_PAGE", "S_TITLE",
                    "S_GLOBL", "S_EVEN", "S_ODD", "S_COMM", "S_SEGM"):
            continue
        if name in ("sys",):        # the same opcode as sc
            continue
        fn = KIND.get(kind)
        if fn is None:
            sys.exit("gentab: no encoding for %s (%s) -- machine.c grew a kind" % (name, kind))
        fn(mn, op, flag)

KIND = {}
def kind(*ks):
    def deco(f):
        for k in ks:
            KIND[k] = f
        return f
    return deco

# S_HALT: outaw(op) -- halt, nop, iret, mbit, mres, mset.
@kind("S_HALT")
def k_halt(mn, op, flag):
    add(mn, op, [])

# S_R: outxx(op, dst, ROK|UP4|flag) -- dab, exts, extsb, extsl.
@kind("S_R")
def k_r(mn, op, flag):
    add(mn, op | 0x8000, [reg(width(mn), 2)])

# S_MREQ: outaw(op | dst<<4) -- MREQ Rd, R0 included (p.137).
@kind("S_MREQ")
def k_mreq(mn, op, flag):
    add(mn, op, [reg("R", 2)])

# S_RR: outxx(op|dst, src, ROK|UP4) -- adc, sbc, rldb (p.166), rrdb.
@kind("S_RR")
def k_rr(mn, op, flag):
    c = width(mn)
    add(mn, op | 0x8000, [reg(c, 3), reg(c, 2)])

# S_RET: op | cc (UN when omitted).
@kind("S_RET")
def k_ret(mn, op, flag):
    add(mn, op, [cc(0, 3)])

# S_SC: outab(SCHIGH); outrb(src).
@kind("S_SC")
def k_sc(mn, op, flag):
    add(mn, DEF["SCHIGH"] << 8, [Op("IM8", 0, 0, 8, 1, 0x00FF)])

# S_TCC: outxx(op|cc, dst, ROK|UP4).
@kind("S_TCC")
def k_tcc(mn, op, flag):
    add(mn, op | 0x8000, [cc(0, 3), reg(width(mn), 2)])

# S_DI: op &= ~mask for each of VI, NVI named; a clear bit is the one acted on
# (DI p.88; EI likewise).
@kind("S_DI")
def k_di(mn, op, flag):
    add(mn, op & ~3, [Op("INT", 0, 0, 2, 0, 0x0003)])

# S_FLG: op |= mask for each of C, Z, S, P/V named.
@kind("S_FLG")
def k_flg(mn, op, flag):
    add(mn, op & ~0xF0, [Op("FLG", 0, 4, 4, 0, 0x00F0)])

# S_IND/S_INDR: outaw(op | src<<4); outaw(8 or 0 | cnt<<8 | dst<<4).  The
# memory operand is a register pair, an I/O port a word register (6.7).
@kind("S_IND", "S_INDR")
def k_ind(mn, op, flag):
    rep = KINDNAME[mn] == "S_INDR"
    sub = op & 0x0F
    io = ((op >> 8) & 0xFE) == 0x3A
    port_src = io and sub in (0x0, 0x1, 0x8, 0x9)     # IN..: port is the source
    port_dst = io and not port_src                    # OUT..: port is the destination
    d = reg("IR" if port_dst else "IRR", 2, 1)
    s = reg("IR" if port_src else "IRR", 2)
    add(mn, op, [d, s, reg("R", 1, 1)], nw=2, nz=1 << 4, m1=0x000F,
        v1=0 if rep else 8)

# S_TRT/S_TRTR: outaw(op | dst<<4); outaw(0 or 0x0E | cnt<<8 | src<<4)
# (TRIB p.198).
@kind("S_TRT", "S_TRTR")
def k_trt(mn, op, flag):
    add(mn, op, [reg("IRR", 2), reg("IRR", 2, 1), reg("R", 1, 1)], nw=2,
        nz=1 << 4, m1=0x000F, v1=0x0E if KINDNAME[mn] == "S_TRTR" else 0)

# S_CPD/S_CPS: outaw(op | src<<4); outaw(cnt<<8 | dst<<4 | cc).  CPD's
# destination is a register (CPI Rx,src,Ry,cc, p.266), CPS's indirect (CPSIR
# p.83).
@kind("S_CPD", "S_CPS")
def k_cpd(mn, op, flag):
    d = reg(width(mn), 2, 1) if KINDNAME[mn] == "S_CPD" else reg("IRR", 2, 1)
    add(mn, op, [d, reg("IRR", 2), reg("R", 1, 1), cc(1, 3)], nw=2, nz=1 << 4)

# S_RL: outaw(op | (2 ? RLBY2 : 0) | dst<<4) (RLC p.165).
@kind("S_RL")
def k_rl(mn, op, flag):
    add(mn, op, [reg(width(mn), 2), num(0, 1, 1, 1)])

# S_SDA: outxx(op, dst, ROK|UP4); outaw(src<<8).
@kind("S_SDA")
def k_sda(mn, op, flag):
    add(mn, op | 0x8000, [reg(width(mn), 2), reg("R", 1, 1)], nw=2)

# S_EX/S_RSRC: outxx(op|dst, src, ROK|IROK|DAOK|XOK|UP4, +IMOK, +LONG).
@kind("S_EX", "S_RSRC")
def k_rsrc(mn, op, flag):
    modes = ALLMEM + ((IM_,) if KINDNAME[mn] == "S_RSRC" else ())
    if KINDNAME[mn] == "S_RSRC" and flag & DEF["S_L"]:
        f = DEF["LONG"]
    else:
        f = 0
    outxx(mn, op, modes, srcw(mn, flag), 2, [reg(dstw(mn, flag), 3)],
          imw=immw(op, f))

# S_JP: op |= cc (UN when omitted); then as S_CALL.  The target is a code
# address, held in a register pair.
@kind("S_JP")
def k_jp(mn, op, flag):
    outxx(mn, op, (IR_, DA_, X_), "IRR", 2, [cc(0, 3)])

# S_CALL: outxx(op, dst, IROK|DAOK|XOK|UP4|IREF) -- call, ldps.
@kind("S_CALL")
def k_call(mn, op, flag):
    outxx(mn, op, (IR_, DA_, X_), "IRR" if mn == "call" else "IR", 2, [], srcpos=0)

# S_CLR: outxx(op, dst, ROK|IROK|DAOK|XOK|UP4).
@kind("S_CLR")
def k_clr(mn, op, flag):
    outxx(mn, op, ALLMEM, dstw(mn, flag), 2, [], srcpos=0)

# S_DEC: op |= n-1; outxx(op, dst, ROK|IROK|DAOK|XOK|UP4) (DEC p.87).
@kind("S_DEC")
def k_dec(mn, op, flag):
    outxx(mn, op, ALLMEM, width(mn), 2, [num(0, 0, 4, 1)], srcpos=0)

# S_DJNZ: outaw(op | cnt<<8 | disp), disp = (. + 2 - dst) / 2, 0..127.
@kind("S_DJNZ")
def k_djnz(mn, op, flag):
    add(mn, op, [reg(width(mn), 1), Op("RA7", 0, 0, 7, 0, 0x007F)])

# S_BIT: immediate: outxx(op|b, dst, ROK|IROK|DAOK|XOK|UP4); register:
# outaw(op | src); outaw(dst<<8) (RESB dynamic p.161).
@kind("S_BIT")
def k_bit(mn, op, flag):
    outxx(mn, op, ALLMEM, width(mn), 2, [num(0, 0, 4)], srcpos=0)
    add(mn, op, [reg(width(mn), 1, 1), reg("R", 3)], nw=2)

# S_SLA/S_SRA: outaw(op | dst<<4); outaw(n), n negated for a right shift; a
# byte shift keeps it in the low byte.  The two kinds share opcodes, so the
# sign of the count picks the mnemonic.
@kind("S_SLA")
def k_sla(mn, op, flag):
    right = {"sla": "sra", "slab": "srab", "slal": "sral", "sll": "srl",
             "sllb": "srlb", "slll": "srll"}[mn]
    bits = 8 if op & 0xFF00 == 0xB200 else 16
    add(mn, op, [reg(width(mn), 2), Op("SHIFT", 1, 0, bits)], nw=2, alt=right)

@kind("S_SRA")
def k_sra(mn, op, flag):
    pass                        # the negative-count half of S_SLA

# S_CP: register destination as S_RSRC; otherwise an immediate source with
# op = makeop(op, CPI): outxx(op, dst, IROK|DAOK|XOK|UP4); outiw().
@kind("S_CP")
def k_cp(mn, op, flag):
    f = DEF["LONG"] if op == DEF["CPL"] else 0
    outxx(mn, op, ALLMEM + (IM_,), dstw(mn, flag), 2, [reg(dstw(mn, flag), 3)],
          imw=immw(op, f))
    if op != DEF["CPL"]:
        mop = (op & W) | DEF["CPI"]
        cp_imm(mn, mop, 16 if op & W else 8)

def cp_imm(mn, mop, iw):
    # the immediate follows the address, so its word moves with a long one
    add(mn, mop, [reg("IR", 2), im(iw, 1)], nw=2, nz=1 << 4)
    add(mn, mop | 0x4000, [da(1), im(iw, 2)], nw=3, segw=1)
    add(mn, mop | 0x4000, [x(1), im(iw, 2)], nw=3, segw=1, nz=1 << 4)

# S_CALR: outaw(CALR | disp&07777), disp = (. + 2 - dst) / 2.
@kind("S_CALR")
def k_calr(mn, op, flag):
    add(mn, op, [Op("RA12", 0, 0, 12, 0, 0x0FFF)])

# S_IN: IR: outaw(op | src<<4 | dst); DA: outaw(makeop(op, INDA) | dst<<4),
# then the port.  The port register is a word register.
@kind("S_IN")
def k_in(mn, op, flag):
    c = width(mn)
    add(mn, op, [reg(c, 3), reg("IR", 2)], nz=1 << 4)
    add(mn, (op & W) | DEF["INDA"], [reg(c, 2), Op("PORT", 1)], nw=2)

# S_SIN: outaw(op | dst<<4), then the port.
@kind("S_SIN")
def k_sin(mn, op, flag):
    add(mn, op, [reg(width(mn), 2), Op("PORT", 1)], nw=2)

# S_OUT: IR: outaw(op | dst<<4 | src); DA: outaw(makeop(op, OUTDA) | src<<4).
@kind("S_OUT")
def k_out(mn, op, flag):
    c = width(mn)
    add(mn, op, [reg("IR", 2), reg(c, 3)], nz=1 << 4)
    add(mn, (op & W) | DEF["OUTDA"], [Op("PORT", 1), reg(c, 2)], nw=2)

# S_SOUT: outaw(op | src<<4), then the port.
@kind("S_SOUT")
def k_sout(mn, op, flag):
    add(mn, op, [Op("PORT", 1), reg(width(mn), 2)], nw=2)

# S_POP: outxx(op | src<<4, dst, ROK|IROK|DAOK|XOK), no UP4: the stack
# pointer is in bits 7..4 and the operand in 3..0.
@kind("S_POP")
def k_pop(mn, op, flag):
    outxx(mn, op, ALLMEM, dstw(mn, flag), 3, [reg("IR", 2)], srcpos=0)

# S_PUSH: an immediate word: outaw(PUSHI | dst<<4), outrw(src); otherwise
# outxx(op | dst<<4, src, ROK|IROK|DAOK|XOK), no UP4.
@kind("S_PUSH")
def k_push(mn, op, flag):
    outxx(mn, op, ALLMEM, dstw(mn, flag), 3, [reg("IR", 2)])
    if op == DEF["PUSHW"]:
        add(mn, DEF["PUSHI"], [reg("IR", 2), im(16, 1)], nw=2, nz=1 << 4)

# S_LDM: outldm(): op (| 0x4000 for DA/X) | address register<<4; then
# reg<<8 | n-1; then the address.
@kind("S_LDM")
def k_ldm(mn, op, flag):
    for base, store in ((DEF["LDMLD"], False), (DEF["LDMST"], True)):
        r, n = reg("R", 1, 1), num(1, 0, 4, 1)
        for mem, v, nw, segw, nz in ((reg("IR", 2), base, 2, 0, 1 << 4),
                                     (da(2), base | 0x4000, 3, 2, 0),
                                     (x(2), base | 0x4000, 3, 2, 1 << 4)):
            add(mn, v, [mem, r, n] if store else [r, mem, n], nw=nw, segw=segw, nz=nz)

# S_LDR/S_LDAR: outaw(op | dst); outaw(target - . - 4) (LDR p.134).
@kind("S_LDR", "S_LDAR")
def k_ldr(mn, op, flag):
    c = "RR" if mn == "ldar" else dstw(mn, flag)
    add(mn, op, [reg(c, 3), Op("RA16", 1)], nw=2)

# S_JR: outaw(op | cc<<8 | disp&0377), disp = (dst - . - 2) / 2.
@kind("S_JR")
def k_jr(mn, op, flag):
    add(mn, op, [cc(0, 1), Op("RA8", 0, 0, 8, 0, 0x00FF)])

# S_LDA: BX: outbx(LDABX); BA: outba(LDABA); else outxx(LDA|dst, src,
# DAOK|XOK|UP4).  The destination is a pair in segmented mode.
@kind("S_LDA")
def k_lda(mn, op, flag):
    d = reg("RR", 3)
    add(mn, DEF["LDABX"], [d, bx()], nw=2, nz=1 << 4)
    add(mn, DEF["LDABA"], [d, ba(1)], nw=2, nz=1 << 4)
    outxx(mn, DEF["LDA"], (DA_, X_), "RR", 2, [d])

# S_LDK: outxx(op|n, dst, ROK|UP4).
@kind("S_LDK")
def k_ldk(mn, op, flag):
    add(mn, op | 0x8000, [reg("R", 2), num(0, 0, 4)])

# S_LD: mchld().
@kind("S_LD")
def k_ld(mn, op, flag):
    long_ = op == DEF["LDL"]
    c = dstw(mn, flag)
    d = reg(c, 3)
    if op == DEF["LDB"]:                # LDBI | dst<<8 | imm
        add(mn, DEF["LDBI"], [reg("RB", 1), Op("IM8", 0, 0, 8, 1, 0x00FF)])
    # LD Rd,#n for n 0..15 is LDK; the two-word form stays for the rest.
    # load: BA, BX, then outxx(op|dst, src, ROK|IROK|IMOK|DAOK|XOK|UP4 [+LONG])
    bao = DEF["LDLBA"] if long_ else (op & W) | DEF["LDBA"]
    bxo = DEF["LDLBX"] if long_ else (op & W) | DEF["LDBX"]
    add(mn, bao, [d, ba(1)], nw=2, nz=1 << 4)
    add(mn, bxo, [d, bx()], nw=2, nz=1 << 4)
    outxx(mn, op, ALLMEM + (IM_,), c, 2, [d], imw=32 if long_ else immw(op, 0))
    # store: BA, BX, then outxx(ST|src, dst, ROK|DAOK|IROK|XOK|UP4)
    sao = DEF["STLBA"] if long_ else (op & W) | DEF["STBA"]
    sxo = DEF["STLBX"] if long_ else (op & W) | DEF["STBX"]
    so = DEF["STL"] if long_ else (op & W) | DEF["ST"]
    add(mn, sao, [ba(1), d], nw=2, nz=1 << 4)
    add(mn, sxo, [bx(), d], nw=2, nz=1 << 4)
    outxx(mn, so, (IR_, DA_, X_), c, 2, [d], srcpos=0)
    # memory, immediate: makeop(op, LDI): outxx(op, dst, IROK|DAOK|XOK|UP4); outiw()
    if not long_:
        cp_imm(mn, (op & W) | DEF["LDI"], 16 if op & W else 8)

# S_CTL: mchctl(): outaw(op | reg<<4 | ctlr | 8 when the control register
# is the destination).  LDCTLB takes FLAGS only, LDCTL the others.
@kind("S_CTL")
def k_ctl(mn, op, flag):
    if op == DEF["LDCTLB"]:
        f = DEF["FLAGS"]
        add(mn, op | f, [reg("RB", 2), lit("FLAGS")])
        add(mn, op | f | DEF["TOCTLR"], [lit("FLAGS"), reg("RB", 2)])
        return
    for c, n in sorted(CTLR.items()):
        if c == DEF["FLAGS"]:
            continue
        add(mn, op | c, [reg("R", 2), lit(n)])
        add(mn, op | c | DEF["TOCTLR"], [lit(n), reg("R", 2)])

KINDNAME = {n: k for n, k, _, _ in PST}

# ---------------------------------------------------------------- CPU forms
#
# Documented forms the assembler cannot write, decoded so that code from other
# sources reads correctly.  None of them is in the round trip.

def cpu_forms():
    # LDR, LDRB, LDRL store: 0011 001W 0000 Rs / disp, 0011 0111 0000 RRs
    # (p.134).  as reaches these opcodes only through BA with a nonzero base.
    for mn, v, c in (("ldrb", 0x3200, "RB"), ("ldr", 0x3300, "R"),
                     ("ldrl", 0x3700, "RR")):
        add(mn, v, [Op("RA16", 1), reg(c, 3)], nw=2, asm=False)
    # TESTL RRd: the CPU ignores the low nibble of 9Cxy (the manual and the
    # assembler write 9Cx8); Olivetti M20 BASIC relies on it.
    for f in FORMS:
        if f.mn == "TESTL" and f.val == 0x9C08:
            f.mask, f.val = 0xFF00, 0x9C00     # samples keep 9Cx8
    # EPA instruction templates (6.8, p.213-215): two words, plus an address
    # in modes DA and X.  The extended operation itself is the EPU's.
    for hi in (0x0E, 0x0F):
        add("EPU", hi << 8, [], nw=2, nz=1 << 4, free=0x00FF, asm=False)
    for hi in (0x4E, 0x4F):
        add("EPU", hi << 8, [], nw=3, segw=2, free=0x00FF, asm=False)
    for hi in (0x8E, 0x8F):
        add("EPU", hi << 8, [], nw=2, free=0x00FF, asm=False)

# ---------------------------------------------------------------- table

def words_matched(f):
    """every first word a form matches."""
    free = [b for b in range(16) if not f.mask >> b & 1]
    for i in range(1 << len(free)):
        w = f.val
        for j, b in enumerate(free):
            if i >> j & 1:
                w |= 1 << b
        if all((w >> (4 * k)) & 15 for k in range(4) if f.nz >> (4 * k) & 1):
            yield w

def disjoint():
    """the forms, after checking no two of them match the same words."""
    taken = {}
    for f in FORMS:
        for w in words_matched(f):
            for g in taken.get(w, ()):
                if (g.v1 ^ f.v1) & g.m1 & f.m1 == 0:
                    sys.exit("gentab: %04X matches both %s and %s" % (w, g.mn, f.mn))
            taken.setdefault(w, []).append(f)
    return FORMS

def emit(forms):
    strs = [""]
    sidx = {"": 0}
    def s(t):
        if t not in sidx:
            sidx[t] = len(strs)
            strs.append(t)
        return sidx[t]
    ops, rows = [], []
    forms = sorted(forms, key=lambda f: (f.val, f.mask, f.v1))
    for f in forms:
        first = len(ops)
        for o in f.ops:
            aux = s(o.aux) if o.kind == "LIT" else o.aux
            ops.append((K[o.kind], o.word, o.shift, o.width, aux))
        rows.append((f.mask, f.val, f.m1, f.v1, f.nz, f.nw, f.segw, len(f.ops),
                     s(f.mn), s(f.alt) if f.alt else 0, first))
    tabs = {
        "CCNAME": [s(n) for n in CCNAME],
        "FLGNAME": [s(FLAGS[1 << (7 - i)]) for i in range(4)],
        "INTNAME": [s(INTS[2]), s(INTS[1])],
    }
    o = []
    o.append("/* z8ktab.h - Z8001 disassembly table.\n"
             " * GENERATED by tools/loutdis/gentab.py from the assembler's own tables\n"
             " * (src/as/z8001/pst.c, asmch.h) and its encoders (machine.c).  Do not\n"
             " * hand-edit: run `make loutdis-table'.\n"
             " *\n"
             " * A form matches when (w0 & mask) == val, every w0 nibble flagged in nz is\n"
             " * nonzero (bit 4k: bits 4k+3..4k), and (w1 & m1) == v1.  No two forms\n"
             " * match the same words.  nw is the length with every segmented address\n"
             " * short; segw names the word holding one, and a long one (bit 15 set)\n"
             " * adds a word and moves every later word up by one.  An operand is\n"
             " * (kind, word, shift, width, aux); alt is the mnemonic used when a\n"
             " * shift count is negative.\n"
             " */\n\n")
    o.append("#define ZNFORM\t%d\n\n" % len(rows))
    for k in KINDS:
        o.append("#define ZK_%s\t%d\n" % (k, K[k]))
    o.append("\nstatic char *zstr[%d] = {\n" % len(strs))
    for i in range(0, len(strs), 8):
        o.append(" ".join('"%s",' % t for t in strs[i:i + 8]) + "\n")
    o.append("};\n\n")
    o.append("/* condition codes; FLG names bits 7..4; INT names bits 1, 0 */\n")
    o.append("static unsigned short zcc[16] = {%s};\n" % ",".join(map(str, tabs["CCNAME"])))
    o.append("static unsigned short zflg[4] = {%s};\n" % ",".join(map(str, tabs["FLGNAME"])))
    o.append("static unsigned short zint[2] = {%s};\n\n" % ",".join(map(str, tabs["INTNAME"])))
    o.append("struct zop {\n\tunsigned char kind, word, shift, width;\n\tunsigned short aux;\n};\n\n")
    o.append("static struct zop zop[%d] = {\n" % len(ops))
    for op in ops:
        o.append("{%d,%d,%d,%d,%d},\n" % op)
    o.append("};\n\n")
    o.append("struct zform {\n\tunsigned short mask, val, m1, v1, nz;\n"
             "\tunsigned char nw, segw, nop;\n\tunsigned short mnem, alt, op;\n};\n\n")
    o.append("static struct zform zform[ZNFORM] = {\n")
    for r in rows:
        o.append("{0x%04X,0x%04X,0x%04X,0x%04X,0x%04X,%d,%d,%d,%d,%d,%d},\n" % r)
    o.append("};\n")
    return "".join(o)

# ---------------------------------------------------------------- samples
#
# Source lines for every form, with the bytes the form says the assembler
# writes.  Registers sweep every legal value where that is few; immediates,
# addresses and displacements take random and boundary values.

ASCC = names("S_CC", prefer=("un",))

def form_samples(f, rnd, n=48):
    """source lines for form f, each with the words it must assemble to."""
    regs = [o for o in f.ops if o.kind in ("R", "RB", "RR", "RQ", "IR", "IRR",
                                           "X", "BA", "BX")]
    def choices(o):
        if o.kind in ("IR", "IRR", "BA", "BX"):
            return list(range(2, 16, 2))         # a pair, never 0
        if o.kind == "X":
            return list(range(1, 16))
        if o.kind == "RR":
            return list(range(0, 16, 2))
        if o.kind == "RQ":
            return list(range(0, 16, 4))
        return list(range(16))
    combos = [[]]
    for o in regs:
        combos = [c + [v] for c in combos for v in choices(o)]
    if len(combos) > n:
        combos = rnd.sample(combos, n)
    out = []
    for k, combo in enumerate(combos):
        rv = dict(zip(map(id, regs), combo))
        out.append(one_sample(f, rv, rnd, k))
    return [x for x in out if x]

def one_sample(f, rv, rnd, k):
    w = [f.sval] + [0] * (f.nw - 1)
    if f.m1:
        w[1] |= f.v1
    longw = None
    mn = f.asmn
    txt = []
    for o in f.ops:
        kd = o.kind
        if kd in ("R", "RB", "RR", "RQ", "IR", "IRR"):
            r = rv[id(o)]
            w[o.word] |= r << o.shift
            txt.append({"R": "r%d", "RR": "rr%d", "RQ": "rq%d", "IR": "@r%d",
                        "IRR": "@rr%d"}[kd] % r if kd != "RB" else
                       ("rh%d" % r if r < 8 else "rl%d" % (r - 8)))
        elif kd == "IM8":
            v = rnd.randrange(256)
            if o.aux:
                w[0] |= v
                txt.append("%d" % v if mn == "sc" else "$0x%02X" % v)
            else:
                w[o.word] = v << 8 | v
                txt.append("$0x%02X" % v)
        elif kd == "IM16":
            v = rnd.randrange(16, 0x10000)        # 0..15 load as LDK
            w[o.word] = v
            txt.append("$0x%04X" % v)
        elif kd == "IM32":
            v = rnd.randrange(0x80000000)
            w[o.word], w[o.word + 1] = v >> 16, v & 0xFFFF
            txt.append("$0x%08X" % v)
        elif kd == "NUM":
            v = rnd.randrange(1 << o.width)
            w[o.word] |= v << o.shift
            txt.append("$%d" % (v + o.aux))
        elif kd == "SHIFT":
            mx = 8 if o.width == 8 else 32 if f.sval & 4 else 16
            c = rnd.choice([rnd.randrange(0, mx + 1), -rnd.randrange(1, mx + 1),
                            0, mx, -mx, -1, 1])
            if c < 0:
                mn = f.alt.lower()
            w[o.word] = c & (0xFF if o.width == 8 else 0xFFFF)
            txt.append("$%d" % abs(c))
        elif kd in ("DA", "X"):
            seg = rnd.randrange(0x80)
            style = k % 3
            off = rnd.randrange(0x100) if style != 1 else rnd.randrange(0x100, 0x10000)
            if style == 0:
                w[o.word] = seg << 8 | off
                t = "0x%02X|0x%02X" % (seg, off)
            else:
                w[o.word] = 0x8000 | seg << 8
                longw = (o.word, off)
                t = "0x%02X|0x%04X" % (seg, off) if style == 1 else "0x%02X00%04X" % (seg, off)
            if kd == "X":
                r = rv[id(o)]
                w[0] |= r << o.shift
                t += "(r%d)" % r
            txt.append(t)
        elif kd == "BA":
            r, d = rv[id(o)], rnd.randrange(0x10000)
            w[0] |= r << o.shift
            w[o.word] = d
            txt.append("rr%d(0x%04X)" % (r, d))
        elif kd == "BX":
            b, x = rv[id(o)], rnd.randrange(1, 16)
            w[0] |= b << o.aux
            w[1] |= x << 8
            txt.append("rr%d(r%d)" % (b, x))
        elif kd == "PORT":
            v = rnd.randrange(0x10000)
            w[o.word] = v
            txt.append("0x%04X" % v)
        elif kd == "RA16":
            d = rnd.randrange(-1000, 1000) * 2
            w[o.word] = d & 0xFFFF
            txt.append(".%+d" % (d + 4))
        elif kd == "RA8":
            d = rnd.randrange(-100, 100)
            w[0] |= d & 0xFF
            txt.append(".%+d" % (2 + 2 * d))
        elif kd == "RA12":
            d = rnd.randrange(-1000, 1000)
            w[0] |= d & 0xFFF
            txt.append(".%+d" % (2 - 2 * d))
        elif kd == "RA7":
            d = rnd.randrange(128)
            w[0] |= d
            txt.append(".%+d" % (2 - 2 * d))
        elif kd == "CC":
            c = rnd.randrange(1, 16)
            w[o.word] |= c << o.shift
            txt.append(ASCC[c])
        elif kd == "LIT":
            txt.append(o.aux)
        elif kd == "FLG":
            v = rnd.randrange(1, 16)
            w[0] |= v << 4
            txt.append(",".join(FLAGS[1 << (7 - i)] for i in range(4) if v >> (3 - i) & 1))
        elif kd == "INT":
            v = rnd.randrange(3)
            w[0] |= v
            txt.append(",".join(n for b, n in ((2, INTS[2]), (1, INTS[1])) if not v & b))
        else:
            sys.exit("gentab: no sample for operand kind " + kd)
    if longw:
        i, off = longw
        w = w[:i + 1] + [off] + w[i + 1:]
    line = "%s\t%s" % (mn, ",".join(txt)) if txt else mn
    return line, " ".join("%04x" % x for x in w)

def samples(forms, rnd):
    """every form the assembler writes, in a deterministic order."""
    out = []
    for f in forms:
        if not f.asm:
            continue
        # LDB Rd,#n is LDBI for every constant n; the two-word form takes
        # only a relocatable operand, which disassembles as its value.
        if f.asmn == "ldb" and f.sval == 0x2000 and f.ops[1].kind == "IM8":
            continue
        out.extend(form_samples(f, rnd))
    return out

def main():
    build()
    cpu_forms()
    forms = disjoint()
    text = emit(forms)
    if "--check" in sys.argv[1:]:
        if OUT.read_text() != text:
            sys.exit("gentab: %s is not what gentab.py writes; run `make loutdis-table'" % OUT.relative_to(ROOT))
        print("gentab: z8ktab.h matches the assembler's tables (%d forms)" % len(forms))
        return
    if "--samples" in sys.argv[1:]:
        for line, words in samples(forms, random.Random(900)):
            print("%s\t%s" % (line, words))
        return
    OUT.write_text(text)

if __name__ == "__main__":
    main()
