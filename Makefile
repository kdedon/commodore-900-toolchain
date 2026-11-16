# Commodore 900 (Z8001) cross-toolchain.
# The normal host build is self-contained; optional targets name their inputs.
#
#   make            cc0/cc1/cc2/cc3-z8001 + as-z8001 + ld-z8001 + slgen + tabgen + mkarz
#                   -> host/build
#   make check      the regression suite + the table gates (implies all)
#   make check-isa  the opcode inventory vs MWC's own assembler table
#   make loutdis-table  regenerate the disassembler's table from the assembler's
#   make check-mi   every MI divergence from the donor is justified
#   make check-shims  the host shims still match src/cc
#   make check-paths  every tracked name survives a Windows checkout
#   make check-sources  every .c under src/ is declared by the native build
#   make check-cc3tab  every table indexed by generated/opcode.h, vs opcode.h
#   make check-libc   the C library's own answers, run on the target libc
#   make check-selfhost  the target-built passes reproduce the host objects
#   make env        stage a compiler environment for a guest (docs/ENVIRONMENTS.md)
#   make libc libm libmisc selfhost native   parts of the `ours' env
#   make env-fallback  cut the two compiler dists consumers place with `make deps'
#   make packages   cut the release packages into $(PKGOUT), each judged against
#                   its own .contents and .provenance before it is left there
#   make deps       acquire what DEPS says this repository consumes
#   make clean      remove host/build
#
# Tests run compiled code under the emulator (host/runner.sh, $C900_EMU).

SHELL = /bin/sh
.DELETE_ON_ERROR:
.PHONY: all cc as ld slgen mkarz libc1 check check-isa check-cc3tab check-mi check-shims check-sources \
	check-paths check-loutdis-table loutdis-table \
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

all: cc as ld slgen mkarz

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

# mkarz writes the l.out archives consumers build; host/arz calls it.
mkarz: ld
	sh host/arz -b

# slgen builds a shared library from objects: reserves the export table, runs
# as and ld, and turns ld's relocations into the segment fixup list.  Plain
# host C, so it needs no shims.
slgen: $(B)/slgen
$(B)/slgen: src/slgen/slgen.c
	@mkdir -p $(B)
	$(TOOLCC) -o $@ $<

# check runs the table gates too: generated/opcode.h numbers rows of tables
# kept by hand, and a half-landed regeneration makes cc2 emit wrong
# instructions silently.  Each test names what it covers in its header.
check: check-tools all check-sources check-mi check-shims check-cc3tab check-isa check-loutdis-table check-paths check-effdiff check-effdiff-linked check-libc libc1 \
	$(B)/tools/loutid $(B)/tools/loutdis $(B)/tools/cohfs
	sh tests/cohfs.sh
	sh tests/regress.sh
	sh tests/cc2run.sh
	sh tests/obj-reloc.sh
	sh tests/ld-commons.sh
	sh tests/ld-commsize.sh
	sh tests/ld-straddle.sh
	sh tests/cc-commons.sh
	sh tests/multiseg-text.sh
	sh tests/regclob.sh
	sh tests/ctype.sh
	sh tests/blkmove-variant.sh
	sh tests/lssaddr-variant.sh
	sh tests/asbytes.sh
	sh tests/disround.sh
	sh tests/loutdis-hdr.sh
	sh tests/asoddpad.sh
	sh tests/as-locptr.sh
	sh tests/shlib-format.sh
	sh tests/shlib-client.sh
	sh tests/shlib-data.sh
	sh tests/fixed-mode.sh
	sh tests/cc-pic.sh
	sh tests/native-ld.sh
	sh tests/float-e2e.sh
	sh tests/foldofs.sh
	sh tests/immstore.sh
	sh tests/calr.sh
	sh tests/switch.sh
	sh tests/relax.sh
	sh tests/relax-seg.sh
	sh tests/peepfold.sh
	sh tests/regvar.sh
	sh tests/promote.sh
	sh tests/volatile.sh
	sh tests/volmem.sh
	sh tests/initvol.sh
	sh tests/vdebug.sh
	sh tests/symlen.sh
	sh tests/lname.sh
	sh tests/proto.sh
	sh tests/lswitch.sh
	sh tests/linecomment.sh
	sh tests/mixdecl.sh
	sh tests/bytearg.sh
	sh tests/stdlevel.sh
	sh tests/structinit.sh
	sh tests/autoarray.sh
	sh tests/autozero.sh
	sh tests/addrarray.sh
	sh tests/ptrlong.sh
	sh tests/asgval.sh
	sh tests/longuns.sh
	sh tests/mul16.sh
	sh tests/sdiv2.sh
	sh tests/sdivw.sh
	sh tests/cptest.sh
	sh tests/loadreuse.sh
	sh tests/peepvals.sh
	sh tests/opasg.sh
	sh tests/condcast.sh
	sh tests/dblcast.sh
	sh tests/charret.sh
	sh tests/sllpair.sh
	sh tests/peepstamp.sh

