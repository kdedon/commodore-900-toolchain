# Commodore 900 (Z8001) cross-toolchain.
# The normal host build is self-contained; optional targets name their inputs.
#
#   make            cc0/cc1/cc2/cc3-z8001 + as-z8001 + ld-z8001 + slgen + tabgen
#                   -> host/build
#   make check      the regression suite + the table gates (implies all)
#   make check-isa  the opcode inventory vs MWC's own assembler table
#   make check-mi   every MI divergence from the donor is justified
#   make check-shims  the host shims still match src/cc
#   make check-paths  every tracked name survives a Windows checkout
#   make check-sources  every .c under src/ is declared by the native build
#   make check-cc3tab  every table indexed by generated/opcode.h, vs opcode.h
#   make check-libc   the C library's own answers, run on the target libc
#   make check-selfhost  the byte-identity fixed point: the TARGET-built passes
#                   reproduce this compiler's objects exactly, all 86 of them
#   make env        stage a compiler environment for a guest (docs/ENVIRONMENTS.md)
#   make libc libm libmisc selfhost native   parts of the `ours' env; each needs $COHERENT_OS
#   make env-fallback  cut the two compiler dists consumers place with `make deps'
#   make packages   cut the release packages into $(PKGOUT), each judged against
#                   its own .contents and .provenance before it is left there
#   make deps       acquire what DEPS says this repository consumes
#   make clean      remove host/build
#
# The guest RUNNER is not optional: the value assertions execute compiled code
# under the C emulator (host/runner.sh, $C900_EMU).  No simulator is reached
# from this repository at all.

SHELL = /bin/sh
.DELETE_ON_ERROR:
.PHONY: all cc as ld slgen libc1 check check-isa check-cc3tab check-mi check-shims check-sources \
	check-paths \
	mi-baseline mi-table \
	check-selfhost check-native check-tools check-libc \
	deps os-fallback env-fallback packages clean env env-ours env-inherited env-mwc1985 \
	libc libm libmisc selfhost native tools-z8001 help

# Overridable so lanes sharing one checkout keep their artifacts apart; every
# host/ script resolves it through $C900_TC_BUILD, which is also the name a
# consuming tree sets to read out of the same directory, and artifacts are
# published by rename (host/publish.sh) so a shared tree cannot be composed
# half-built.
B ?= $(if $(C900_TC_BUILD),$(C900_TC_BUILD),host/build)
export C900_TC_BUILD := $(abspath $(B))

all: cc as ld slgen

help:
	@printf '%s\n' \
	  'make                 build the compiler, assembler, linker and slgen' \
	  'make check           run the regression suite' \
	  'make check-selfhost  verify the compiler fixed point' \
	  'make check-native    compare native assembler/linker output' \
	  'make tools           build conversion tools' \
	  'make env             stage a guest compiler environment' \
	  'make packages        cut and judge the release packages' \
	  'make deps            fetch inputs listed in DEPS' \
	  'make clean           remove build products'

# Each script builds, publishes its own artifact, and exits nonzero on failure.
# Nothing here pipes a build into a filter: a pipeline's status is its last
# element's, so `build | grep -c ok' reports whether grep matched.
cc:
	sh host/build-cc.sh
as:
	sh host/build-as.sh
# build-ld.sh reads the patched canon.c + n.out.h out of $(B)/as, so the
# assembler is a real input and not a conventional ordering.
ld: as
	sh host/build-ld.sh

# slgen builds a shared library out of ordinary objects: it reserves the export
# table, runs as and ld, and turns ld's relocation records into the segment
# fixup list (src/include/shlib.h).  Self-contained host C, reading and writing
# l.out by byte offset, so it needs none of the donor shims.
slgen: $(B)/slgen
$(B)/slgen: src/slgen/slgen.c
	@mkdir -p $(B)
	$(TOOLCC) -o $@ $<

