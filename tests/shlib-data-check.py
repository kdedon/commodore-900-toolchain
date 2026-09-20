#!/usr/bin/env python3
"""shlib-data-check.py -- check a library's data exports or a client's data
slots against shlib.h.

    shlib-data-check.py lib libtoy.1      the export table and the library's
                                          own cells
    shlib-data-check.py cli a.out         the LI_IMP records and the cells they
                                          name
    shlib-data-check.py shrd libro.1      a `readonly' table exported out of
                                          the SHARED segment
"""
import sys

NCPLN, LDSLEN, NLSEG = 16, 22, 9
L_SHRI, L_PRVI, L_BSSI, L_SHRD, L_PRVD, L_BSSD, L_DEBUG, L_SYM, L_REL = range(9)
LI_LIB, LI_IMP = 0o13, 0o14
SL_HDRLEN, SL_EXPLEN, SL_FIXLEN = 16, 20, 4
SE_DATA, SE_SHRD = 0x0001, 0x0002
SF_LOC_PRIVATE, SF_REF_PRIVATE = 0x0001, 0x0100
SL_NOMSHR, SL_NOMPRV = 3, 4
LF_SLIB, LF_SLREF = 0o100, 0o40

EXPORTS = {b"toy_box_": True, b"toy_arr_": True,
           b"toy_sum_": False, b"toy_set_": False}

nfail = 0


def ok(msg):
    print("  PASS %s" % msg)


def bad(msg):
    global nfail
    nfail += 1
    print("  FAIL %s" % msg)