# effdiff's negative control: its matcher must call a known pair equal and
# another different.  Prints the perturbation at which it goes blind.
check-effdiff:
	sh tests/effdiff.sh --selftest

# The same for the linked sweep.
check-effdiff-linked:
	sh tests/effdiff-linked.sh --selftest

# The C library as a target program sees it, run under the emulator.
# fpcost, fpcycles and intcycles hold soft-float and integer *, / and %
# under instruction and clock ceilings.
check-libc: libc libm $(B)/tools/loutdis
	sh tests/notmem.sh
	sh tests/printf.sh
	sh tests/sbrk.sh
	sh tests/libm.sh
	sh tests/fpcost.sh
	sh tests/fpcycles.sh
	sh tests/intcycles.sh

# Every source is declared by the native build's manifest (host/srcman.sh),
# and build-selfhost.sh's copy of the compiler's list matches src/cc's.
check-sources:
	@sh -c '. host/srcman.sh; rc=0; \
		srcman_check cc src/cc || rc=1; \
		srcman_check as src/as || rc=1; \
		srcman_check ld src/ld || rc=1; \
		srcman_selfhost_check src/cc host/build-selfhost.sh || rc=1; \
		[ $$rc = 0 ] && echo "check-sources: cc, as, ld declared and complete"; \
		exit $$rc'

# The host shims still apply to src/cc.
check-shims:
	sh tests/check-shims.sh

check-tools:
	sh tests/check-tools.sh

# Every tracked name survives a Windows checkout.
check-paths:
	sh tests/check-paths.sh

# Every machine-independent divergence from the donor has a record
# (src/cc/MI-PATCHES).  $MWC_DONOR adds a full-tree comparison.
check-mi:
	@python3 tests/mi-divergence.py check

# Regenerate MI-BASELINE (needs $MWC_DONOR) and docs/PATCHES.md's table.
mi-baseline:
	python3 tests/mi-divergence.py baseline
mi-table:
	python3 tests/mi-divergence.py table

# The opcode inventory matches the assembler's table.
check-isa:
	python3 tools/isa/check_pst.py --check

# z8ktab.h is generated from the assembler's pst.c and asmch.h by gentab.py,
# whose encoders transcribe machine.c.  loutdis-table rewrites it; the check
# asserts the committed table is what the generator writes, and
# tests/disround.sh that the assembler encodes every form as the table says.
loutdis-table:
	python3 tools/loutdis/gentab.py
check-loutdis-table:
	python3 tools/loutdis/gentab.py --check

# cc3's copy of the instruction table matches cc2's.
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
#                   in tools/loutdis/z8ktab.h, which tools/loutdis/gentab.py
#                   generates from the assembler's tables (`make loutdis-table').
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
# libc.1, the shared C library: libc's members plus csu/slrt.s, through slgen.
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

# The self-host fixpoint: the target-built passes reproduce the host
# compiler's objects byte for byte.
check-selfhost: selfhost
	sh host/build-selfhost2.sh

# The native as and ld match the host ones, and ld rejects a corrupt object.
check-native: native
	sh tests/nativetools.sh

# Fetch what DEPS names; `make deps DEP=emu' fetches one.  Never a build
# prerequisite.
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

PKGVERSION ?=
PKGOUT ?= $(C900_TC_BUILD)/dist

# The release packages, cut by host/release-pack.sh and
# host/pack-components.sh, each checked against its .contents and
# .provenance.  Needs `make all libc libm libmisc selfhost native tools
# tools-z8001'.  PKGVERSION defaults to `git describe'.
packages:
	rm -rf $(PKGOUT)
	mkdir -p $(PKGOUT)
	sh host/release-pack.sh "$(PKGVERSION)" $(PKGOUT)
	sh host/pack-components.sh "$(PKGVERSION)" $(PKGOUT)

clean:
	rm -rf $(B)
