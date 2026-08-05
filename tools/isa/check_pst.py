#!/usr/bin/env python3
"""Cross-check the decoder-generated opcode table against MWC's own Z8001
assembler opcode table (cmd/as/z8001/pst.c).

Locks in the three-way agreement: the verified sim decoder (-> generated/
OPCODE_INVENTORY.md), OPCODE_VERIFICATION.md, and the MWC assembler (pst.c).

For each instruction mnemonic in pst.c, pst.c carries ONE base opcode (the
@R/immediate "form-0" encoding; the assembler ORs the addressing-mode hi-nibble
0x80=reg / 0x40=DA at assemble time). So the check is: pst_base must appear among
the set of `base` values the inventory lists for that mnemonic's shapes.

Writes PST_CROSSCHECK.md beside this script and exits nonzero on any real
mismatch (mnemonic present in both, pst base NOT among the inventory bases).

With `--check' it writes nothing and instead asserts that the COMMITTED
PST_CROSSCHECK.md is byte-for-byte what this script would produce today.  That
is the second thing this gate has to catch: not only a decoder/pst.c
disagreement, but a committed artifact that no longer matches its generator.
The two had in fact drifted -- the artifact carried a separator character the
generator did not emit -- and the writing mode could never have reported it,
because it overwrote the evidence before anyone could look at it.  `make
check-isa' runs `--check'.
"""
import re, sys, pathlib

CHECK_ONLY = "--check" in sys.argv[1:]

HERE = pathlib.Path(__file__).resolve().parent          # tools/isa
ROOT = HERE.parent.parent
GEN  = HERE / "OPCODE_INVENTORY.md"
# pst.c: MWC's own opcode table, in the assembler this repo ships.
PST  = ROOT / "src" / "as" / "z8001" / "pst.c"
OUT  = HERE / "PST_CROSSCHECK.md"

# ---- parse pst.c instruction rows: { flag, "name", S_FMT, mod, E_class, val } ----
# instruction rows: name not starting with '.', format != S_REG, value is the opcode.
pst_row = re.compile(
    r'\{\s*[^,]+,\s*"([^"]+)"\s*,\s*(S_\w+)\s*,\s*([^,]+),\s*(E_\w+)\s*,\s*'
    r'(0x[0-9A-Fa-f]+|\d+)\s*\}')
pst = {}          # MNEM -> (base, S_fmt, modifier)
pst_dups = {}
for m in pst_row.finditer(PST.read_text()):
    name, sfmt, mod, eclass, val = m.groups()
    if name.startswith('.') or sfmt == 'S_REG':
        continue                          # directive or register, not an instruction
    base = int(val, 0)
    MN = name.upper()
    pst.setdefault(MN, (base, sfmt, mod.strip()))
    pst_dups.setdefault(MN, set()).add(base)

# ---- parse the generated inventory: | MNEM | `shape` | `0xBASE` | ... ----
inv_row = re.compile(r'^\|\s*([A-Z0-9]+)\s*\|\s*`([^`]*)`\s*\|\s*`0x([0-9A-Fa-f]+)`')
inv = {}          # MNEM -> set(base)
inv_shapes = {}   # MNEM -> [(shape, base)]
for line in GEN.read_text().splitlines():
    m = inv_row.match(line)
    if not m:
        continue
    MN, shape, base = m.group(1), m.group(2), int(m.group(3), 16)
    inv.setdefault(MN, set()).add(base)
    inv_shapes.setdefault(MN, []).append((shape, base))

# ---- compare ----
# pst.c stores the "form-0" base; machine.c ORs the addressing-mode hi-nibble at
# assemble time: 0x8000 = register-direct, 0x4000 = direct-address (DA). So a pst
# base matches if {base, base|0x8000, base|0x4000} intersects the inventory set.
FORMS = [(0x0000, "exact"), (0x8000, "+reg(0x80)"), (0x4000, "+DA(0x40)")]
matched, mismatched, pst_only, special = [], [], [], []
for MN, (base, sfmt, mod) in sorted(pst.items()):
    if MN not in inv:
        pst_only.append((MN, base, sfmt))
        continue
    if base == 0:                         # placeholder; opcode built specially in machine.c
        special.append((MN, base, sfmt, sorted(inv[MN])))
        continue
    hit = next(((base | bit) for bit, _ in FORMS if (base | bit) in inv[MN]), None)
    how = next((tag for bit, tag in FORMS if (base | bit) in inv[MN]), None)
    if hit is not None:
        matched.append((MN, base, hit, how, sfmt))
    else:
        mismatched.append((MN, base, sfmt, sorted(inv[MN])))
