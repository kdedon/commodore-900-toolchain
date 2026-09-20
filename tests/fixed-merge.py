#!/usr/bin/env python3
"""fixed-merge.py CLIENT LIBRARY OUT -- one l.out the runner can run.

The runner loads one `-n -i' file, its four sections at consecutive segments
from the entry symbol's.  So the two images become those four sections --

    L_SHRI   the client, whole            segment 3   (ld -R 0x03000000)
    L_PRVI   one filler byte              segment 4
    L_SHRD   the library's shared half    segment 5   (slgen -F 0x05000000)
    L_PRVD   the library's private half   segment 6

-- with the client's symbol table, so `f_' is at segment 3.  bss is written
as zeroes, since the loader copies each section's declared size.
"""
import sys

HDR, NSEG = 48, 9
SHRI, PRVI, BSSI, SHRD, PRVD, BSSD, DEBUG, SYM, REL = range(9)


def rdw(b, o):			# short: low byte first
    return b[o] | b[o + 1] << 8


def rdl(b, o):			# long: high word first, each word low byte first
    return rdw(b, o) << 16 | rdw(b, o + 2)


def wrw(v):
    return bytes((v & 0xFF, (v >> 8) & 0xFF))


def wrl(v):
    return wrw((v >> 16) & 0xFFFF) + wrw(v & 0xFFFF)


class Lout:
    def __init__(self, path):
        self.b = open(path, 'rb').read()
        if rdw(self.b, 0) != 0o407 or rdw(self.b, 6) != HDR:
            sys.exit("%s: not a 48-byte-header l.out" % path)
        self.flag = rdw(self.b, 2)
        self.ss = [rdl(self.b, 8 + 4 * i) for i in range(NSEG)]
        self.off, o = {}, HDR
        for i in range(NSEG):
            if i in (BSSI, BSSD):
                continue
            self.off[i] = o
            o += self.ss[i]
        if o != len(self.b):
            sys.exit("%s: section sizes do not add up to the file size" % path)

    def sect(self, i):
        return self.b[self.off[i]:self.off[i] + self.ss[i]]


def main(argv):
    if len(argv) != 4:
        sys.exit(__doc__)
    cli, lib = Lout(argv[1]), Lout(argv[2])

    # Every client section in memory order, then its bss as zeroes.

    client = b''.join(cli.sect(i) for i in (SHRI, PRVI, SHRD, PRVD))
    client += bytes(cli.ss[BSSI] + cli.ss[BSSD])
    shared = lib.sect(SHRI) + lib.sect(SHRD)
    private = lib.sect(PRVI) + lib.sect(PRVD) \
        + bytes(lib.ss[BSSI] + lib.ss[BSSD])
    syms = cli.sect(SYM)

    ss = [0] * NSEG
    ss[SHRI], ss[PRVI], ss[SHRD], ss[PRVD] = \
        len(client), 1, len(shared), len(private)
    ss[SYM] = len(syms)
    hdr = wrw(0o407) + wrw(cli.flag | 0o3) + wrw(4) + wrw(HDR)
    hdr += b''.join(wrl(v) for v in ss) + wrl(rdl(cli.b, 44))
    out = hdr + client + b'\0' + shared + private + syms
    open(argv[3], 'wb').write(out)
    return 0


sys.exit(main(sys.argv))
