# coff2elf + libcoh-linux — the x86-target host-link bridge

Converts a Coherent i386 COFF object into an ELF32 one that gnu `ld` can link
and the development host can run.

**This is a standalone tool with no consumer in this repository.** It was written
for an i386 reference harness that host-built the *donor's* i386 compiler out of
`$MWC_DONOR`; that harness has been deleted (it required a private holding, and
because it compiled the donor's back end rather than `src/cc`, it could not test
this tree's code generator). There is no i386 back end under `src/cc`. What
remains here is self-contained: `make` and `make test` need only gcc with `-m32`.
The sections below describe the pipeline it was built for, in which the format
conventions it encodes were established.

```
MWC i386 cc2 (donor n2/i386/outcoff.c)      <-- emits Coherent i386 COFF (magic 0x14C)
        |  *.coff
        v
   coff2elf [-u]                            <-- THIS TOOL: COFF32 -> ELF32 (ET_REL, EM_386)
        |  *.o (ELF)
        v
   ld -m elf_i386  +  crt0.o + libcoh       <-- gnu ld links against libcoh-linux
        |
        v
   a 32-bit ELF that runs natively on x86-64 Linux (ia32)
```

## Pieces
- **`coff2elf.c`** — the converter. K&R C, **self-hosting**: it builds under the
  host `cc` (LP64) during bootstrap *and* under the MWC i386 compiler (ILP32) at
  self-host. Reads COFF strictly by little-endian byte offsets (never struct
  overlay), so it is word-size-portable. Maps `.text`/`.data`/`.bss`, the COFF
  symbol table (section + local + global), and relocations
  `R_DIR32→R_386_32`, `R_PCRLONG→R_386_PC32`. `-u` strips one leading underscore.
- **`libcoh/crt0.s`** — i386 Linux `_start`: calls `main(argc,argv)`, turns its
  return into `exit(2)`. The minimal "own OS interface."
- **`libcoh/sys.s`** — i386 Linux syscall stubs (`write`/`read`/`_exit`, `int
  0x80`): the bottom of the Coherent libc retargeted to Linux. (T1 subset.)
- **`mkfix.c`** — test-only fixture generator (emits a minimal valid i386 COFF
  object); not part of the shipped toolchain.

> The `.s` files are in **GNU as (AT&T)** syntax, assembled by the host toolchain.
> `coff2elf.c` itself is K&R C that also compiles under an ILP32 Coherent compiler.

## Build & test
Built by the repository's own Makefile, into `$C900_BUILD/tools`:
```
make tools            # coff2elf, mkfix (and lout2cpm)
make libcoh           # crt0.o + libcoh.a; needs a 32-bit gcc
make check-coff2elf   # COFF fixture -> coff2elf -> ld + crt0 -> run; assert results
```

## Why COFF, not l.out
The i386 target's writer is the donor's `n2/i386/outcoff.c` (`.prof.386` sets
`OUTPUT=outcoff.o`) — **COFF**, 32-bit. The classic `l.out` (`outcoh.c`) is the
**16-bit 286** path (`unsigned short` addresses) and cannot represent a 32-bit
program. COFF↔ELF are both section+symtab+reloc formats, so the bridge is clean.
