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

## root/ -- what those tools compile and link against

A guest filesystem skeleton: the 1985 C library, the C runtime startup, and
the three header trees the system's own sources include.

| path | what | sha256 |
|---|---|---|
| root/lib/libc.a | /lib/libc.a, 76062 bytes | 18ae9fda3d418608 |
| root/lib/crts0.o | /lib/crts0.o, 255 bytes | 4680e1f8a41dd318 |
| root/usr/include | /usr/include, 59 headers | |
| root/usr/sys/h | /usr/sys/h, 31 headers | |
| root/usr/sys/z8001/h | /usr/sys/z8001/h, 24 headers | |

A consumer copies `root/` and overlays the tools; `c900 --exec` reroots the
guest's absolute paths at it, so `-I/usr/sys/z8001/h` and `/lib/libc.a` mean
what they meant on the machine.

These are not a convenience.  Until they were here, anything driving the 1985
passes needed a stock COHERENT 0.7.3 hard-disk image to read them out of --
which is large, private, and in no repository, so no CI run could build the
ROM at all.  The forward-ported COHERENT headers are NOT a substitute: they
are a later system, and compiling against them does not give the 1985 objects.
Neither is COHERENT 0.8's tree -- its headers differ in ktty.h, machine.h,
mdata.h and alloc.h, and its `slibc.a` is half the size.

## Why they are in this repository

They are **the same compiler this repository builds**, at its 1985 state:
MWC C for the Z8001.  Ours is that lineage ported, fixed and given a Z8001
backend written for it; `ccx` is the original binary of the same family.
Two points on one line, not two compilers -- which is what makes building the
system with either one a meaningful comparison rather than a curiosity.

They are Z8001 executables: they run on a C900, or under the emulator.  Once
a build happens inside the emulator over a host-mapped directory, selecting
the 1985 compiler is a version choice, not a separate procedure.

## Binaries, in a repository that otherwise holds none

Deliberate, and the test is REGENERABILITY.  The no-binaries rule keeps build
output out of a source tree; nothing here can reproduce these, because the
compiler that emitted them exists only as these files.  Losing them would be
permanent, and they came within one disk of being lost already.  `libc.a` and
`crts0.o` pass the same test for the same reason: the sources they were built
from are not in any holding, and the compiler that built them is the one above.

## Licence

Same as the rest of this repository: BSD 3-Clause, (c) 1977-1995 Robert
Swartz -- see ../../LICENSE.  Note condition 2 applies to
these specifically: a binary redistribution must reproduce the copyright
notice and disclaimer in its documentation.