inv_only = sorted(set(inv) - set(pst))

# ---- report ----
lines = ["# pst.c <-> generated inventory opcode cross-check\n",
    "Three-way agreement check: verified sim decoder (generated table) vs MWC's",
    "own Z8001 assembler opcode table `cmd/as/z8001/pst.c`. A pst.c base must",
    "appear among the inventory's `base` values for that mnemonic (the assembler",
    "ORs the addressing hi-nibble 0x80/0x40 at assemble time).\n",
    f"- mnemonics in pst.c (instructions): **{len(pst)}**",
    f"- mnemonics in generated inventory: **{len(inv)}**",
    f"- **matched: {len(matched)}**  ·  **mismatched: {len(mismatched)}**  ·  "
    f"special(placeholder): {len(special)}  ·  pst-only: {len(pst_only)}  ·  "
    f"inventory-only: {len(inv_only)}\n"]

if mismatched:
    lines.append("## MISMATCHES (pst base not among inventory bases, any form)\n")
    lines.append("| mnemonic | pst.c base | pst fmt | inventory bases |\n|---|---|---|---|")
    for MN, base, sfmt, ibases in mismatched:
        lines.append(f"| {MN} | `0x{base:04X}` | {sfmt} | " +
                     ", ".join(f"`0x{b:04X}`" for b in ibases) + " |")
    lines.append("")

if special:
    lines.append("## Special (pst base = 0x0000 placeholder; opcode built in machine.c)\n")
    lines.append("| mnemonic | pst fmt | inventory bases |\n|---|---|---|")
    for MN, base, sfmt, ibases in special:
        lines.append(f"| {MN} | {sfmt} | " +
                     ", ".join(f"`0x{b:04X}`" for b in ibases) + " |")
    lines.append("")

lines.append("## Matched (pst base found in inventory; form = bit machine.c ORs in)\n")
lines.append("| mnemonic | pst base | inv base | form | pst fmt (-> optab OF_*) |\n|---|---|---|---|---|")
for MN, base, hit, how, sfmt in matched:
    lines.append(f"| {MN} | `0x{base:04X}` | `0x{hit:04X}` | {how} | {sfmt} |")

if pst_only:
    lines.append("\n## pst.c-only (assembler mnemonics not in the codegen inventory)\n")
    lines.append("Mostly privileged/IO/block ops the C codegen never emits.\n")
    lines.append(", ".join(f"`{MN}`" for MN, _, _ in pst_only))
if inv_only:
    lines.append("\n## inventory-only (decoder mnemonics not named in pst.c)\n")
    lines.append(", ".join(f"`{MN}`" for MN in inv_only))

report = "\n".join(lines) + "\n"
print(f"pst.c instructions: {len(pst)} | inventory: {len(inv)} | "
      f"matched: {len(matched)} | mismatched: {len(mismatched)} | "
      f"pst-only: {len(pst_only)} | inv-only: {len(inv_only)}")

stale = False
if CHECK_ONLY:
    committed = OUT.read_text() if OUT.exists() else None
    if committed is None:
        print(f"MISSING: {OUT} is not present; run without --check to write it",
              file=sys.stderr)
        stale = True
    elif committed != report:
        import difflib
        print(f"STALE: {OUT} is not what check_pst.py produces today.",
              file=sys.stderr)
        for d in difflib.unified_diff(committed.splitlines(True),
                                      report.splitlines(True),
                                      fromfile="committed", tofile="generated"):
            sys.stderr.write(d)
        print("Run `python3 tools/isa/check_pst.py' to regenerate, and commit it.",
              file=sys.stderr)
        stale = True
    else:
        print(f"{OUT.name} is up to date")
else:
    OUT.write_text(report)
    print(f"wrote {OUT}")

if mismatched:
    print("MISMATCHES:", file=sys.stderr)
    for MN, base, sfmt, ibases in mismatched:
        print(f"  {MN} pst=0x{base:04X} fmt={sfmt} inv={[hex(b) for b in ibases]}",
              file=sys.stderr)
if mismatched or stale:
    sys.exit(1)
