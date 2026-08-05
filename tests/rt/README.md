# Soft-float runtime, for the tests

The Z8001 has no FPU, so cc1 lowers every `double` operation into a call:
`a + b` becomes `CALL dladd`.  These hand-written routines are what those calls
land on -- they are the compiler's own runtime, the equivalent of libgcc, not
part of any OS's libc.  `tests/float-e2e.sh` and `tests/cc2run.sh` assemble and
link them to execute float programs end to end.

They were read out of the Coherent tree at `os/libc/crt/` because that is where
COHERENT ships them, and the build scripts used to assemble them straight from
there.  That made the float gates unrunnable without an OS checkout, for
routines the compiler itself defines the calling convention of.

**This is a copy, and it can drift.** The OS tree still ships its own
`libc/crt/*.s`, and a program built by this toolchain links against THAT one,
not this one.  If a routine here is fixed, the fix has to be carried across, or
the tests will pass against a runtime the shipped programs do not use.  The
right end state is for the OS to take its copy from here (the toolchain owns
what it emits calls to); that has not been done.

Files: `dadd dmul ddiv dcmp itod dtoi ftod dtof ldexp frexp modfs` (`.s`).
