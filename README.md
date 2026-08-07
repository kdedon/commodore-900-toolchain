# commodore-900-toolchain

The **Mark Williams C compiler, assembler and linker from COHERENT 4.2.12**,
carrying a new **Zilog Z8001** machine layer for the **Commodore 900**. It emits
COHERENT `l.out` objects and executables in the segmented (`VLARGE`) memory
model, for a machine with 16-bit `int`, 32-bit `long`, far pointers and no
floating-point unit. MWC released 4.2.12 under BSD 3-Clause (Robert Swartz,
2015); the machine-independent passes, the assembler and the linker are theirs,
and everything under a `z8001/` directory is ours.

## Building, on a Linux host

    make                        cc0/cc1/cc2/cc3-z8001 + as-z8001 + ld-z8001 + tabgen
    make check                  the regression suite
    make check-isa              the opcode inventory against MWC's own assembler table
    make check-cc3tab           cc3's instruction table against cc2's
    make check-mi               every MI divergence from pristine MWC has a PATCHES.md row.
                                Needs $MWC_DONOR; skips loudly without it.
    make libc selfhost native   the NATIVE cc/as/ld: this compiler, compiled to
                                Z8001 by itself.  Needs $COHERENT_OS.
    make check-selfhost         the fixed point: run those target-built passes over
                                all 86 compiler sources and byte-compare the objects with
                                this build's.  The only check that can see a host workaround
                                which should have been part of the source.
    make check-native           RUN the native as and ld: their output against the host
                                tools' byte for byte, and a corrupt object against ld's
                                exit status.  The fixed point covers cc0/cc1/cc2 only.
    make env                    a COMPILER ENVIRONMENT: a directory tree a GUEST compiles
                                from.  CCENV selects which compiler (ours, inherited,
                                mwc1985); see docs/ENVIRONMENTS.md.  `ours' needs
                                $COHERENT_OS; the other two are composed over a library
                                and headers named by $C900_STOCK_ROOT.
    make deps                   acquire what DEPS says this repository consumes
    make clean

`make` needs gcc and python3 and nothing else, and consults nothing outside this
repository. Binaries land in `host/build/`: the compiler passes in
`host/build/z8001`, `as-z8001` and `ld-z8001` beside it. `host/ccz` is the
one-shot driver (`.c`/`.s`/`.o` in, linked `l.out` out), but it needs a libc —
see below.

`make check` additionally needs the emulator, which runs what it compiles;
`make deps DEP=emu` places it and nothing else is required to get a green
`731 passed, 0 failed`.

`src/cc/Makefile` builds the compiler on the C900 itself; the deliverable runs
on the machine, and the host cross-build exists for speed. Host-only workarounds
are *shims*, applied to a scratch copy by `host/build-cc.sh` and never committed
to `src/`; `docs/PATCHES.md` classifies each edit as BAKED or HOST SHIM.

## What a link must supply: `SS`

A Z8001 address word carries a segment, so every reference to a local or an
argument names the segment the stack is in. The compiler does not know it, and
does not choose it: `cc2` emits that byte as a **byte relocation against the
external symbol `SS`**, and the link states the value. `SS` is the only external
symbol `cc2` names on its own behalf.

Define it in whatever object carries your startup code, as an absolute with the
segment in **both bytes** — the byte relocated is the segment half of either the
one-word or the two-word address form:

        .globl  SS
    SS = 0x3F3F                 / a stack in segment 0x3F

An object with no frame references never asks for it. Everything that runs on
the machine does, one way or another:

| what you are linking | `SS` | where |
|---|---|---|
| a COHERENT program | `0x0000` | `csu/crts0.s`, in the OS tree |
| the COHERENT kernel | `0x3F3F` | `z8001/src/md.s`, in the OS tree |
| a loadable driver | — | resolved from the kernel's symbol table by `ld -k` |
| anything freestanding — a boot loader, a CP/M-8000 system image, a separately linked module | **yours to define** | your own `crt` |
| a CP/M-8000 transient program | — | not referenced: the `VTPA` variant emits the literal TPA segment, because such a program links against no runtime of ours |

Getting the *value* wrong does not fail the link. It compiles, links, reads,
and writes every local in the wrong segment, so take it from where your startup
code actually points the stack pointer.

## Inputs from outside this repository

The rule the split exists to enforce: **the toolchain does not depend on any
OS's headers, libraries or build system.** `make` holds to it. Everything else
is an input, each with a resolver script that names its variable and refuses
politely if it is missing.

`DEPS` states the two edges that are whole repositories, and `make deps`
acquires what it can: the emulator, which we do not build, is pinned by tag and
unpacked into a gitignored `external/`. It is not another way to *find* things —
it puts them where `host/deps.sh` already looks, so setting `C900_EMU` or
`COHERENT_OS` by hand works exactly as before and still wins.

The COHERENT edge is a **snapshot**: the few directories this repository
compiles, cut from that tree and published as a release of ours until the tree
itself is published. A checkout always wins over it — `host/deps.sh` searches
siblings first and `external/` last — and any build that does resolve to the
snapshot says so on stderr, naming the commit it was cut from and the date. That
is deliberate: "built against COHERENT as of some Tuesday" is the failure mode,
so it cannot happen quietly.

Nothing the toolchain itself needs is behind that edge — **`make` and `make
check` need only the emulator**, which `make deps DEP=emu` places. What is
behind it is the handful of targets that build *OS artifacts* with this
compiler: `make libc`, `native`, `selfhost`, `check-selfhost`, `check-native`,
`env`.

| input | variable | who needs it |
|---|---|---|
| the [emulator](https://github.com/MichalPleban/commodore-900-emulator), which RUNS compiled code | `C900_EMU` | `make check`, and every gate in `tests/` that executes what it compiles. Resolved by `host/runner.sh` → `host/deps.sh`: `external/`, `$PATH`, or a sibling checkout up to three parents away |
| a COHERENT source tree | `COHERENT_OS` | libc, libm, libmisc, `selfhost`, `native`, `ccz`'s default include path, `make env` |
| pristine MWC 4.2.12 | `MWC_DONOR` | `make check-mi` alone: it diffs `src/cc`'s MI files against the donor's and requires a `docs/PATCHES.md` row for each difference |
| the COHERENT 0.7.3 userland corpus | `Z8001_DONOR` | the sweep and efficiency gates — `objsweep.sh`, `asan_frontend.sh`, and `tests/check.sh`, which runs them all |

`C900_BUILD` moves the build directory, which defaults to `host/build`. A
consumer building against a checkout rather than a release archive sets it, so
that two of them do not share one tree.

`make check` runs `tests/regress.sh`, which compiles each case through the whole
shipped pipeline (cc0 → cc1 → cc2 → ld) and **executes the linked binary**.
`tests/cc2run.sh` and `tests/float-e2e.sh` are the other two gates that run
without a donor corpus.

libc is the OS's property — it makes syscalls — so it stays there. The
soft-float routines are the *compiler's* runtime (cc1 lowers `a + b` on doubles
into `CALL dladd`) and are vendored at `tests/rt/`; that copy can drift from the
OS tree's, and `tests/rt/README.md` records it.
