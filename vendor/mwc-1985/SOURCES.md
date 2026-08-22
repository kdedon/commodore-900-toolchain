# The original Mark Williams Z8001 toolchain, 1985

The compiler, assembler, linker and binutils Mark Williams shipped for the
Commodore 900, recovered from the machine's hard-disk image.

| file | bytes | sha256 |
|---|---|---|
| ar | 15782 | 28a22bc5cb937493 |
| as | 38006 | 877a6ef07bc025c4 |
| cc | 54 | f00940fe63cf5e5e |
| cc0 | 46374 | 2a7622043f16844d |
| cc1 | 59292 | 7a45bffaf20d836b |
| cc2 | 32342 | d3561efb8c0f7f1a |
| cc3 | 18282 | bd0ad36214400054 |
| ccx | 15458 | 29b874ea936c6b97 |
| cpp | 17972 | 094a0449fc3c5eca |
| db | 40818 | 8dc68fb73e210e4d |
| l | 9070 | 13f158e07c298431 |
| ld | 19486 | c87a1dc1b26b85d3 |
| nld | 20922 | 580a26a44215abac |
| nm | 9764 | c4d31a38467f9cbd |
| scrts0.o | 310 | d602ba67535b9ca9 |
| slibc.a | 38736 | fb691c228b9f76d5 |
| size | 7350 | 051d50306adbe92a |

Dated June 1985.  The five compiler passes, `db` and `l` carry a later
timestamp only because they were recovered on a later pass over the same
disk; the bytes are the 1985 artifacts, and the sha256 above is what
identifies them.

`cc` and `ccx` are the driver, and `cpp cc0 cc1 cc2 cc3` are what the driver
runs.  A compiler is its passes;
they belong together, and with them here nothing outside this repository is
needed to run it.

## What they are NOT

The COMPILER, and nothing it compiles against.  The 1985 C library, the C
runtime startoff and the `/usr/include`, `/usr/sys/h` and `/usr/sys/z8001/h`
header trees are a 1985 SYSTEM; nothing in this repository is built against
them, and they are held by the repository that builds a 1985 artifact --
`commodore-900-bios`, at its own `vendor/mwc-1985`, which is self-contained.
`make env CCENV=mwc1985` composes these binaries over a root named by
`$C900_STOCK_ROOT` and does not guess at one.

## Why they are in this repository

They are **the same compiler this repository builds**, at its 1985 state:
MWC C for the Z8001.  Ours is that lineage ported, fixed and given a Z8001
backend written for it; `ccx` is the original binary of the same family.
Two points on one line, not two compilers -- which is what makes building the
system with either one a meaningful comparison rather than a curiosity.

They are Z8001 executables: they run on a C900, or under the emulator.  Once
a build happens inside the emulator over a host-mapped directory, selecting
the 1985 compiler is a version choice, not a separate procedure.

`commodore-900-bios` has its own copy of these same tools, because it must
build with them from a clone and nothing else.  Two copies is what each
repository standing alone costs; they are recovered artifacts and do not
change, so the copies cannot drift except by one of them being replaced.

## Binaries, in a repository that otherwise holds none

Deliberate, and the test is REGENERABILITY.  The no-binaries rule keeps build
output out of a source tree; nothing here can reproduce these, because the
compiler that emitted them exists only as these files.  Losing them would be
permanent, and they came within one disk of being lost already.

## Licence

Same as the rest of this repository: BSD 3-Clause, (c) 1977-1995 Robert
Swartz -- see ../../LICENSE.  Note condition 2 applies to
these specifically: a binary redistribution must reproduce the copyright
notice and disclaimer in its documentation.

`scrts0.o` and `slibc.a` are the 1985 SHARED-LIBRARY runtime.

The `s` is `shared', not `small'.  `slibc.a' carries a.out magic 0407 -- a
linked image, not an `ar' archive (a COHERENT archive begins 0177535), which is
what a shared library is.  `scrts0.o' is the client-side start-off: its symbols
are `main_ __end_ end_ exit_ environ_ start _exit_', which is the symbol set of
src/csu/crt0sl.s and NOT that of src/csu/crts0.s -- crts0.s defines no `__end_'
or `end_', because a statically linked program gets its break tracker from the
link rather than from the library.  src/csu/slrt.s is the library-side half.

Nothing builds against them: the shared-library work is designed but
deliberately unimplemented, so these are the only artifacts of that ABI we
hold, and they are the reference for it.
