# Compiler environments — compiling ON the C900

An **environment** is a host directory tree holding everything needed to
compile on the target: the compiler passes, the driver, the assembler, the
linker, the archiver, the C library and the headers, all as **Z8001**
binaries, laid out in the guest paths they stand in for. A guest mounts it and
builds; the host edits it with `cp`.

```
make env                # the default environment, ours -> host/build/env/ours
make env CCENV=inherited
make env-mwc1985
```

This repository produces environments. The OS repositories **consume** them:
they locate one through `$C900_TOOLCHAIN`, the variable they already use to
find the compiler, and vendor nothing. The emulator publishes only itself and
is located the way `host/runner.sh` locates it (`$C900_EMU`, then `$PATH`,
then siblings).

## Why a directory and not a disk image

Because host mapping works on the filesystem. The guest sees the tree through
a mount; the host updates it in place and the next guest run sees the change,
with nothing repacked. An image would have to be rebuilt for every compiler
fix, and would be a second artifact to keep in step with the first.

## The layout, and why it is that shape

```
host/build/env/ours/
    bin/   cc as ld ar
    lib/   cc0 cc1 cc2 crts0.o libc.a
    usr/include/   ...156 headers, sys/ and netinet/ included
    CCENV          one line naming whose compiler this environment holds
```

It mirrors guest paths because the driver looks its parts up **by path**, not
by adjacency (`src/cc/coh/cc.c`):

| part | how `cc` finds it |
|---|---|
| `cc0` `cc1` `cc2` | P_LIB: searched on `LIBPATH`, default `/lib:/usr/lib` |
| `crts0.o` | P_LIB, under exactly that name (`pass[CRT].p_pln`) |
| `libc.a` | P_LIB; `makelib()` composes `"lib" + "c" + ".a"` |
| `as` `ld` | P_BIN: searched on `PATH`, default `:/bin:/usr/bin` |

`ar` is not a compiler pass, but a build that makes a library needs it and the
guest this serves is minimal on purpose, so it ships here.

### `mwc1985` carries more, because it is the **system** compiler

`ours` and `inherited` are userland compiler environments and `usr/include` is
all they need. The 1985 binaries are also what the kernel, the loadable
drivers and the boot ROM were built with, and those name the kernel headers by
absolute guest path — `cc -I/usr/sys/z8001/h`, with `<../../h/…>` reaching
across into `/usr/sys/h`. So `mwc1985` carries three trees, not one:

```
host/build/env/mwc1985/
    bin/   cc ccx as ld nld ar nm size
    lib/   cpp cc0 cc1 cc2 cc3 crts0.o libc.a
    usr/include/        59 headers
    usr/sys/h/          31 headers    the kernel's own
    usr/sys/z8001/h/    24 headers    the Z8001 machine tree
    VARIANT             the variant word each kind of artifact is compiled with
    CCENV
```

and two files the others do not:

* **`nld`** — `cc2` emits the 32-bit object format (`l_flag` carries `LF_32`),
  and `nld`, not `ld`, is the loader for it. A consumer linking what these
  passes produced needs it, and it survives nowhere else either.
* **`VARIANT`** — the bit-vector word `cc0`/`cc1`/`cc2` must be run with, per
  kind of artifact, with the evidence for each written beside it. It is a
  property of *these binaries*, so it travels with them: a consumer that
  unpacked a dist has no `vendor/mwc-1985` to read it out of, and the wrong
  word silently produces objects that are not the ones the machine shipped.
  `commodore-900-bios` keeps its own copy of it beside its own copy of them,
  for the same reason.

The asymmetry is the difference between the two jobs, not an omission from
`ours`.

**The three trees are not vendored here.** A C library, a C runtime startoff
and kernel headers are a 1985 *system*, and nothing in this repository compiles
against them; `commodore-900-bios` holds its own copy beside its own copy of
these tools, and reproduces the V1.0 boot ROM byte for byte from a clone and an
emulator. So composing `mwc1985` means naming a root:
`C900_STOCK_ROOT=…/commodore-900-bios/vendor/mwc-1985` for the 1985 originals,
or a built COHERENT staging root for a later library under the same passes.

## Using it from the guest

Mounted at `/mnt`, nothing is where `cc` looks. Two ways, both real:

**1. Point the driver at the mount.** `-t` names the passes to relocate and
`-B` gives the search list they are taken from; `path(3)` takes a colon list,
so one `-B` covers both directories:

```
cc -t012sdlr -B/mnt/env/bin:/mnt/env/lib -I/mnt/env/usr/include -c x.c
```

`-t012sdlr` = cc0, cc1, cc2, as(`s`), ld(`d`), libc(`l`), crts0.o(`r`).
Nothing is installed and the guest disk is not written to except for the
output and `/tmp`. This is the invocation the tests use and the one that has
been run end to end.

