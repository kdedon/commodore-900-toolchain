#!/usr/bin/env python3
"""shlib-client-check.py -- read a CLIENT l.out and say whether ld bound it.

	shlib-client-check.py CLIENT LIBNAME SYM [SYM ...]

Knows only what shlib.h says, as exec does.  Checks

  * LF_SLREF set, LF_SLIB clear;
  * one LI_LIB record naming LIBNAME by base name, not path;
  * one LI_IMP record per SYM, and no others;
  * per import, a stub in the client's shared text reading
    54 02 8S 00 oo oo 1E 28, where S:oooo is the slot its LI_IMP names;
  * every slot in the client's private data, four zero bytes;
  * nothing unresolved, no relocation left;
  * etext_/edata_/end_ at the ends of the client's own segments.

Exit 0 with PASS lines, or 1 with what is wrong.

"""
import sys

NCPLN = 16
L_SHRI, L_PRVI, L_BSSI, L_SHRD, L_PRVD, L_BSSD, L_DEBUG, L_SYM, L_REL = range(9)
LF_SHR, LF_SEP, LF_NRB, LF_32, LF_SLREF, LF_SLIB = 0o1, 0o2, 0o4, 0o20, 0o40, 0o100
L_GLOBAL, L_ABS, L_REF = 0o20, 9, 10
LI_LIB, LI_IMP = 0o13, 0o14
LDSLEN = 22
STUB = b"\x54\x02\x00\x00\x00\x00\x1e\x28"          # the framing bytes
SLOTLEN = 4

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


def nm(x):
    return x.rstrip(b"\0").decode("latin-1")


def main(client, libname, syms):
    b = open(client, "rb").read()
    print("%s:" % client)
    check(canw(b, 0) == 0o407, "l.out magic 0407")
    check(canw(b, 4) == 4, "machine Z8001")
    flag = canw(b, 2)
    check(flag & LF_SLREF, "LF_SLREF is set (flag %#o)" % flag)
    check(not flag & LF_SLIB, "LF_SLIB is clear: this is a client")
    print("  --   layout: %s" % ("separated I/D, shared text (ld -n -i)"
          if flag & LF_SEP else "one image (a plain ld link)"))
    tbase = canw(b, 6)
    size = [canl(b, 8 + 4 * i) for i in range(9)]

    # File offsets: every section but the two bss ones, in order, from l_tbase.
    foff, o = {}, tbase
    for i in range(9):
        if i in (L_BSSI, L_BSSD):
            continue
        foff[i] = o
        o += size[i]
    if not check(o == len(b), "the section sizes add up to the file size"):
        return

    # Virtual bases.  Without -e, l_entry is where L_SHRI starts.
    entry = canl(b, 8 + 4 * 9)
    phys = ((entry >> 24) & 0xFF) << 16 | (entry & 0xFFFF)
    # As ld's baseall(): LF_SHR and LF_SEP pick one of four layouts.
    vbase, p = {}, phys

    def newpage(a):
        return (a + 0xFFFF) & ~0xFFFF

    def setbase(i, a):
        vbase[i] = a
        return a + size[i]

    shr, sep = flag & LF_SHR, flag & LF_SEP
    p = setbase(L_SHRI, p)
    if shr and not sep:
        p = setbase(L_SHRD, p)
    if shr:
        p = newpage(p)
    p = setbase(L_PRVI, p)
    if shr and not sep:
        p = setbase(L_PRVD, p)
    p = setbase(L_BSSI, p)
    if sep:
        p = newpage(p)
    if not (shr and not sep):
        p = setbase(L_SHRD, p)
    if shr and sep:
        p = newpage(p)
    if not (shr and not sep):
        p = setbase(L_PRVD, p)
    setbase(L_BSSD, p)

    def ptov(a):
        return ((a >> 16) & 0xFF) << 24 | (a & 0xFFFF)

    # The symbol table: the ordinary records, then the import records.
    nsym = size[L_SYM] // LDSLEN
    defs, imports, libs, unres = {}, [], [], []
    for i in range(nsym):
        o = foff[L_SYM] + i * LDSLEN
        name, t, a = b[o:o + NCPLN], canw(b, o + NCPLN), canl(b, o + NCPLN + 2)
        if t == LI_LIB:
            libs.append((nm(name), a))
        elif t == LI_IMP:
            imports.append((nm(name), a))
        elif t == (L_GLOBAL | L_REF):
            unres.append(nm(name))
        else:
            defs[nm(name)] = (t & ~L_GLOBAL, a)

    check(len(libs) == 1 and libs[0][0] == libname,
          "one LI_LIB record, naming the base file name %r (got %r)"
          % (libname, [l[0] for l in libs]))
    check(all(a == 0 for _, a in libs), "LI_LIB ls_addr is 0, as reserved")
    check(sorted(n for n, _ in imports) == sorted(syms),
          "one LI_IMP record per referenced import: %r" % [n for n, _ in imports])
    check(not unres, "no reference left unresolved (%d)" % len(unres))
    check(size[L_REL] == 0, "no relocation left over")
    if fails:
        return

    # Each import: a stub in the client's own shared text, naming its own slot.
    seen = set()
    for name, slot in imports:
        if not check(name in defs, "%s is defined in the client" % name):
            continue
        seg, addr = defs[name]
        if not check(seg == L_SHRI,
                     "%s's stub is in the client's shared text" % name):
            continue
        soff = ((addr >> 24) & 0xFF) << 16 | (addr & 0xFFFF)
        soff -= vbase[L_SHRI]
        if not check(0 <= soff and soff + 8 <= size[L_SHRI]
                     and soff not in seen,
                     "%s's stub is a distinct 8 bytes inside L_SHRI" % name):
            continue
        seen.add(soff)
        got = b[foff[L_SHRI] + soff:foff[L_SHRI] + soff + 8]
        want = bytearray(STUB)
        want[2] = 0x80 | ((slot >> 24) & 0x7F)      # SL long-address marker
        want[3] = 0x00
        want[4] = (slot >> 8) & 0xFF
        want[5] = slot & 0xFF
        check(got == bytes(want),
              "%s: stub is %s (ldl rr2,slot / jp (rr2), slot %08x)"
              % (name, got.hex(" "), slot))

        # The slot itself: inside the private data, four bytes, zero.
        poff = ((slot >> 24) & 0xFF) << 16 | (slot & 0xFFFF)
        poff -= vbase[L_PRVD]
        if not check(0 <= poff and poff + SLOTLEN <= size[L_PRVD],
                     "%s's slot %08x lies in the client's private data"
                     % (name, slot)):
            continue
        check(b[foff[L_PRVD] + poff:foff[L_PRVD] + poff + SLOTLEN]
              == b"\0" * SLOTLEN, "%s's slot is four zero bytes" % name)

    # The end markers must be the client's own.

    for name, seg in (("etext_", L_PRVI), ("edata_", L_PRVD), ("end_", L_BSSD)):
        if not check(name in defs, "%s is defined" % name):
            continue
        s, a = defs[name]
        want = ptov(vbase[seg] + size[seg])
        check(s == seg and a == want,
              "%s = %08x, the end of the client's own %s"
              % (name, a, ("SHRI PRVI BSSI SHRD PRVD BSSD".split())[seg]))


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
    if fails:
        print("%d check(s) failed" % len(fails))
        sys.exit(1)
    sys.exit(0)