# The table gates run here rather than as a side target somebody remembers:
# generated/opcode.h is machine-generated and its numbers are the ROW NUMBERS of
# tables kept by hand, so a half-landed regeneration makes cc2 emit the wrong
# instruction with no diagnostic anywhere.
#
# The four suites after regress.sh need only the emulator, the same edge
# regress.sh already needs, and cost half a second between them -- but nothing
# invoked them, so no CI run has ever executed one.  They cover ground
# regress.sh does not: cc2's object as the linker sees it, relocation, the
# register-clobber contract, and the soft-float runtime.
#
# tests/multiseg-text.sh links through ccz against the libc-z8001 that
# check-libc builds from src/, and runs the result, so it needs that target,
# the emulator and $(B)/tools/loutid.  It is the `ld -L' multi-segment text
# gate: placement of named modules across three and four text segments, read
# back with tools/loutid -s.
#
# tests/ld-commons.sh needs no libc: .comm states the sizes, so as and ld alone
# build the case.
#
# tests/ld-commsize.sh is the other half of the same merge: a common against a
# definition of the name, where ld measures the room the definition has and
# refuses one too small for it.
#
# tests/cc-commons.sh is the compiled half: a file-scope `int foo;' with no
# initialiser under -VCOMM, the driver's own default, through cc0/cc1/cc2 and
# into a link.  It needs the emulator, since the cases are run.
#
# tests/shlib-format.sh builds a toy shared library with slgen and reads it back
# against src/include/shlib.h, the header the kernel's loader compiles against.
#
# tests/shlib-abi.sh holds libc.1's export table to src/libc/libc.1.exp, which
# is the ABI: additions only.  It needs libc1, which is why `check' builds the
# real shared C library.
#
# tests/shlib-data.sh covers the data import: the compiler's -VPIC slot for an
# extern datum, slgen's SE_DATA export, and ld binding one to the other.
#
# tests/shlib-client.sh covers the other half, ld linking a program AGAINST a
# library: a stub and a zeroed slot per import, plus the LI_LIB/LI_IMP records
# exec binds them with.
#
# tests/fixed-mode.sh is the other style: `slgen -F base' builds a library at
# addresses settled when it was built, with an index jump table at the head of
# its shared segment, and `ld -F' links a client of one -- absolutes, direct
# CALLs, no stub, no slot, no import record.
#
# tests/native-ld.sh builds src/ld/all.c FOR the machine and makes that linker
# link a C program against libc under the emulator.  The unity build is the only
# thing that puts the whole linker through the 1985 front end at once: a
# construct gcc takes and cc0 does not would cost every guest its linker with
# the suite green.
#
# tests/foldofs.sh holds the addressing of a far-pointer field: which consumers
# take the constant offset in the base-displacement operand and which must have
# it materialized first.
#
# tests/immstore.sh holds which constant stores reach that operand through a
# register, the Z8000 having no immediate store with a displacement.
#
# tests/calr.sh holds which direct calls go PC-relative: a callee cc2 has
# already laid down in the same segment and within reach, and nothing else.
check: check-tools all check-sources check-mi check-shims check-cc3tab check-isa check-paths check-effdiff check-effdiff-linked check-libc libc1 \
	$(B)/tools/loutid $(B)/tools/loutdis $(B)/tools/cohfs
	sh tests/cohfs.sh
	sh tests/regress.sh
	sh tests/cc2run.sh
	sh tests/obj-reloc.sh
	sh tests/ld-commons.sh
	sh tests/ld-commsize.sh
	sh tests/cc-commons.sh
	sh tests/multiseg-text.sh
	sh tests/regclob.sh
	sh tests/ctype.sh
	sh tests/blkmove-variant.sh
	sh tests/lssaddr-variant.sh
	sh tests/asbytes.sh
	sh tests/as-locptr.sh
	sh tests/shlib-format.sh
	sh tests/shlib-client.sh
	sh tests/shlib-data.sh
	sh tests/shlib-abi.sh
	sh tests/fixed-mode.sh
	sh tests/cc-pic.sh
	sh tests/native-ld.sh
	sh tests/float-e2e.sh
	sh tests/foldofs.sh
	sh tests/immstore.sh
	sh tests/calr.sh
	sh tests/regvar.sh

# The efficiency sweep itself needs the donor corpus, the original binaries and
# an l.out disassembler ($EFFDIFF_DIS) this repository does not carry, so it
# cannot run here -- but its NEGATIVE CONTROL needs python3 and
# nothing else, and a differential harness that has never been demonstrated to
# fail is not yet an instrument.  This target is that demonstration: it feeds
# effdiff's own matcher a pair it must call equal and a pair it must call
# different, and fails if either verdict does not come back.  It also prints the
# perturbation size at which the signature matcher stops seeing a function --
# the coverage limit, measured on every run rather than claimed in a comment.
check-effdiff:
	sh tests/effdiff.sh --selftest