**2. Install it.** Copy `bin/*` to `/bin`, `lib/*` to `/lib` and
`usr/include` to `/usr/include`, after which the stock `cc x.c` works with no
options at all. Do this on a system whose `/usr` is on the ROOT filesystem —
`os/dist/media/hd21-build.media` in the COHERENT repository is laid out that
way precisely so that headers installed single-user are not hidden when
`/etc/rc` mounts a separate `/usr` over them.

`/tmp` must exist and be writable: `cc` puts its intermediates there
(`tempnam(3)`, `P_tmpdir`).

## The environments, and what `CCENV` is not

An environment is a (compiler, C library, headers) triple. The tree's shape is
the same for all of them, which is the point of having a table rather than a
script per flavour.

| `CCENV` | compiler | library + headers |
|---|---|---|
| `ours` | this repository's, built for the target: the `cc0/cc1/cc2` self-host fixpoint (`build-selfhost.sh`) + driver/assembler/linker (`build-native.sh`) | the extended COHERENT tree at `$COHERENT_OS` |
| `inherited` | the COHERENT tree's own — the Mark Williams lineage as that tree builds and installs it — taken from a stock staging root | that same root |
| `mwc1985` | `vendor/mwc-1985` — the original Mark Williams driver, `as`, `ld`, `nld`, `ar` — plus the passes (`cpp cc0 cc1 cc2 cc3`), which survive only in a `commodore-900-coherent` checkout's `src/dist/lib` | `$C900_STOCK_ROOT`: `commodore-900-bios/vendor/mwc-1985` for the 1985 originals, or a stock root |

**`CCENV` selects a compiler. It is not the OS tree's dist axis.** A dist name
in `commodore-900-coherent` (`stock`, `extended`) says what an owner of a real
Commodore 900 wants **installed**; `CCENV` says **whose compiler** stages this
environment. The table above is the proof that the two are independent:
`inherited` and `mwc1985` take their C library and their headers from the *same*
staging root — one installed system — and differ only in whose compiler binaries
sit beside them, so no dist name can tell them apart. In the other direction,
`CCENV` cannot distinguish `extended-hr` from `extended-lr`. Do not try to make
one axis serve for the other, and do not reuse a name across them.

Neither namespace may encode a release number. That is why these are `ours` and
`inherited` and not `coh35` and `coh08`: those were named for COHERENT 3.5 and
0.8, the trees moved, and the names then described nothing. The release number
lives in exactly one file per system in the OS tree (`src/VERSION`,
`os/hostbuild/VERSION`) and is resolved at build time. `mwc1985` keeps its date
because it names a **third party's** artifact — the 1985 Mark Williams release —
which is a fact that cannot rot, not a claim about what this tree currently is.

`ours` is built from source here and `make env` chains its prerequisites.
`inherited` is **selected** from a tree built elsewhere and takes that root as an
input: `C900_STOCK_ROOT=/path/to/commodore-900-coherent/build/root`.
`build-env.sh` refuses with one line naming the variable rather than guessing at
a sibling checkout. `mwc1985` is selected the same way and takes **two** inputs
from elsewhere: `$C900_STOCK_ROOT` for the library, the startoff and the three
header trees, and a `commodore-900-coherent` **checkout** for the passes
(`C900_MWC1985_PASSES` overrides), because `src/dist/lib` is the only place
those exist and the OS-source snapshot does not carry it.

One wrinkle in `mwc1985`: its `cc` is a two-line shell script that execs
`/bin/ccx` by **absolute** path, so it must be installed into the guest's own
`/bin` rather than run from a mount point.

## The two fallback dists

`make env-fallback` tars the composed `ours` and `mwc1985` roots into release
assets (`host/pack-fallback.sh`), and every root carries `.provenance` naming
the commits it was composed from. Consumers place them with their own `make
deps` and compile with them: no toolchain checkout, no OS checkout, no compiler
build.

`ours` is the one with consumers. `mwc1985` was cut for `commodore-900-bios`,
which now vendors the 1985 tools and the 1985 system itself and fetches
neither; nothing else places it. It is still cuttable — `make env
CCENV=mwc1985 C900_STOCK_ROOT=…` then `make env-fallback` — and is kept
against a second consumer wanting the 1985 compiler without a checkout.

`host/pack-fallback.sh` refuses to pack a root that is not a working compiler,
and for `mwc1985` it also requires `bin/nld`, `VARIANT`, `usr/sys/h` and
`usr/sys/z8001/h` — so a dist that cannot build a system artifact cannot be
cut.

**The tag is mutable by design.** `fallback-N` is re-cut in place rather than
renumbered, so it names the **role** and two roots carrying one tag need not
hold the same bytes. What tells them apart is the `toolchain <commit>` line in
`.provenance`, which is why a dirty tree is refused. Two consequences a
consumer lives with: `make deps` leaves an already-unpacked dist alone, so a
machine or CI cache holding an earlier cut keeps it silently — `rm -rf
external/<name>` forces the new one — and a CI cache keyed on the tag should not
exist.

