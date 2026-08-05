#!/usr/bin/env python3
"""mi-divergence -- the machine-independent front end is not edited, audited.

The compiler's correctness argument rests on a claim: the committed source is
pristine MWC 4.2.12 except where a deliberate, justified fix says otherwise.
That claim is only worth anything if the record of the exceptions is COMPLETE,
so the record is a gate: a file that differs from the donor with no
justification fails, and nobody can make it pass by writing prose.

Two committed files carry the record, and neither is prose:

  src/cc/MI-BASELINE  what each MI file looked like in the pristine donor, as a
                      SHA-256.  Generated from $MWC_DONOR by `make mi-baseline'
                      and never by hand -- and never from our own tree, which
                      would make it agree with whatever we did.
  src/cc/MI-PATCHES   one record per deliberate divergence: the files it covers
                      WITH THE HASH THE JUSTIFICATION WAS WRITTEN AGAINST, what
                      the fix is, and why it is correct on the native C900.

docs/PATCHES.md's BAKED table is GENERATED from MI-PATCHES (`make mi-table', and
this gate fails if they are stale), because the hand-maintained table drifted
exactly the way hand-maintained audits drift: it claimed a file was
byte-identical to the donor when it was not, and two divergences passed the old
gate on the strength of an unrelated backtick elsewhere in the page.

The hashes are why $MWC_DONOR is no longer needed to run this.  The donor is a
200 MB third-party archive that must not become a build dependency, so a gate
that could only run beside it ran nowhere: CI printed SKIPPED and exited 0, and
the rule that defines this repository was enforced by nothing.  What the donor
adds when it IS present is the deeper check -- that the baseline itself is
honest, and the actual text of each divergence.

    mi-divergence.py check      the gate.  $MWC_DONOR optional, never required
    mi-divergence.py baseline   rewrite MI-BASELINE from $MWC_DONOR
    mi-divergence.py table      rewrite docs/PATCHES.md's generated tables
"""

import hashlib
import os
import re
import subprocess
import sys

HOME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(HOME, "src", "cc")
BASELINE = os.path.join(SRC, "MI-BASELINE")
PATCHES = os.path.join(SRC, "MI-PATCHES")
TABLE = os.path.join(HOME, "docs", "PATCHES.md")

# The passes' machine-INDEPENDENT directories.  Machine layers live in
# <pass>/z8001/ and are ours; only the top level of these is donor text.
MIDIRS = ("n0", "n1", "n2", "n3", "common", "coh", "h")

BEGIN = "<!-- BEGIN GENERATED %s -- from src/cc/MI-PATCHES, `make mi-table' -->"
END = "<!-- END GENERATED %s -->"


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(65536), b""):
            h.update(b)
    return h.hexdigest()


def mifiles(root):
    """Every MI-directory source file under `root', as relative paths."""
    out = []
    for d in MIDIRS:
        dp = os.path.join(root, d)
        if not os.path.isdir(dp):
            continue
        for n in sorted(os.listdir(dp)):
            if n.endswith((".c", ".h")) and os.path.isfile(os.path.join(dp, n)):
                out.append(d + "/" + n)
    return out


def donor():
    d = os.environ.get("MWC_DONOR")
    if not d:
        return None
    if not os.path.isfile(os.path.join(d, "n0", "expr.c")):
        sys.exit("mi-divergence: MWC_DONOR=%s is not an MWC c/ tree" % d)
    return d


# --------------------------------------------------------------------------
# MI-BASELINE:  <sha256|NOT-VENDORED>  <path>


def read_baseline():
    rows = {}
    with open(BASELINE) as f:
        for ln in f:
            ln = ln.split("#", 1)[0].strip()
            if not ln:
                continue
            h, p = ln.split()
            rows[p] = h
    return rows


