# The original Mark Williams Z8001 toolchain, 1985

The compiler, assembler, linker and binutils Mark Williams shipped for the
Commodore 900, recovered from the machine's hard-disk image.

| file | bytes | sha256 |
|---|---|---|
| ar | 15782 | 28a22bc5cb937493 |
| as | 38006 | 877a6ef07bc025c4 |
| cc | 54 | f00940fe63cf5e5e |
| ccx | 15458 | 29b874ea936c6b97 |
| ld | 19486 | c87a1dc1b26b85d3 |
| nld | 20922 | 580a26a44215abac |
| nm | 9764 | c4d31a38467f9cbd |
| size | 7350 | 051d50306adbe92a |

Dated June 1985. 

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
