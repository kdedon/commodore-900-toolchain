# Makefile - the Commodore 900 (Z8001) cross toolchain.
#
# Everything the toolchain itself needs is in this repository: `make' builds the
# host cross toolchain with gcc out of src/, against the Coherent headers in
# host/include.  No OS checkout is consulted -- the harnesses that do need one
# take it through host/coherent-os.sh as $COHERENT_OS.
#
#   make            cc0/cc1/cc2/cc3-z8001 + as-z8001 + ld-z8001 + tabgen -> host/build
#   make check      the regression suite + the table gates (implies all)
#   make check-isa  the opcode inventory vs MWC's own assembler table
#   make check-mi   every MI divergence from the donor is justified
#   make check-shims  the host shims still match src/cc
#   make check-sources  every .c under src/ is declared by the native build
#   make check-cc3tab  every table indexed by generated/opcode.h, vs opcode.h
#   make check-selfhost  the byte-identity fixed point: the TARGET-built passes
#                   reproduce this compiler's objects exactly, all 86 of them
#   make env        stage a compiler environment for a guest (docs/ENVIRONMENTS.md)
#   make libc selfhost native   parts of the `ours' env; each needs $COHERENT_OS
#   make env-fallback  cut the two compiler dists consumers place with `make deps'
#   make deps       acquire what DEPS says this repository consumes
#   make clean      remove host/build
#
# The guest RUNNER is not optional: the value assertions execute compiled code
# under the C emulator (host/runner.sh, $C900_EMU).  No simulator is reached
# from this repository at all.

SHELL = /bin/sh
.DELETE_ON_ERROR:
.PHONY: all cc as ld check check-isa check-cc3tab check-mi check-shims check-sources \
	mi-baseline mi-table \
	check-selfhost \
	deps os-fallback env-fallback clean env env-ours env-inherited env-mwc1985 libc selfhost native

# Overridable so lanes sharing one checkout keep their artifacts apart; every
# host/ script resolves it through $C900_BUILD, and artifacts are published by
# rename (host/publish.sh) so a shared tree cannot be composed half-built.
B ?= $(if $(C900_BUILD),$(C900_BUILD),host/build)
export C900_BUILD := $(abspath $(B))

all: cc as ld

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
# tests/segexec.sh and tests/multiseg-text.sh are the same family and are NOT
# here: both link through ccz against libc-z8001, so they need an OS tree, and
# segexec reads the entry segment with loutdis, which is not in this
# repository.  They belong wherever check-selfhost lives, not in `check'.
check: all check-sources check-mi check-shims check-cc3tab check-isa
	sh tests/regress.sh
	sh tests/cc2run.sh
	sh tests/obj-reloc.sh
	sh tests/regclob.sh
	sh tests/float-e2e.sh

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
# Side tools.  Not part of `all': nothing in the toolchain proper needs them,
# and libcoh wants a 32-bit gcc a plain host may not have.  Both are K&R-clean
# so an MWC compiler can build them too.
#
#   coff2elf/mkfix  COFF32 -> ELF32, the x86-target host-link bridge
#   lout2cpm        l.out -> CP/M-8000 x.out (commodore-900-cpm compiles its
#                   own copy of the source rather than consuming this one)
TOOLBIN = $(B)/tools
TOOLCC  = cc -std=gnu89 -g -w
M32     = gcc -m32

tools: $(TOOLBIN)/coff2elf $(TOOLBIN)/mkfix $(TOOLBIN)/lout2cpm

$(TOOLBIN)/coff2elf: tools/coff2elf/coff2elf.c | $(TOOLBIN)
	$(TOOLCC) -o $@ $<
$(TOOLBIN)/mkfix: tools/coff2elf/mkfix.c | $(TOOLBIN)
	$(TOOLCC) -o $@ $<
$(TOOLBIN)/lout2cpm: tools/lout2cpm/lout2cpm.c | $(TOOLBIN)
	$(TOOLCC) -o $@ $<

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

env:
ifeq (ours,$(CCENV))
	sh host/build-cc.sh
	sh host/build-as.sh
	sh host/build-ld.sh
	sh host/build-libc-z8001.sh
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

libc:
	sh host/build-libc-z8001.sh
selfhost:
	sh host/build-selfhost.sh
native:
	sh host/build-native.sh

# The self-host FIXPOINT: run the target-built passes over every compiler source
# and byte-compare the objects against the host build's.  It is the one gate that
# can see a shim which should have been baked.  Deliberately not folded into
# `check': check needs only the emulator, this needs an OS tree as well.
check-selfhost: selfhost
	sh host/build-selfhost2.sh

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

clean:
	rm -rf $(B)