# The same demonstration for the LINKED sweep, which needs crt0.o, the libc
# archive and both corpora on top of what effdiff needs.  Its matcher runs at a
# near-exact threshold of 2, so the perturbation it goes blind at is far smaller
# than effdiff's; this target prints that number too.
check-effdiff-linked:
	sh tests/effdiff-linked.sh --selftest

# The C library's own answers, as a PROGRAM on the machine gets them.  notmem()
# decides whether a pointer may be freed, so it is asked of the libc-z8001.a a
# target program links against rather than of a host build of the same source;
# libc is built from src/ (host/coherent-os.sh), so this needs no OS tree and
# nothing beyond the emulator `check' already requires.
check-libc: libc
	sh tests/notmem.sh
	sh tests/printf.sh

# What each program is MADE OF, declared once by the build that runs on the
# C900 and read by every cross-build (host/srcman.sh).  The build scripts assert
# this too, so a stray source cannot be compiled; this target is the assertion
# alone, over committed inputs only, plus the one thing no single build can see:
# that build-selfhost.sh's second copy of the compiler's list still agrees with
# src/cc/Makefile's.
check-sources:
	@sh -c '. host/srcman.sh; rc=0; \
		srcman_check cc src/cc || rc=1; \
		srcman_check as src/as || rc=1; \
		srcman_check ld src/ld || rc=1; \
		srcman_selfhost_check src/cc host/build-selfhost.sh || rc=1; \
		[ $$rc = 0 ] && echo "check-sources: cc, as, ld declared and complete"; \
		exit $$rc'

# The host shims are the one thing `make all' cannot report on: build-cc.sh
# applies them and would fail, but only in a build that reached gcc, and only
# for the lane running it.  This target is that assertion alone, over committed
# inputs only -- no build directory, no emulator, no OS tree.
check-shims:
	sh tests/check-shims.sh

# A name Windows cannot create aborts the whole checkout there, and nothing on
# a Linux or macOS tree shows it -- so it belongs with the other gates over
# committed inputs, which run on every push.
check-tools:
	sh tests/check-tools.sh

check-paths:
	sh tests/check-paths.sh

# The rule that defines this repository -- Z8001 work goes in the machine layer,
# the machine-independent front end is not edited -- is enforced HERE or nowhere.
# It ran nowhere for as long as it needed the 200 MB donor archive to say
# anything: CI printed SKIPPED and exited 0.  It now reads committed hashes and
# needs no donor, so it belongs in `check' with the other gates over committed
# inputs; $MWC_DONOR still adds the full-tree comparison when it is set.
check-mi:
	@python3 tests/mi-divergence.py check

# Rewrite the two generated artifacts.  mi-baseline is the only thing here that
# needs the donor, and it is run when the donor generation changes -- not by a
# gate, which must never be able to rewrite what it is checking.
mi-baseline:
	python3 tests/mi-divergence.py baseline
mi-table:
	python3 tests/mi-divergence.py table

# --check asserts rather than writes.  Run bare, the script overwrites its own
# committed artifact and then exits 0 on the result, so drift from the generator
# would be undetectable by construction.
check-isa:
	python3 tools/isa/check_pst.py --check

# cc3 reads the same CODE stream cc2 does, from its own copy of the instruction
# table; a copy that drifts desynchronizes the reader rather than mis-printing a
# line.  What this cannot see is the DECODER moving under a self-consistent set
# of tables -- that needs the simulator and lives with the generator.
check-cc3tab:
	sh tests/cc3tab.sh

