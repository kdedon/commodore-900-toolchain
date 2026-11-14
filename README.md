# Commodore 900 toolchain

Mark Williams C compiler, assembler, and linker with a Zilog Z8001 target for
the Commodore 900. The tools emit segmented COHERENT `l.out` objects and
executables using 16-bit `int`, 32-bit `long`, and far pointers.

## Build and test

    make                  build the host cross-toolchain in host/build
    make check            run the regression suite
    make check-selfhost   verify the self-hosted compiler fixed point
    make check-native     compare native assembler/linker output
    make tools            build auxiliary conversion tools
    make env              stage a guest compiler environment
    make deps             fetch inputs listed in DEPS
    make clean
    make help

A normal build requires GCC and Python 3. Tests that execute Z8001 programs
also require `C900_EMU`; `make deps DEP=emu` installs the pinned emulator.

The main outputs are:

    host/build/z8001/cc0-z8001
    host/build/z8001/cc1-z8001
    host/build/z8001/cc2-z8001
    host/build/z8001/cc3-z8001
    host/build/as-z8001
    host/build/ld-z8001

`host/ccz` is the one-shot compiler driver. Linking a complete program also
requires headers, startup code, and libraries from the target environment.

## Stack-segment symbol

Generated code refers to the absolute symbol `SS` when it needs the stack
segment. Startup code must define it with the segment byte repeated:

        .globl SS
    SS = 0x3F3F

COHERENT user programs use `0x0000`; the kernel uses `0x3F3F`. Freestanding
programs must use the segment selected by their startup code.

## Long external names

An l.out symbol name is 16 bytes, the `_` cc appends included; cc2 warns
when it truncates one.  `ccz -VLNAME` (cc2 variant VLNAME, `as -N`,
`ld -N`) keeps names of up to 127 characters instead.  An object or image
that names a longer one sets `LF_LNAME` (02000) in `l_flag`; one that does
not is the same bytes as without the option.

In an `LF_LNAME` file a name of 16 characters or fewer is in `ls_id` as
before.  A longer one has `ls_id[0]` zero and, in `ls_id[4..7]`, the offset
of the name in a string table that follows `L_REL`: a header-order long
holding the table's size, its own four bytes included, then NUL-terminated
names.  An archive index naming a long symbol starts with a marker entry
(`ar_id[1]` 1, `ar_off` the table's offset in `__.SYMDEF`) and ends with the
same kind of table (`<ar.h>`).  Names past 127 characters are cut there,
with cc2's warning.

`ld` refuses an `LF_LNAME` input without `-N`, and refuses long names in a
shared library or a program that uses one, whose export and import records
the kernel reads at 16 bytes; `slgen` refuses `LF_LNAME` objects.  ld, ar,
loutid and loutdis read both forms; `nlist()` reads both and finds names of
up to 16 characters.  COHERENT's own tools (nm, size, strip, db, and ld and
ar built before this format) do not read `LF_LNAME` files; files without
long names are unaffected.

## Optional inputs

| Variable | Used for |
|---|---|
| `C900_EMU` | tests that execute Z8001 binaries |
| `COHERENT_OS` | libc, native/self-hosted tools, and guest environments |
| `MWC_DONOR` | comparison with pristine MWC sources |
| `Z8001_DONOR` | broad compiler corpus tests |
| `C900_TC_BUILD` | alternate build directory, for the build and for a consumer reading it |

## License

Project-authored code is MIT licensed. The Mark Williams COHERENT sources are
BSD 3-Clause. Other historical material remains under its original terms. See
`LICENSE` and notices in the source.
