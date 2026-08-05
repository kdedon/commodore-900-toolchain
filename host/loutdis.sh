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
# It is not in this repository, and that is deliberate: it decodes through the
# private z8000 simulator's cpu.Decode rather than re-implementing an ISA, so it
# lives in c900oses/gotools with the other simulator-dependent Go instruments.
# A public checkout therefore has the whole toolchain and every gate, and none
# of the differential harnesses -- which already need $Z8001_DONOR and extracted
# original binaries they cannot ship either.
#
# Resolution order, the same shape as host/runner.sh's, and for the same reason
# -- a checkout is named, never counted off in `../..':
#
#   $LOUTDIS         explicit, wins; the built binary
#   $C900_GOTOOLS    the gotools tree; built through its Makefile if need be
#   a gotools beside c900oses, then one and two levels further out
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
	echo "loutdis.sh: no c900oses/gotools tree found beside $ROOT or up to two" >&2
	echo "            levels out.  Set \$C900_GOTOOLS to it, or \$LOUTDIS to a built" >&2
	echo "            loutdis.  It is not in this repository: it decodes through the" >&2
	echo "            private z8000 simulator, and no gate here needs it." >&2
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