def gen_baseline(d):
    lines = [
        "# MI-BASELINE -- the pristine donor, by hash.  GENERATED, not written:",
        "#     make mi-baseline        (with $MWC_DONOR set)",
        "#",
        "# Donor: Mark Williams COHERENT 4.2.12 c/ tree, compiler V4.6.3 -- the",
        "# newest MWC compiler source that exists (docs/toolchain TASK-234).  It is",
        "# not vendored a second time: this repository already SHIPS that source in",
        "# src/cc, and the only datum missing is what it looked like before we",
        "# touched it, which is exactly one hash per file.",
        "#",
        "# NOT-VENDORED names a donor file this tree deliberately does not carry;",
        "# it must stay absent, so that vendoring one later is a decision and not",
        "# a slip.  A file present here and absent from the donor cannot exist:",
        "# it would be a new file in a machine-independent directory, which is the",
        "# thing the rule forbids outright.",
        "#",
        "# sha256                                                            path",
    ]
    for rel in mifiles(d):
        ours = os.path.join(SRC, rel)
        h = sha(os.path.join(d, rel)) if os.path.exists(ours) else "NOT-VENDORED".ljust(64)
        lines.append("%s  %s" % (h, rel))
    return "\n".join(lines) + "\n"


# --------------------------------------------------------------------------
# MI-PATCHES:  blank-line-separated records
#
#   patch: <id>            a deliberate divergence from the donor
#   file:  <path> [sha256] one per file the record covers; the hash is
#                          required for MI files and is the content the
#                          justification was written against
#   fix:   <one line>
#   why:   <one line>


def read_patches():
    recs = []
    cur = None
    with open(PATCHES) as f:
        for no, ln in enumerate(f, 1):
            if ln.startswith("#"):
                continue
            if not ln.strip():
                cur = None
                continue
            k, _, v = ln.partition(":")
            k, v = k.strip(), v.strip()
            if k == "patch":
                cur = {"kind": k, "id": v, "files": [], "fix": "", "why": "", "line": no}
                recs.append(cur)
            elif cur is None:
                sys.exit("%s:%d: field outside a record" % (PATCHES, no))
            elif k == "file":
                p = v.split()
                cur["files"].append((p[0], p[1] if len(p) > 1 else None))
            elif k in ("fix", "why"):
                cur[k] = (cur[k] + " " + v).strip()
            else:
                sys.exit("%s:%d: unknown field %r" % (PATCHES, no, k))
    return recs


def gen_table(recs):
    head = ("File", "Fix", "Why it is native-correct")
    rows = ["| %s |" % " | ".join(head), "|" + "---|" * len(head)]
    for r in recs:
        files = ", ".join("`%s`" % p for p, _ in r["files"])
        rows.append("| %s | %s | %s |" % (files, r["fix"], r["why"]))
    return "\n".join(rows)


def splice(text, tag, body):
    b, e = BEGIN % tag, END % tag
    i, j = text.find(b), text.find(e)
    if i < 0 or j < 0:
        sys.exit("%s: missing %s markers" % (TABLE, tag))
    return text[: i + len(b)] + "\n" + body + "\n" + text[j:]


def rendered(recs):
    with open(TABLE) as f:
        text = f.read()
    return splice(text, "BAKED", gen_table(recs))


# --------------------------------------------------------------------------


