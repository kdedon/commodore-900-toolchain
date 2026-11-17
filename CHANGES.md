# Changes

## v0.2.0 (2026-11-16)

Objects from v0.1.9 still link, but rebuild them to pick up the code
generation fixes. `l.out` files and archives without long names are
unchanged.

### Packaging

- The host archives carry `src/libc`, `src/libm` and `src/include`, so
  Exec900 builds from a release. `make all` builds `host/build/mkarz`.
- CI runs every stage; the self-host and native tool stages no longer wait
  for an OS snapshot.

### Language

Features above K&R are additions: K&R code compiles to the same objects.

- Function prototypes and ANSI definitions, `switch` on `long`, `//`
  comments, declarations after statements and in `for`.
- C89 initializers: an automatic structure from a structure expression, an
  automatic array sized by its initializer, omitted members zeroed, an
  address cast to `long` as a static initializer.
- `&` of an array, and `offsetof()` as an integer constant expression.
- Language levels `-VKR`, `-VC89`, `-VC99`; `-VSTRICT` makes strict
  messages errors; `-VSVARG` warns of an `int` in a `...` slot. `ccz` reads
  a level from `CCZ_LEVEL`.
- At `-VC89` and `-VC99`, `readonly` and `alien` are identifiers and
  `unsigned char` promotes to `int`.
- `volatile` applies at the declarator level it is written at, and through
  typedefs.

### Wrong-code fixes

- `long` with `unsigned char`, `unsigned short` or `unsigned int` balances
  to `long`.
- `x /= y` and `x %= y` divide in the balanced type.
- A signedness-changing cast of `?:`, a comma or a float-to-integer
  conversion converts before widening.
- A function returning a `char` type narrows its value.
- A signed quotient converted to unsigned keeps its signed divide.
- A shift op-assign by a variable count keeps its count.
- A long times a widened short uses `MULTL`.
- cc2's copy deletion treats word `RL`, `SDL`, `SLL` and `LDCTL` as one-word
  writes, and no longer reads stale liveness marks.
- The copy into the return register the epilogue reads is kept.
- `DI` and `EI` act on VI and NVI.
- Several cc1 internal errors on pointer and byte casts, calls through
  computed addresses and byte constant arguments.
- cc0: macro arguments up to about 1400 characters; identifiers of 254 or
  more characters no longer overrun.

### Code generation

- Dense switches dispatch through a table of self-relative words.
- Peephole: loads pushed directly, redundant `EXTSB` dropped, memory
  `INC`/`DEC` folded, argument pops merged.
- Undeclared locals are promoted to registers in cc1.
- 16-bit products and quotients use one-word `MULT` and `DIV`.
- Signed `int` and `long` division by powers of two uses shifts; the
  remainder masks.
- cc2 shortens compares with zero, drops redundant `TEST`s and reuses a
  value already in a register, at no clock cost.

### Assembler, linker and tools

- `ld` relaxes long operands and `CALL`s in reach to short forms and `CALR`
  in `LF_RELAX` objects, which cc2 now emits, including calls from the
  bottom of an `-L` text segment.
- `ld` keeps every section of a segmented image inside one 64K segment.
- Long external names, opt-in: `ccz -VLNAME`, `as -N`, `ld -N`, up to 127
  characters, flagged `LF_LNAME`. cc2 warns when it truncates a name.
- `as`: `MREQ` encodes as `7BnD`; shift counts are range-checked; register 0
  is refused as a base; the object is removed on error. An object ending
  in an odd section holds its last pad byte, so `ld` no longer reads the
  next module a byte early.
- `loutdis`: its table is generated from the assembler's
  (`make loutdis-table`), and `tests/disround.sh` round-trips every form.
  It takes the header's byte order from `l_magic`, so a stripped image or
  an `LF_LNAME` object is no longer read big-endian, and counts code in
  `PRVI` as well as `SHRI`.
- cc2 objects with debug records read back correctly.
- Shared libraries take their exports from their objects.

### Libraries

- Soft-float add, subtract, multiply and divide round to nearest even, and
  are no slower than the truncating versions.
- `modf`, `floor` and `ceil` truncate correctly and keep the sign of zero.
- `memset`, `memcpy` and `memcmp` are in assembly.
- `sbrk` returns `(char *)-1` on failure.
- `<sys/resource.h>` with `getrlimit` and `setrlimit`.

### Tests

- `check-libc` holds soft-float and integer arithmetic under instruction
  and clock ceilings (`fpcost.sh`, `fpcycles.sh`, `intcycles.sh`).
- New regression scripts cover each change above.
