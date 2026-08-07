#!/bin/sh
# loutdis.sh -- print the path of the l.out disassembler, or fail legibly.
#
# loutdis reads a linked l.out/n.out back into instructions: header, symbols,
# per-function listing, callee-save audit.  Several SIDE harnesses here compare
# instruction streams with it (disdiff.sh, codesize.sh, effdiff.sh,
# effdiff-linked.sh, segrun.sh, segexec.sh, `check.sh dis'), and NO GATE does --
# `make check' asserts through cc3's selection dump and cc2's post-peephole
# listing, which are shipped compilers built out of src/.
#
# It is not in this repository, and that is deliberate: it decodes through a
# simulator's decoder rather than re-implementing an ISA, so it is kept with the
# other simulator-dependent instruments.  A checkout therefore has the whole
# toolchain and every gate, and none of the differential harnesses -- which
# already need $Z8001_DONOR and extracted original binaries they cannot ship
# either.
#
# Resolution order, the same shape as host/runner.sh's, and for the same reason
# -- a checkout is named, never counted off in `../..':
#
#   $LOUTDIS         explicit, wins; the built binary
#   $C900_GOTOOLS    a gotools tree; built through its Makefile if need be
#   a gotools beside this checkout, then one and two levels further out
#
# Callers use:  LD="${LOUTDIS:-$(sh "$H/host/loutdis.sh")}"
# so $LOUTDIS still overrides everything.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

if [ -n "${LOUTDIS:-}" ]; then
	# -f as well as -x: every DIRECTORY is executable too, so testing -x
	# alone accepts a checkout path and prints it as if it were the binary.
	if [ -f "$LOUTDIS" ] && [ -x "$LOUTDIS" ]; then echo "$LOUTDIS"; exit 0; fi
	echo "loutdis.sh: LOUTDIS=$LOUTDIS is not an executable" >&2
	exit 1
fi

# gotools tree: explicit, else beside this checkout's parents.
if [ -n "${C900_GOTOOLS:-}" ]; then
	if [ ! -f "$C900_GOTOOLS/Makefile" ]; then
		echo "loutdis.sh: C900_GOTOOLS=$C900_GOTOOLS holds no Makefile" >&2
		exit 1
	fi
	gt=$(cd "$C900_GOTOOLS" && pwd)
else
	gt=
	for d in "$ROOT/../.." "$ROOT/../../c900oses" "$ROOT/../../.." \
		 "$ROOT/../../../c900oses"; do
		if [ -f "$d/gotools/Makefile" ]; then gt=$(cd "$d/gotools" && pwd); break; fi
	done
fi

if [ -z "$gt" ]; then
	echo "loutdis.sh: no l.out disassembler.  Set \$LOUTDIS to one." >&2
	echo "            It is not part of this repository and NO GATE NEEDS IT:" >&2
	echo "            \`make', \`make check' and every stage of CI pass without" >&2
	echo "            it.  Only the differential harnesses read a disassembly," >&2
	echo "            and those already need \$Z8001_DONOR as well." >&2
	exit 1
fi

# Build on demand rather than only reporting an absence: the binary is an
# artifact of that tree's Makefile, and a harness that says "not built" when one
# `make' away is a chore, not a safeguard.  A build FAILURE is a real error and
# is reported as one.
if [ ! -x "$gt/build/loutdis" ]; then
	if ! make -s -C "$gt" loutdis >&2; then
		echo "loutdis.sh: $gt/Makefile could not build loutdis (see above)" >&2
		exit 1
	fi
fi
echo "$gt/build/loutdis"
