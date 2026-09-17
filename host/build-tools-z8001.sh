#!/bin/sh
# build-tools-z8001.sh -- cross-build the shipped tools to run on the machine.
#
#	sh host/build-tools-z8001.sh
#
# loutid, lout2cpm and loutdis, linked like any other /bin command.  coff2elf
# and mkfix are not here: they bridge COFF32 to ELF32 for a host link and have
# no meaning on the target.
#
# $BUILD/tools-z8001, not $BUILD/native: native/ is the compiler environment
# build-env.sh stages into env/ours/bin, and these are ordinary utilities.
#
# Prereqs: make all, make libc, make tools.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
CCZ="$HERE/ccz"
. "$HERE/publish.sh"			# $BUILD, stagedir, publish_dir

# The shipped userland's link convention: stripped, separated I/D with shared
# text, large model.
LFLAGS="-s -i -L"

[ -x "$CCZ" ] || { echo "build-tools-z8001.sh: no ccz at $CCZ" >&2; exit 1; }
OUT=$(stagedir tools-z8001)
trap 'rm -rf "$OUT"' EXIT INT TERM
W="$OUT/obj"; mkdir -p "$W"

compile() {	# compile <obj> <source> [flag ...]
	_o=$1; _s=$2; shift 2
	if ! "$CCZ" -c -o "$W/$_o" "$@" "$ROOT/$_s" >"$W/$_o.log" 2>&1; then
		echo "build-tools-z8001.sh: $_s: $(grep -v Warning "$W/$_o.log" |
			tail -3 | tr '\n' ' ')" >&2
		exit 1
	fi
}

echo "== loutid"
compile loutid.o tools/loutid/loutid.c
"$CCZ" $LFLAGS -o "$OUT/loutid" "$W/loutid.o"

echo "== lout2cpm"
compile lout2cpm.o tools/lout2cpm/lout2cpm.c
"$CCZ" $LFLAGS -o "$OUT/lout2cpm" "$W/lout2cpm.o"

echo "== loutdis"
compile loutdis.o tools/loutdis/loutdis.c -I"$ROOT/tools/loutdis"
compile z8kdis.o tools/loutdis/z8kdis.c -I"$ROOT/tools/loutdis"
"$CCZ" $LFLAGS -o "$OUT/loutdis" "$W/loutdis.o" "$W/z8kdis.o"

# ccz reports a byte count from the file it wrote and says nothing about which
# machine it is for; this script's risk is a host binary reaching a target tree.
"$BUILD/tools/loutid" -m z8001 "$OUT/loutid" "$OUT/lout2cpm" "$OUT/loutdis"

publish_dir tools-z8001
trap - EXIT INT TERM			# $OUT is published now
# end of build-tools-z8001.sh
