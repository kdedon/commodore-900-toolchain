# commodore-900-toolchain

A C compiler, assembler and linker targeting the **Zilog Z8001** as fitted to the
**Commodore 900**. It emits COHERENT `l.out` objects and executables, in the
segmented (`VLARGE`) memory model, for a machine with 16-bit `int`, 32-bit
`long`, far pointers and no floating-point unit. 

**Lineage.** The machine-independent passes, the assembler and the linker derive
from Mark Williams Company COHERENT 4.2.12, released under BSD 3-Clause by
Robert Swartz in 2015. The Z8001 machine layer is new work. 

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
    make env                    a COMPILER ENVIRONMENT: a directory tree a GUEST compiles
                                from.  CCENV selects which compiler (ours, inherited,
                                mwc1985); see docs/ENVIRONMENTS.md.  Needs $COHERENT_OS.
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

## Releases

`VERSION` holds `MAJOR.MINOR.PATCH`, and the number is a statement about
codegen, not about the interface: **PATCH cannot change an emitted byte**, MINOR
means the compiler's output moved, MAJOR means the contract did (calling
convention, `l.out` layout, driver options). A consumer pinning a version is
pinning codegen. The PATCH promise is checked rather than asserted —
`host/check-patch-bump.sh` compares the fixed point's 86 objects against the
previous tag's and the release refuses to publish a PATCH bump whose objects
moved.

A `v*` tag publishes three deliverables — a Linux archive and a Windows archive,
each carrying the host compiler *and* the native Z8001 one, and the native
binaries on their own for a consumer who wants nothing else — plus a fourth
asset, `-codegen.tar.gz`, which is not a deliverable but the evidence the next
release's PATCH check compares against. An unpacked archive is self-contained:
`bin/ccz` finds its passes, its libc and its headers inside the archive, with no
OS tree and no variables set.

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

An object with no frame references never asks for it. Everything already in
these repositories does, one way or another:

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
unpacked into a gitignored `deps/`; our own repositories are cloned as siblings
and left floating on their branch. It is not another way to *find* things — it
puts them where `host/deps.sh` already looks, so setting `C900_EMU` or
`COHERENT_OS` by hand works exactly as before and still wins.

The COHERENT edge is marked `local`, which means it is not published and there
is nothing to fetch: `make deps` says so and exits nonzero, naming the variable.
Nothing the toolchain itself needs is behind it — **`make` and `make check` need
only the emulator**, which `make deps DEP=emu` places. What is behind it is the
handful of targets that build *OS artifacts* with this compiler (`make libc`,
`native`, `selfhost`, `check-selfhost`, `env`) and, therefore, a release: an
archive carries `usr/include` and the Z8001 libraries, and `host/release-pack.sh`
refuses to pack one without recording the COHERENT commit they came from. A
*released* toolchain needs no OS tree at all — that is the point of shipping
them.

| input | variable | who needs it |
|---|---|---|
| the [emulator](https://github.com/MichalPleban/commodore-900-emulator), which RUNS compiled code | `C900_EMU` | `make check` and every gate in `tests/` that executes its output (`host/runner.sh` → `host/deps.sh`; also `deps/`, `$PATH`, or a sibling checkout bounded at three parents) |
| `c900oses/gotools`, which holds the Go instruments — including `loutdis`, the `l.out` disassembler | `C900_GOTOOLS` | **no gate**: the side harnesses only (`tests/disdiff.sh`, `codesize.sh`, `effdiff*.sh`, `segrun.sh`, `segexec.sh`, `check.sh dis`), through `host/loutdis.sh`. Those tools import the private `c900`/`z8000` simulator checkouts, which is exactly why they are not here; `make check` reaches for none of it, and neither does anything under `src/` |
| a COHERENT source tree | `COHERENT_OS` | `host/build-libc-z8001.sh`, `build-libm`, `build-libmisc`, `build-selfhost.sh`, `ccz`'s default include path, `make env` |
| pristine MWC 4.2.12 | `MWC_DONOR` | `make check-mi` alone, which diffs `src/cc`'s MI files against the donor's and requires a `docs/PATCHES.md` row for each difference. No other target reads it |
| the Coherent 0.7.3 userland corpus | `Z8001_DONOR` | the sweep and efficiency gates: `objsweep.sh`, `disdiff.sh`, `effdiff*.sh`, `asan_frontend.sh`, `segrun.sh`, and `tests/check.sh` which runs them all |

`make check` runs `tests/regress.sh`, which compiles each case through the whole
shipped pipeline (cc0 → cc1 → cc2 → ld) and **executes the linked binary**.
`tests/cc2run.sh` and `tests/float-e2e.sh` are the other two gates that run
without a donor corpus.

libc is the OS's property — it makes syscalls — so it stays there. The
soft-float routines are the *compiler's* runtime (cc1 lowers `a + b` on doubles
into `CALL dladd`) and are vendored at `tests/rt/`; that copy can drift from the
OS tree's, and `tests/rt/README.md` records it.
