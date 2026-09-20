#!/usr/bin/env python3
"""shlib-check.py -- read a shared library and say whether it is one.

	shlib-check.py LIBRARY EXPORTLIST

Knows only what shlib.h says, as the kernel's loader does.  Checks

  * the header: magic, Z8001, LF_SHR and LF_SLIB;
  * the export table: magic, version, count, entry offset, names sorted
    unsigned, exactly the listed names, each offset on its symbol;
  * the fixup list in L_DEBUG: count and size agree, each entry in its image
    and naming a byte that holds the segment it claims;
  * completeness against the relocation records.

Exit 0 with PASS lines, or 1 with what is wrong.
"""
import sys

NCPLN = 16
L_SHRI, L_PRVI, L_BSSI, L_SHRD, L_PRVD, L_BSSD, L_DEBUG, L_SYM, L_REL = range(9)
LF_SHR, LF_SLIB = 0o1, 0o100
LR_SEG, LR_PCR, LR_OP = 0o17, 0o20, 0o340
LR_WORD, LR_LONG = 1 << 5, 2 << 5
L_GLOBAL, L_ABS, L_REF = 0o20, 9, 10
SL_MAGIC, SL_VERSION, SL_HDRLEN, SL_EXPLEN, SL_FIXLEN = 0x534C, 1, 16, 20, 4
SF_LOC_PRIVATE, SF_REF_PRIVATE = 0x0001, 0x0100
SL_NOMSHR, SL_NOMPRV = 3, 4
LDHLEN, LDSLEN = 48, 22

fails = []


def check(cond, what):
    if cond:
        print("  PASS %s" % what)
    else:
        print("  FAIL %s" % what)
        fails.append(what)
    return cond


def canw(b, o):                 # canonical short: low byte first
    return b[o] | b[o + 1] << 8


def canl(b, o):                 # canonical long: high word first, words LE
    return (b[o] | b[o + 1] << 8) << 16 | (b[o + 2] | b[o + 3] << 8)


def bew(b, o):                  # target memory order
    return b[o] << 8 | b[o + 1]


def bel(b, o):
    return bew(b, o) << 16 | bew(b, o + 2)