def check():
    bad = []

    def fail(msg):
        bad.append(msg)
        print("MI: " + msg)

    base = read_baseline()
    recs = read_patches()
    d = donor()

    # Justification index: file -> the record covering it.
    cover = {}
    for r in recs:
        if not r["fix"] or not r["why"]:
            fail("%s: record `%s' has no fix:/why: -- a justification that says"
                 " nothing is not a justification" % (PATCHES, r["id"]))
        for p, h in r["files"]:
            cover.setdefault(p, []).append((r, h))

    ours = mifiles(SRC)

    # Direction 1, tree -> record.  A gate walked only rows -> tree can never
    # see an unlisted item; this is the direction that catches a new file.
    for rel in ours:
        if rel not in base:
            fail("%s is in a machine-independent directory and not in the donor."
                 " New MI files are the thing the rule forbids; put it in the"
                 " machine layer." % rel)

    # Direction 2, record -> tree, plus the divergence verdict per file.
    for rel, want in sorted(base.items()):
        path = os.path.join(SRC, rel)
        here = os.path.exists(path)
        if want == "NOT-VENDORED":
            if here:
                fail("%s is vendored but MI-BASELINE says NOT-VENDORED." % rel)
            continue
        if not here:
            fail("%s is in MI-BASELINE and missing from the tree." % rel)
            continue
        got = sha(path)
        recs_here = cover.get(rel, [])
        if got == want:
            for r, _ in recs_here:
                    fail("%s is byte-identical to the donor and MI-PATCHES still"
                         " claims a patch (`%s').  A row for a file that carries"
                         " no fix stops anyone looking." % (rel, r["id"]))
            continue
        # Divergent.
        if not recs_here:
            fail("UNDOCUMENTED DIVERGENCE %s -- differs from the donor with no"
                 " record in src/cc/MI-PATCHES.  Either revert it, or add a"
                 " record saying what the fix is and why it is correct on the"
                 " native C900, not merely why it builds on the host." % rel)
            continue
        for r, h in recs_here:
            if h is None:
                fail("%s: record `%s' names it without the hash it was written"
                     " against." % (rel, r["id"]))
            elif h != got:
                fail("%s has changed since record `%s' was written.  Re-read the"
                     " justification against the new text, and update the hash in"
                     " the same commit as the diff:\n         %s" % (rel, r["id"], got))

    # Records may name machine-layer files too (a fix that spans both sides);
    # those are outside the baseline, but they must at least exist.
    for p in cover:
        if p not in base and not os.path.exists(os.path.join(SRC, p)):
            fail("MI-PATCHES names %s, which does not exist." % p)

    # The published table is a rendering of the record, and a rendering that
    # has been edited is a second, disagreeing record.
    with open(TABLE) as f:
        if f.read() != rendered(recs):
            fail("docs/PATCHES.md is not what src/cc/MI-PATCHES renders to."
                 "  The tables are generated: edit MI-PATCHES and run"
                 " `make mi-table'.")

    # With the donor: is the baseline itself honest, and what actually differs.
    if d:
        want = gen_baseline(d)
        with open(BASELINE) as f:
            if f.read() != want:
                fail("MI-BASELINE does not match $MWC_DONOR.  Either the donor"
                     " tree is not the one it names, or the baseline was"
                     " hand-edited; `make mi-baseline' rewrites it.")
        for rel in sorted(base):
            p, o = os.path.join(SRC, rel), os.path.join(d, rel)
            if base[rel] == "NOT-VENDORED" or not os.path.exists(p):
                continue
            if sha(p) != base[rel]:
                n = subprocess.run(["diff", "-u", o, p], capture_output=True,
                                   text=True).stdout.count("\n@@")
                print("     %-16s %d hunk(s) vs the donor" % (rel, n))

    n = len(ours)
    div = sum(1 for r in ours if base.get(r) not in (None, "NOT-VENDORED")
              and sha(os.path.join(SRC, r)) != base[r])
    print("=== MI: %d files, %d identical to the donor, %d divergent%s"
          % (n, n - div, div, ", donor tree checked" if d else ""))
    if bad:
        print("=== %d problem(s); the machine-independent front end is not audited." % len(bad))
        return 1
    return 0


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "check"
    if what == "check":
        sys.exit(check())
    if what == "baseline":
        d = donor()
        if not d:
            sys.exit("mi-divergence: baseline needs $MWC_DONOR (a pristine MWC"
                     " 4.2.12 c/ tree: the one holding n0/ n1/ n2/ n3/ common/"
                     " h/ coh/)")
        with open(BASELINE, "w") as f:
            f.write(gen_baseline(d))
        print("wrote %s" % BASELINE)
        return
    if what == "table":
        text = rendered(read_patches())   # read the page BEFORE truncating it
        with open(TABLE, "w") as f:
            f.write(text)
        print("wrote %s" % TABLE)
        return
    sys.exit(__doc__)


main()
