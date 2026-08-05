#!/bin/sh
# selfhost-root.sh - build the fake root the self-host fixpoint (S3) runs in.
#
#	sh host/selfhost-root.sh [SELFHOST_DIR]
#
# SELFHOST_DIR defaults to $BUILD/selfhost; build-selfhost.sh passes its private
# staging directory so the root is published by the same rename as the passes.
#
# build-selfhost2.sh runs the host passes and the TARGET passes with IDENTICAL
# argv, and the argv carries relative paths -- so both sides must see one
# directory tree under one set of names, and the target side sees it through the
# emulator's N2ROOT.  That tree is this:
#
#	src	 -> src/cc		the compiler source of record
#	tables	 -> ../tables		tabgen's macros.c/patern.c, built beside it
#	usr/include -> $COHERENT_OS/include	the target system headers
#	lib	 -> $BUILD/libc-z8001	crt0.o + libc-z8001.a
#	work/h2, work/t2		the two sides' intermediates and objects
#
# It is symlinks rather than copies because every input already exists exactly
# once elsewhere in the build, and a copy is a thing that can go stale.
#
# This existed in no script until 2026-08-04: it survived only in whichever
# working tree first made it by hand, which made the gate unrunnable from a
# fresh checkout -- the one property CI depends on.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/publish.sh"			# $BUILD
. "$HERE/coherent-os.sh"		# $COHERENT_OS: usr/include is an OS input

SH=${1:-$BUILD/selfhost}
R="$SH/root"

# The selection tables are two generated .c files the compile needs and no
# checkout carries.  build-selfhost.sh makes them on its way to the target
# passes; the host-only side of the fixpoint (the Windows runner, which compares
# objects across hosts and never builds a target pass) has no other way to get
# them, so making them is part of making the root.
stale=0
for t in "$ROOT/src/cc/n1/tables"/*.t "$ROOT/src/cc/n1/tables/prefac.f"; do
	[ "$t" -nt "$SH/tables/macros.c" ] && stale=1
done
if [ ! -f "$SH/tables/macros.c" ] || [ "$stale" = 1 ]; then
	mkdir -p "$SH/tables"
	cp "$ROOT/src/cc/n1/tables"/*.t "$ROOT/src/cc/n1/tables/prefac.f" "$SH/tables/"
	( cd "$SH/tables" && "$BUILD/tabgen" -s prefac.f *.t >/dev/null )
fi

mkdir -p "$R/usr" "$R/work/h2" "$R/work/t2"
ln -sfn "$ROOT/src/cc" "$R/src"
ln -sfn ../tables "$R/tables"		# relative: valid in staging and published
ln -sfn "$COHERENT_OS/include" "$R/usr/include"
ln -sfn "$BUILD/libc-z8001" "$R/lib"

echo "selfhost root: $R"
# end of selfhost-root.sh