**Exactly two, and never a third.** This is the bootstrap for the
toolchain ↔ OS cycle while `commodore-900-coherent` is unpublished. The images
belong in that repository's dist package permanently — it owns `libc`, `csu` and
the headers — and when it ships one, this pair is frozen and each consumer
repoints one `DEPS` line. A third dist here is a deliberate edit to
`pack-fallback.sh`, not a parameter.

## Verification: the binaries are checked, not assumed

Every host build harness in this repository also runs the host compiler, and
the failure that matters is a host binary reaching a tree the guest will
execute — it mounts, it lists, and it fails inside the guest with a bad magic
number. So `build-env.sh` ends by running `host/loutid.py -m z8001` over every
file in `bin/` and `lib/`, which reads the l.out header's machine field
(`include/mtype.h` `M_Z8001`) and exits nonzero on anything else, ELF
included. Archives are opened and every member is checked.

The gate has been shown to fail: copying `/bin/echo` over `env/ours/bin/as`
produces

```
host/build/env/ours/bin/as              ELF (a HOST binary)   <-- WANTED z8001
GATE EXIT=1
```

`loutid.py` is a header identification and deliberately not a disassembly: it
answers "is this a Z8001 program" for a whole tree in milliseconds with no Go,
no simulator and no sibling checkout. Whether a program also *runs* is a
different question, and only the guest answers it.

## What `build-native.sh` had to change, and why

`cc0/cc1/cc2` were already produced by `build-selfhost.sh`. The driver, the
assembler and the linker had never been built for the target. They compile
**pristine** — every shim in `build-as.sh`/`build-ld.sh` is an LP64/glibc/gcc
workaround that does not apply when `int` is 16 bits and the on-file structs
are the native layout — with these exceptions, all in the driver:

* `-DX_OK=AEXEC -DR_OK=AREAD`: `cc.c` uses the 4.x spelling of the access(2)
  modes; COHERENT 3.x `include/access.h` spells them `AEXEC`/`AREAD`.
* `-DVERSMWC=...`: the version string, which no header here defines.
* `-DV8087=VMBASE+13` and friends: the i386/i8086 FP and OMF variant bits,
  which the driver names unconditionally in its option table and which
  `h/z8001/varmch.h` has no hardware to describe. All six map onto one unused
  machine-dependent slot, inside the `VMBASE..VMAXIM` range so that setting
  one cannot write outside the `VARIANT` array.
* a `getpass` → `ccgetpass` rename in a scratch copy: the driver's static
  collides with libc's `getpass(3)`.

Two changes went into `src/cc/coh/cc.c` itself, under `#if _Z8001`, because
they are not workarounds but the machine's own defaults:

* **the default memory model is `VSEG`.** The donor forces `VSMALL` outside
  OMF output — right on the 8086, and here it compiles every program for a
  Z8002 with truncated pointers. The first guest compile died in cc1 with an
  internal compiler error for exactly this reason; the variant string the
  driver computed was `...0480` (VNSEG) where the cross driver uses
  `...020800` (VSEG + VREADONLY).
* **`VREADONLY` on by default**, because the system headers spell `const`
  `readonly` (`ctype.h`) and without the keyword they do not parse.

## Measured cost of compiling in the guest

Under the minimal emulator (`commodore-900-emulator`), COHERENT 3.5 booted
from the `extended-build` dist, environment mounted from a rendered medium:

| workload | host wall clock |
|---|---|
| boot + mount + umount, no compiling (control) | 23 s |
| `make` over 8 one-function files, no includes | 33 s total, ≈ **10 s for the 8 compiles** |
| `make` over a 2-file program with `<stdio.h>`, plus the link, plus running the result | 37 s total, ≈ **14 s for the build** |

So roughly **1–7 s of host wall clock per source file**, against a fixed ~20 s
of boot and mount. That is a usable path, not merely a faithful one.

**A trap worth knowing before you measure this yourself.** Driving `cc` by
typing it at the console costs far more than the compile: five long command
lines fed through the emulator's console input cost 104 s more than one,
whether they were compiler invocations (+111 s) or `echo` with a 95-character
argument (+104 s). Console input pacing, not compilation, was the whole
difference. Measure a build that `make` drives, or you will measure the
keyboard.

The guest's own clocks do not agree with any of this and should not be quoted
as "what real hardware would take": for the same one-file compile, `date`
before and after reported **23 minutes** (the emulated RTC, which advances one
second per `--rtc-ips` instructions) while `time(1)` reported **5.7 s real,
0.5 s CPU** (the kernel's tick accounting). Two clocks in one emulated
machine, ~250x apart. Calibrating them is an emulator question, and until it
is answered the honest number is the host's.
