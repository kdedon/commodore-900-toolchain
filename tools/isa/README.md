# ISA inventory — the decoder's own account of the Z8000

**Provenance:** produced by `genz8001tab` by driving a **verified decoder**
exhaustively over the entire 16-bit opcode space (segmented mode). Every byte
here comes from the same decoder the emulator's reference model executes — no
transcription, no reverse-engineering, and **not** from the faulty
`Z8000_instruction_encodings.md`.

**The generator is not in this repository** and cannot be run from it: it reads
a decoder that is not public. These files are committed artifacts, checked
against each other by the gates below, and the compiler compiles them as they
stand.

Nothing in this directory is compiled. It is the ISA reference the encoder was
built *from* and is checked *against*. The tables the compiler actually compiles
are `src/cc/generated/{opcode.h,OF_styles.h}` — one copy, next to the source
that includes them.

## Files

- **`OPCODE_INVENTORY.md`** — **514** `(mnemonic, operand-shape)` groups over
  **162** distinct mnemonics. Per group: `base` (the opcode skeleton = bits
  fixed across the group, operand fields zeroed), `varmask` (bits that vary =
  the operand/register/CC fields), word count, cycles, encoding count, and a
  decoded example. The file's own header line carries these two counts; it is
  generated, so read them there rather than trusting this paragraph.
- **`PST_CROSSCHECK.md`** — diff of the inventory against MWC's own assembler
  opcode table, `src/as/z8001/pst.c` (via `check_pst.py`). **Result: 155
  matched, 0 mismatches** (149 exact, 6 via the register-form bit `pst|0x8000`),
  plus 2 placeholders — `LDM` and `ADDB`, whose pst.c base is 0x0000 because
  machine.c builds the opcode. Locks the three-way agreement: verified sim
  decoder · its own `OPCODE_VERIFICATION.md`, in a checkout that is not part
  of this repository ·
  MWC assembler. `make check-isa` asserts the committed artifact still says
  exactly this.
- **`optab.c`** — DRAFT n2/z8001 opcode table: each `src/cc/generated/opcode.h`
  row → `{ OF_style, base, flags }`, base = authentic `pst.c` form-0 opcode,
  style by operand-shape cluster, `OP_BYTE`/`OP_DWORD` by width. Codegen-critical
  families assigned confidently; 53 block/IO/privileged ops are
  `OF_ASMONLY`/`OF_IO` (not C-emitted) and flagged for review. **This is not
  `src/cc/n2/z8001/optab.c`** — that is the cc2 OPINFO table the compiler links;
  this is the decoder inventory rendered as C.

## Scripts

- **`check_pst.py`** — the cross-check above. Bare, it writes
  `PST_CROSSCHECK.md` and exits nonzero on any real mismatch. With `--check` it
  writes nothing and asserts the committed artifact is byte-for-byte what it
  would produce, so a hand-edit or a stale commit fails too. `make check-isa`
  runs `--check`, which asserts rather than writes.
- **`gen_optab.py`** — generates `src/cc/generated/OF_styles.h` + `optab.c` here
  from the inventory + `pst.c`, and — when a `c900oses/gotools` tree is
  reachable (`$C900_GOTOOLS`) — `cmd/rt_z8001/inv_data.go` there (every
  `(mnem, shape, base, varmask, style)` row: the data the round-trip driver
  consumes). Without that tree it writes the C outputs and says out loud that
  it skipped the Go one; `rt_z8001` needs a decoder this repository has not
  got. It reads MWC's `pst.c` from `src/as/z8001/`; before the split it
  read a donor checkout that is not part of this repository, which is why that
  path had to be repointed at the assembler this repo ships.

## How to read an inventory row

`ADD | R,R | base 0x8100 | varmask 0x00FF` means: register-register `ADD` has
opcode skeleton `0x8100` with the source register in bits 7-4 (nib2) and the
destination in bits 3-0 (nib3) — exactly the Z8000 general format
`10|opcode|W|src|dst`. The addressing form is encoded in the **hi nibble** of the
opcode byte: `0x8X` = register, `0x0X` = immediate/IR (`@R`), `0x4X` = direct/
indexed (`DA`/`X`), `0x5X`/`0x1X` = the long/addressed escape groups. The
assembler's `asm.c` maps the compiler's internal `A_*` mode to these.

## Known inventory artifacts (first-cut; harmless)

- **Branch/return condition codes** appear as one group per cc (`JR EQ`, `JR F`,
  …, 16 each) because the shape abstractor does not fold cc names. This is fine —
  it directly exposes the cc field encoding; `optab.c` collapses them to one row
  with the cc in `varmask`.
- A few **empty-shape rows** (`COM `` `, `NEG `` `, `PUSH `` `) are
  addressed-operand forms where the probe words produced no formatted operand;
  cross-check the matching non-empty row.
- `DIV` cycle counts show a worst-case figure from the decoder; not used by the
  opcode table.