def main(libname, expname):
    b = open(libname, "rb").read()
    want = []
    for line in open(expname):
        line = line.split("#")[0].strip()
        if line:
            want.append(line[:NCPLN].encode().ljust(NCPLN, b"\0"))
    want.sort()

    print("%s:" % libname)
    check(canw(b, 0) == 0o407, "l.out magic 0407")
    check(canw(b, 4) == 4, "machine Z8001")
    flag = canw(b, 2)
    check(flag & LF_SLIB, "LF_SLIB is set (flag %#o)" % flag)
    check(flag & LF_SHR, "LF_SHR is set: one shared segment, one private")

    size = [canl(b, 8 + 4 * i) for i in range(9)]
    off, o = {}, LDHLEN
    for i in range(9):
        if i in (L_BSSI, L_BSSD):
            continue
        off[i] = o
        o += size[i]
    if not check(o == len(b), "the section sizes add up to the file size"):
        return
    shrlen = size[L_SHRI] + size[L_SHRD]
    prvlen = size[L_PRVI] + size[L_PRVD]
    check(shrlen <= 0x10000, "the shared segment fits one 64K segment")
    check(prvlen + size[L_BSSI] + size[L_BSSD] <= 0x10000,
          "the private segment fits one 64K segment")

    # ---- the export table ----
    s = off[L_SHRI]
    check(bew(b, s) == SL_MAGIC, "export header magic 'SL'")
    check(bew(b, s + 2) == SL_VERSION, "format version %d" % SL_VERSION)
    nexp = bew(b, s + 4)
    check(bew(b, s + 6) == SL_HDRLEN, "entries start at offset %d" % SL_HDRLEN)
    nfix = bew(b, s + 8)
    check(bew(b, s + 10) == L_DEBUG, "the fixup list is in L_DEBUG")
    fixoff = bel(b, s + 12)
    check(fixoff == off[L_DEBUG],
          "sl_fixoff %#x is where L_DEBUG starts" % fixoff)
    check(size[L_DEBUG] == nfix * SL_FIXLEN,
          "l_ssize[L_DEBUG] is %d fixups" % nfix)

    # the symbol table, to check the offsets against
    syms = {}
    for p in range(off[L_SYM], off[L_SYM] + size[L_SYM], LDSLEN):
        syms[b[p:p + NCPLN]] = (canw(b, p + NCPLN), canl(b, p + NCPLN + 2))

    got, ok_off, ok_sym = [], True, True
    for i in range(nexp):
        e = s + SL_HDRLEN + i * SL_EXPLEN
        name = b[e:e + NCPLN]
        eoff = bew(b, e + 18)
        got.append(name)
        if not (0 <= eoff < shrlen):
            ok_off = False
        t = syms.get(name)
        if t is None or t[0] != (L_GLOBAL | L_SHRI) or (t[1] & 0xFFFF) != eoff:
            ok_sym = False
    check(nexp == len(want), "%d exports, as the list names" % len(want))
    check(got == want, "the exports are the listed names, sorted by name")
    check(got == sorted(got) and len(set(got)) == len(got),
          "the entries are sorted and no two are equal in %d bytes" % NCPLN)
    check(ok_off, "every export offset is inside the shared segment")
    check(ok_sym, "every export offset is that symbol's own address")

    # ---- the fixup list, entry by entry ----
    fix = []
    bad_place, bad_byte = [], []
    for i in range(nfix):
        p = off[L_DEBUG] + i * SL_FIXLEN
        fl, fo = bew(b, p), bew(b, p + 2)
        fix.append((fl, fo))
        priv = bool(fl & SF_LOC_PRIVATE)
        # The file orders SHRI, PRVI, SHRD, PRVD, so a segment's two halves
        # are not contiguous here.

        ilen = size[L_PRVI] if priv else size[L_SHRI]
        lim = prvlen if priv else shrlen
        if fo + 4 > lim:
            bad_place.append((fl, fo))
            continue
        where = (off[L_PRVI if priv else L_SHRI] + fo if fo < ilen
                 else off[L_PRVD if priv else L_SHRD] + fo - ilen)
        seg = SL_NOMPRV if fl & SF_REF_PRIVATE else SL_NOMSHR
        if b[where] & 0x7F != seg:
            bad_byte.append((fl, fo, b[where]))
    check(not bad_place, "every fixup names a byte inside its own image")
    check(not bad_byte,
          "every fixup names a byte holding the nominal segment%s"
          % ("" if not bad_byte else " -- %r" % bad_byte[:3]))
    check(fix == sorted(fix, key=lambda f: (f[0] & SF_LOC_PRIVATE, f[1])),
          "the list is in one pass order: shared image first, then private")

    # ---- completeness, from the relocation records ----
    want_fix, unresolved, bad_rel = [], 0, []
    p, end = off[L_REL], off[L_REL] + size[L_REL]
    while p < end:
        op, addr = b[p], canl(b, p + 1)
        p += 5
        seg = op & LR_SEG
        if seg == L_SYM:
            p += 2
            unresolved += 1
            continue
        if seg in (L_ABS, L_REF):
            continue
        if op & LR_OP == LR_WORD or op & LR_PCR:
            continue
        if op & LR_OP != LR_LONG:
            bad_rel.append(op)
            continue
        if SL_NOMSHR << 16 <= addr < (SL_NOMSHR << 16) + shrlen:
            fl, fo = 0, addr - (SL_NOMSHR << 16)
        elif SL_NOMPRV << 16 <= addr < (SL_NOMPRV << 16) + prvlen:
            fl, fo = SF_LOC_PRIVATE, addr - (SL_NOMPRV << 16)
        else:
            bad_rel.append(op)
            continue
        if seg not in (L_SHRI, L_SHRD):
            fl |= SF_REF_PRIVATE
        want_fix.append((fl, fo))
    check(unresolved == 0, "no unresolved relocation is left in the library")
    check(not bad_rel, "no relocation carries a segment the loader cannot move")
    missing = sorted(set(want_fix) - set(fix))
    extra = sorted(set(fix) - set(want_fix))
    check(not missing,
          "every relocated segment reference has a fixup%s"
          % ("" if not missing else " -- missing %s"
             % ", ".join("%s+%#x" % ("private" if f & SF_LOC_PRIVATE
                                     else "shared", o)
                         for f, o in missing[:4])))
    check(not extra,
          "the list names no byte that is not a relocated segment byte%s"
          % ("" if not extra else " -- %r" % extra[:4]))
    check(len(fix) == len(set(fix)), "no fixup is listed twice")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
    if fails:
        print("shlib-check: %d check(s) failed" % len(fails))
        sys.exit(1)
    print("shlib-check: %s is a shared library in the published format"
          % sys.argv[1])