class Lout:
    """An l.out in the canonical field order: a short is low byte first, a long
    is high word first with each word low byte first (<canon.h>)."""

    def __init__(self, path):
        self.d = open(path, "rb").read()
        self.flag = self.w(2)
        self.tbase = self.w(6)
        self.ssize = [self.l(8 + 4 * i) for i in range(NLSEG)]
        off = self.tbase
        self.foff = {}
        for s in (L_SHRI, L_PRVI, L_SHRD, L_PRVD, L_DEBUG, L_SYM, L_REL):
            self.foff[s] = off
            off += self.ssize[s]

    def w(self, o):
        return self.d[o] | self.d[o + 1] << 8

    def l(self, o):
        return (self.w(o) << 16) | self.w(o + 2)

    def bw(self, o):			# a target memory image: big-endian
        return self.d[o] << 8 | self.d[o + 1]

    def sect(self, s):
        return self.d[self.foff[s]:self.foff[s] + self.ssize[s]]

    def syms(self):
        for k in range(self.ssize[L_SYM] // LDSLEN):
            p = self.foff[L_SYM] + LDSLEN * k
            yield (self.d[p:p + NCPLN].rstrip(b"\0"), self.w(p + NCPLN),
                   self.l(p + NCPLN + 2))


def dolib(path):
    f = Lout(path)
    if not f.flag & LF_SLIB:
        bad("LF_SLIB is clear")
        return
    t = f.foff[L_SHRI]
    nexp, expoff, nfix = f.bw(t + 4), f.bw(t + 6), f.bw(t + 8)
    prvsz = (f.ssize[L_PRVI] + f.ssize[L_PRVD]
             + f.ssize[L_BSSI] + f.ssize[L_BSSD])
    seen = {}
    for i in range(nexp):
        p = t + expoff + SL_EXPLEN * i
        nm = f.d[p:p + NCPLN].rstrip(b"\0")
        flags, off = f.bw(p + NCPLN), f.bw(p + NCPLN + 2)
        seen[nm] = (flags, off)
    for nm, isdata in EXPORTS.items():
        if nm not in seen:
            bad("%s is not exported" % nm.decode())
            continue
        flags, off = seen[nm]
        if bool(flags & SE_DATA) != isdata:
            bad("%s: se_flags %#x, expected SE_DATA %s"
                % (nm.decode(), flags, isdata))
        elif isdata and off >= prvsz:
            bad("%s: offset %#x is outside the %d-byte private image"
                % (nm.decode(), off, prvsz))
        elif not isdata and off >= f.ssize[L_SHRI]:
            bad("%s: offset %#x is outside the shared text" % (nm.decode(), off))
        else:
            ok("%-9s %s at %#06x" % (nm.decode(),
                                     "object in the private image" if isdata
                                     else "function in the shared text", off))
    box = seen.get(b"toy_box_", (0, None))[1]
    arr = seen.get(b"toy_arr_", (0, None))[1]
    # The library's own cells: each points at an export in the private segment
    # and has a fixup.
    prvd = f.sect(L_PRVD)
    cells = {}
    for o in range(0, len(prvd) - 3, 2):
        if prvd[o] == SL_NOMPRV and prvd[o + 1] == 0:
            cells[o] = prvd[o + 2] << 8 | prvd[o + 3]
    want = {box, box + 2, arr}
    if want <= set(cells.values()):
        ok("the library's own cells point at its own data: %s"
           % " ".join("%#06x" % v for v in sorted(set(cells.values()))))
    else:
        bad("the library's own cells are %s, wanted %s"
            % (sorted(set(cells.values())), sorted(want)))
    fx = f.d[f.foff[L_DEBUG]:f.foff[L_DEBUG] + SL_FIXLEN * nfix]
    fixed = set()
    for i in range(nfix):
        fl = fx[SL_FIXLEN * i] << 8 | fx[SL_FIXLEN * i + 1]
        of = fx[SL_FIXLEN * i + 2] << 8 | fx[SL_FIXLEN * i + 3]
        if fl & SF_LOC_PRIVATE and fl & SF_REF_PRIVATE:
            fixed.add(of - f.ssize[L_PRVI])
    missing = [o for o in cells if o not in fixed]
    if missing:
        bad("cells at %s carry no private->private fixup" % missing)
    else:
        ok("every cell is in the fixup list, so the pair moves with it")


def docli(path):
    f = Lout(path)
    if not f.flag & LF_SLREF:
        bad("LF_SLREF is clear")
        return
    prvd = f.sect(L_PRVD)
    base = None
    imps = {}
    for nm, t, a in f.syms():
        if t == LI_LIB:
            ok("LI_LIB %s" % nm.decode())
        elif t == LI_IMP:
            imps.setdefault(nm, []).append(a)
    if base is None:
        # The virtual base of L_PRVD is derived from the lowest slot, below.
        pass
    for nm, isdata in EXPORTS.items():
        if nm not in imps:
            bad("no LI_IMP for %s" % nm.decode())
            continue
        n = len(imps[nm])
        if isdata:
            ok("%-9s %d slot%s" % (nm.decode(), n, "" if n == 1 else "s"))
        elif n != 1:
            bad("%s: %d LI_IMP records for a function" % (nm.decode(), n))
        else:
            ok("%-9s one slot, for its stub" % nm.decode())
    if len(imps.get(b"toy_box_", [])) < 2:
        bad("toy_box_ has fewer than two slots: `.a' and `.b' are one cell, so"
            " the member offset went somewhere it cannot be bound from")
    # Each slot lies in L_PRVD and holds only its addend; segment 0 traps
    # until exec binds it.
    allslots = [a for v in imps.values() for a in v]
    lo = min(allslots)
    seg = (lo >> 24) & 0xFF
    pbase = lo & 0xFFFF
    for a in allslots:
        if ((a >> 24) & 0xFF) != seg:
            bad("slot %08x is not in the private data segment" % a)
            continue
        o = (a & 0xFFFF) - pbase
        if o < 0 or o + 4 > len(prvd):
            bad("slot %08x is outside L_PRVD" % a)
        elif prvd[o] != 0 or prvd[o + 1] != 0:
            bad("slot %08x is not zero-segmented: %s" % (a, prvd[o:o + 4].hex()))
    if nfail == 0:
        ok("every slot is a zero-segmented far pointer inside L_PRVD")
    addends = sorted((((a & 0xFFFF) - pbase) for a in imps[b"toy_box_"]))
    vals = [prvd[o + 2] << 8 | prvd[o + 3] for o in addends]
    if sorted(vals) == [0, 2]:
        ok("toy_box_'s two slots carry the addends 0 and 2 (`.a' and `.b')")
    else:
        bad("toy_box_'s slots carry %s, wanted [0, 2]" % vals)


def doshrd(path):
    """A `readonly' object is in L_SHRD.  Its export is SE_DATA|SE_SHRD: a slot
    that exec fills with the shared segment."""

    f = Lout(path)
    t = f.foff[L_SHRI]
    nexp, expoff = f.bw(t + 4), f.bw(t + 6)
    for i in range(nexp):
        p = t + expoff + SL_EXPLEN * i
        if f.d[p:p + NCPLN].rstrip(b"\0") != b"toy_ro_":
            continue
        flags, off = f.bw(p + NCPLN), f.bw(p + NCPLN + 2)
        if flags != (SE_DATA | SE_SHRD):
            bad("toy_ro_: se_flags %#06x, wanted SE_DATA|SE_SHRD" % flags)
        elif not f.ssize[L_SHRI] <= off < f.ssize[L_SHRI] + f.ssize[L_SHRD]:
            bad("toy_ro_: offset %#06x is not in L_SHRD (%#06x..%#06x)"
                % (off, f.ssize[L_SHRI], f.ssize[L_SHRI] + f.ssize[L_SHRD]))
        else:
            ok("toy_ro_  SE_DATA|SE_SHRD at %#06x, in the shared segment "
               "past the %d-byte text" % (off, f.ssize[L_SHRI]))
        return
    bad("toy_ro_ is not exported")


if __name__ == "__main__":
    {"lib": dolib, "cli": docli, "shrd": doshrd}[sys.argv[1]](sys.argv[2])
    sys.exit(1 if nfail else 0)
