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

## Optional inputs

| Variable | Used for |
|---|---|
| `C900_EMU` | tests that execute Z8001 binaries |
| `COHERENT_OS` | libc, native/self-hosted tools, and guest environments |
| `MWC_DONOR` | comparison with pristine MWC sources |
| `Z8001_DONOR` | broad compiler corpus tests |
| `C900_BUILD` | alternate build directory |

## License

Project-authored code is MIT licensed. The Mark Williams COHERENT sources are
BSD 3-Clause. Other historical material remains under its original terms. See
`LICENSE` and notices in the source.