# ---------------------------------------------------------------------------
# Side tools.  Not part of `all', but `env' and `native' depend on `tools':
# build-native.sh and build-env.sh both run loutid to identify l.out objects.
# libcoh wants a 32-bit gcc a plain host may not have; coff2elf/mkfix/lout2cpm/
# loutid/loutdis are K&R-clean so an MWC compiler can build them too.
#
#   cohfs           makes, reads and writes COHERENT filesystems in a disk
#                   image; host-run only, since the machine has its own mkfs
#   coff2elf/mkfix  COFF32 -> ELF32, the x86-target host-link bridge
#   lout2cpm        l.out -> CP/M-8000 x.out (commodore-900-cpm compiles its
#                   own copy of the source rather than consuming this one)
#   loutdis         l.out disassembler.  Its instruction knowledge is entirely
#                   in tools/loutdis/z8ktab.h, generated from a verified
#                   decoder that is not reachable from this repository.
TOOLBIN = $(B)/tools
TOOLCC  = cc -std=gnu89 -g -w
M32     = gcc -m32

tools: $(TOOLBIN)/coff2elf $(TOOLBIN)/mkfix $(TOOLBIN)/lout2cpm $(TOOLBIN)/loutid \
	$(TOOLBIN)/loutdis $(TOOLBIN)/cohfs

$(TOOLBIN)/coff2elf: tools/coff2elf/coff2elf.c | $(TOOLBIN)
	$(TOOLCC) -o $@ $<
$(TOOLBIN)/mkfix: tools/coff2elf/mkfix.c | $(TOOLBIN)
	$(TOOLCC) -o $@ $<
$(TOOLBIN)/lout2cpm: tools/lout2cpm/lout2cpm.c | $(TOOLBIN)
	$(TOOLCC) -o $@ $<
$(TOOLBIN)/loutid: tools/loutid/loutid.c | $(TOOLBIN)
	$(TOOLCC) -o $@ $<
$(TOOLBIN)/cohfs: tools/cohfs/cohfs.c | $(TOOLBIN)
	$(TOOLCC) -o $@ $<
$(TOOLBIN)/loutdis: tools/loutdis/loutdis.c tools/loutdis/z8kdis.c \
		tools/loutdis/z8ktab.h | $(TOOLBIN)
	$(TOOLCC) -Itools/loutdis -o $@ tools/loutdis/loutdis.c tools/loutdis/z8kdis.c

# The 32-bit glue a converted object links against: crt0, syscall stubs, sbrk.
# exit.o is a separate member so it is pulled only when stdio's exit() is not.
# No soft-float here -- the integer soft-float came from the donor libc, via an
# i386 harness that has since been deleted.
libcoh: $(TOOLBIN)/crt0.o $(TOOLBIN)/libcoh.a

$(TOOLBIN)/crt0.o: tools/coff2elf/libcoh/crt0.s | $(TOOLBIN)
	$(M32) -c $< -o $@
$(TOOLBIN)/%.o: tools/coff2elf/libcoh/%.s | $(TOOLBIN)
	$(M32) -c $< -o $@
$(TOOLBIN)/%.o: tools/coff2elf/libcoh/%.c | $(TOOLBIN)
	$(M32) -c -std=gnu89 -w $< -o $@

$(TOOLBIN)/libcoh.a: $(TOOLBIN)/sys.o $(TOOLBIN)/mem.o $(TOOLBIN)/exit.o
	ar rc $@ $^

$(TOOLBIN):
	mkdir -p $(TOOLBIN)

# Needs a 32-bit gcc and gnu ld, so it is its own target rather than part of
# `check'.
check-coff2elf: tools libcoh
	sh tools/coff2elf/test.sh

# ---------------------------------------------------------------------------
# Compiler environments -- host directory trees a GUEST compiles from.
# docs/ENVIRONMENTS.md has the layout and how a guest reaches one.  This is what
# the OS repositories consume, through $C900_TOOLCHAIN.
#
# CCENV NAMES A COMPILER, NOT A SYSTEM.  `inherited' and `mwc1985' take the same
# C library and headers from the same COHERENT staging root and differ only in
# whose compiler binaries sit beside them, so a dist name cannot tell them apart
# -- and neither name may encode a release number.
#
# `ours' is built from this repository's sources and so has real prerequisites,
# chained here.  The others are SELECTED from trees built elsewhere and have
# none; build-env.sh refuses to guess at their inputs.
CCENV ?= ours

env: tools
ifeq (ours,$(CCENV))
	sh host/build-cc.sh
	sh host/build-as.sh
	sh host/build-ld.sh
	sh host/build-libc-z8001.sh
	sh host/build-libm-z8001.sh
	sh host/build-selfhost.sh
	sh host/build-native.sh
