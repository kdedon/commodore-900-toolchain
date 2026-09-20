#!/usr/bin/env python3
"""fixed-check.py LIBRARY BASE NAME... -- read a fixed-address library back.

Checks the jump table at the head of the shared segment (six-byte
`jp <long DA>' entries), that each exported NAME points at its own entry, and
that no per-program linker symbol is exported.  Other code globals are
reported.  Constants are spelled out, not taken from the toolchain's headers.

"""
import sys

HDR, NSEG, LDSLEN, NCPLN = 48, 9, 22, 16
SHRI, PRVI, BSSI, SHRD, PRVD, BSSD, DEBUG, SYM, REL = range(9)
L_GLOBAL, L_ABS, L_REF = 0o20, 9, 10
LF_SHR, LF_SEP, LF_32, LF_SLIB = 0o1, 0o2, 0o20, 0o100
JMPLEN = 6
PERPROG = ('etext_', 'edata_', 'end_')

fails = []


def chk(ok, what):
    print("  %s %s" % ("PASS" if ok else "FAIL", what))
    if not ok:
        fails.append(what)


def rdw(b, o):
    return b[o] | b[o + 1] << 8


def rdl(b, o):
    return rdw(b, o) << 16 | rdw(b, o + 2)


def bew(b, o):			# a target memory image: big-endian
    return b[o] << 8 | b[o + 1]


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    b = open(argv[1], 'rb').read()
    base = int(argv[2], 0)
    want = set(argv[3:])
    bseg = base >> 24

    chk(rdw(b, 0) == 0o407 and rdw(b, 6) == HDR, "l.out magic and header size")
    flag = rdw(b, 2)
    chk(flag & (LF_SLIB | LF_SHR | LF_32) == (LF_SLIB | LF_SHR | LF_32)
        and not flag & LF_SEP,
        "LF_SLIB|LF_SHR|LF_32 set and LF_SEP clear (flag 0%o)" % flag)
    ss = [rdl(b, 8 + 4 * i) for i in range(NSEG)]
    off, o = {}, HDR
    for i in range(NSEG):
        if i in (BSSI, BSSD):
            continue
        off[i] = o
        o += ss[i]
    chk(o == len(b), "the section sizes account for the whole file")
    chk(rdl(b, 44) == base,
        "l_entry is the link base 0x%08X" % base)
    chk(ss[SHRI] + ss[SHRD] <= 0x10000 and
        ss[PRVI] + ss[PRVD] + ss[BSSI] + ss[BSSD] <= 0x10000,
        "each half fits one hardware segment")
    chk(ss[DEBUG] == 0, "no fixup list: nothing is relocated at load")

    # ---- the table, at offset 0 of the shared segment
    t = off[SHRI]
    tlen = bew(b, t)
    n = (tlen - 2) // JMPLEN
    chk(tlen >= 2 and (tlen - 2) % JMPLEN == 0,
        "the jump table starts the shared segment: %d bytes = 2 + %d*%d"
        % (tlen, n, JMPLEN))
    chk(tlen <= ss[SHRI], "the table lies inside the shared text")
    slot = {}
    for i in range(n):
        e = t + 2 + i * JMPLEN
        a = "entry %d at 0x%04X" % (i, 2 + i * JMPLEN)
        if b[e] != 0x5E or b[e + 1] != 0x08:
            chk(False, "%s is `jp' (found %02X%02X)" % (a, b[e], b[e + 1]))
            continue
        if b[e + 2] != 0x80 | bseg or b[e + 3] != 0:
            chk(False, "%s is a long-form DA in segment %d (found %02X%02X)"
                % (a, bseg, b[e + 2], b[e + 3]))
            continue
        tgt = bew(b, e + 4)
        chk(tlen <= tgt < ss[SHRI],
            "%s jumps to 0x%04X, past the table and inside the text"
            % (a, tgt))
        slot[base + 2 + i * JMPLEN] = tgt

    # ---- the symbol table
    seen, extra, perprog = {}, [], []
    for p in range(off[SYM], off[SYM] + ss[SYM], LDSLEN):
        nm = b[p:p + NCPLN].split(b'\0')[0].decode('latin1')
        ty = rdw(b, p + NCPLN)
        ad = rdl(b, p + NCPLN + 2)
        if nm in PERPROG:
            perprog.append((nm, ty))
            continue
        if not ty & L_GLOBAL:
            continue
        if ty & ~L_GLOBAL in (SHRI, PRVI, BSSI):
            seen[nm] = ad
            if nm not in want:
                extra.append(nm)
        elif ty & ~L_GLOBAL in (SHRD, PRVD, BSSD):
            chk(ad >> 24 == bseg + (0 if ty & ~L_GLOBAL == SHRD else 1),
                "data export %s is an absolute in segment %d"
                % (nm, ad >> 24))

    chk(set(seen) == want, "exported exactly %s" % " ".join(sorted(want)))
    chk(extra == [], "no unexpected code global (%s)" % " ".join(extra))
    chk(len(seen) == n, "%d names for %d slots" % (len(seen), n))
    for nm in sorted(seen):
        chk(seen[nm] in slot,
            "%s is its own jump slot 0x%08X" % (nm, seen[nm]))
    chk(len(set(seen.values())) == len(seen), "no two names share a slot")
    chk(perprog != [], "the linker's per-program symbols are in the table")
    for nm, ty in perprog:
        chk(not ty & L_GLOBAL, "%s is not exported" % nm)
    return 1 if fails else 0


sys.exit(main(sys.argv))
