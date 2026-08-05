#!/usr/bin/env python3
# loutid.py -- say what a file IS, from its first bytes, and fail if it is not
# what was asked for.
#
#	loutid.py FILE...		print one line per file
#	loutid.py -q -m z8001 FILE...	silent unless a file is not a Z8001
#					l.out or a Z8001 archive; exit 1 then
#
# WHY THIS EXISTS.  An environment tree is a directory of binaries that a GUEST
# will execute.  Every host build harness in this repository runs the host
# compiler too, and a staging copy that grabbed the wrong artifact -- the host
# cc0 instead of the target one, an x86 `ar' instead of the Coherent one --
# produces a tree that looks complete, mounts, and fails only inside the guest
# with a message about a bad magic number.  The cost of checking is eight bytes
# per file, so it is checked rather than assumed.
#
# WHAT IT READS.  The COHERENT 32-bit object header (include/n.out.h), which is
# the Z8001 native format for assembler output, linker output and kernel exec
# input alike:
#
#	off 0	short l_magic	 0407
#	off 2	short l_flag	 LF_SHR 01 / LF_SEP 02 / LF_NRB 04 / LF_32 020
#	off 4	short l_machine	 M_Z8001 4 (include/mtype.h)
#
# 16-bit fields are little-endian on this target, so 0407 is `07 01'.  An
# archive (include/ar.h) starts with the magic word 0177535 instead and holds
# objects, which are checked individually.
#
# This is a HEADER identification, and it is deliberately not a disassembly:
# it answers "is this a Z8001 program" for every file in a tree in milliseconds
# and with no Go, no simulator and no sibling checkout.  Whether a program also
# RUNS is a separate question that only the emulator can answer, and the
# environment build asks it separately.
import struct
import sys

L_MAGIC = 0o407
M_Z8001 = 4
AR_MAGIC = 0o177535  # include/ar.h ARMAG
MACHINES = {
    1: "pdp11", 2: "vax", 3: "s360", 4: "z8001", 5: "z8002",
    6: "i8086", 7: "i8080", 8: "m6800", 9: "m6809", 10: "m68000", 11: "i386",
}


def flagstr(f):
    names = [(0o1, "shr"), (0o2, "sep"), (0o4, "nrb"), (0o10, "ker"),
             (0o20, "32")]
    return "|".join(n for b, n in names if f & b) or "-"


def ident_lout(b, off=0):
    """(kind, machine-name) for an l.out header at b[off:], or None."""
    if len(b) - off < 8:
        return None
    magic, flag, mach = struct.unpack_from("<hhh", b, off)
    if magic != L_MAGIC:
        return None
    return ("l.out", MACHINES.get(mach, "machine%d" % mach), flagstr(flag))


def ident(path):
    """(ok_machine, description) -- ok_machine is None when unidentifiable."""
    with open(path, "rb") as f:
        b = f.read(4096)
    if len(b) < 2:
        return None, "empty or too short"
    if b[:4] == b"\x7fELF":
        return None, "ELF (a HOST binary)"
    if struct.unpack_from("<H", b, 0)[0] == AR_MAGIC:
        machs = archive_machines(path)
        if machs is None:
            return None, "archive (unreadable member header)"
        if len(machs) == 1:
            return machs.pop(), "archive of l.out objects"
        if not machs:
            return None, "archive (no objects)"
        return None, "archive of MIXED machines: " + ",".join(sorted(machs))
    got = ident_lout(b)
    if got is None:
        return None, "not an l.out (magic %#06x)" % struct.unpack_from("<H", b, 0)[0]
    kind, mach, flags = got
    return mach, "%s %s [%s]" % (kind, mach, flags)


def archive_machines(path):
    """The set of machine names of every object in a COHERENT archive."""
    # ar.h: 2-byte magic, then per member a 28-byte header
    #   char ar_name[14]; int ar_date; short ar_uid, ar_gid, ar_mode;
    #   unsigned int ar_size;  (32-bit fields PDP-canonical: high word first)
    machs = set()
    with open(path, "rb") as f:
        f.seek(2)
        while True:
            hdr = f.read(28)
            if len(hdr) < 28:
                break
            hi, lo = struct.unpack_from("<HH", hdr, 24)
            size = (hi << 16) | lo
            if size == 0 or size > (1 << 26):
                return None
            body = f.read(min(size, 64))
            if len(body) < 8:
                break
            got = ident_lout(body)
            if got:
                machs.add(got[1])
            # Members are NOT padded to an even boundary in this format
            # (checked against libc-z8001.a): the next header follows the
            # body immediately.
            f.seek(size - len(body), 1)
    return machs


def main(argv):
    quiet = False
    want = None
    files = []
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "-q":
            quiet = True
        elif a == "-m":
            i += 1
            want = argv[i]
        elif a.startswith("-"):
            sys.stderr.write("loutid.py: unknown option %s\n" % a)
            return 2
        else:
            files.append(a)
        i += 1
    if not files:
        sys.stderr.write("usage: loutid.py [-q] [-m MACHINE] FILE...\n")
        return 2
    bad = 0
    for p in files:
        try:
            mach, desc = ident(p)
        except OSError as e:
            mach, desc = None, "cannot read: %s" % e
        wrong = want is not None and mach != want
        if wrong:
            bad += 1
        if not quiet or wrong:
            sys.stdout.write("%-40s %s%s\n" % (p, desc,
                             "   <-- WANTED %s" % want if wrong else ""))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
# end of loutid.py