endif
	sh host/build-env.sh $(CCENV)

# Named, not a pattern rule: a pattern would also match `env-typo' and build it.
env-ours:
	$(MAKE) env CCENV=ours
env-inherited:
	$(MAKE) env CCENV=inherited
env-mwc1985:
	$(MAKE) env CCENV=mwc1985

# build-libc-z8001.sh compiles C with the published cc0/cc1/cc2 and assembles
# against the patched headers and canon.o that build-ld.sh puts under $(B)/ld.
# Both are real inputs, not a conventional ordering: without cc every C source
# is reported as "DID NOT COMPILE", and without ld the script refuses outright.
libc: cc ld
	sh host/build-libc-z8001.sh
# libc.1, the SHARED C library: libc's own members plus csu/slrt.s through
# slgen.  Built here rather than in the userland repository because the
# toolchain owns every input, and because src/libc/libc.1.exp, the checked-in
# ABI, belongs beside the source it is derived from.
libc1: libc slgen
	sh host/build-libc1.sh
# Both are required by host/release-pack.sh.
libm:
	sh host/build-libm-z8001.sh
libmisc:
	sh host/build-libmisc-z8001.sh
selfhost:
	sh host/build-selfhost.sh
native: tools
	sh host/build-native.sh

# The same tools as `tools', built to run on the machine.  Not a prerequisite of
# `env': they are utilities, and env/ours/bin is the compiler.
tools-z8001: tools libc
	sh host/build-tools-z8001.sh

# The self-host FIXPOINT: run the target-built passes over every compiler source
# and byte-compare the objects against the host build's.  It is the one gate that
# can see a shim which should have been baked.  Deliberately not folded into
# `check': check needs only the emulator, this needs an OS tree as well.
check-selfhost: selfhost
	sh host/build-selfhost2.sh

# The fixpoint runs cc0/cc1/cc2 and nothing else, so the native ASSEMBLER and
# LINKER were built, shipped in the release archive, and never executed.  This
# runs them: their output against the host tools' byte for byte, and a corrupt
# object against ld's exit status, which is the half a byte-comparison cannot
# see -- two linkers agreeing about a bad object still agree.
check-native: native
	sh tests/nativetools.sh

# Never a prerequisite of a build: nothing that compiles may decide for you which
# version of another repository it is testing against.  `make deps DEP=coherent'
# places just that edge.
deps:
	sh host/deps-fetch.sh $(DEP)

# Cut the OS-source snapshot `deps' places, from a checkout you have.  Run when
# the OS moves; publish the archive under the tag it names and pin that tag in
# DEPS.  Not a gate's prerequisite: the thing a gate checks may not be produced
# by the same command that checks it.
os-fallback:
	sh host/pack-coherent-os.sh $(B)

# Cut the two compiler dists consumers place with `make deps' -- the `ours' and
# `mwc1985' guest roots, from environments already composed here.  EXACTLY TWO,
# as the bootstrap for the toolchain <-> OS cycle; host/pack-fallback.sh says
# why, and why a third would not belong.
env-fallback: env-ours env-mwc1985
	sh host/pack-fallback.sh $(B)

# The release packages -- this host's archive, the z8001 archive, the Z8001
# libraries and the target headers -- cut by host/release-pack.sh, which judges
# each archive against what it says it carries and refuses the whole cut on one
# failure.  Each carries programs for the machine its name gives and no other.
# Needs `make all libc libm libmisc selfhost native'; the packer names whichever
# is missing, and asks for less under -hostonly, where no Z8001 program is
# packed at all.  PKGVERSION defaults to what `git describe' says this checkout is.
# Each cut starts from an empty PKGOUT: the two packers only ever add archives
# there, so a stale one from a prior version or a prior dirty tree would
# otherwise sit alongside the new cut and be just as collectible.
PKGVERSION ?=
PKGOUT ?= $(C900_TC_BUILD)/dist
packages:
	rm -rf $(PKGOUT)
	mkdir -p $(PKGOUT)
	sh host/release-pack.sh "$(PKGVERSION)" $(PKGOUT)
	sh host/pack-components.sh "$(PKGVERSION)" $(PKGOUT)

clean:
	rm -rf $(B)
