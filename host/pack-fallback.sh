#!/bin/sh
# pack-fallback.sh -- cut the two fallback compiler dists this repository
# publishes: the `ours' guest root and the `mwc1985' guest root.
#
#	sh host/pack-fallback.sh [OUTDIR]
#
# EXACTLY TWO COMPILER DISTS, and never a third: `ours' and `mwc1985'.  This is
# not an environment-publishing system, it is the bootstrap for the toolchain
# <-> OS cycle, which cannot be broken from either side while
# commodore-900-coherent is unpublished.  The images belong in that
# repository's dist package permanently -- it owns libc, csu and the headers --
# and when it ships one, this pair is frozen and every consumer repoints one
# DEPS line.  Adding a third COMPILER dist here is a deliberate edit to this
# file, not a parameter somebody passes.
#
# The release carries a third ASSET that is not a compiler dist: the OS source
# subset this repository itself compiles.  See the end of this file for why it
# rides along rather than taking a tag of its own.
#
# What a dist IS: the directory host/build-env.sh composes, tarred whole.  A
# consumer unpacks it and compiles with it; it needs no checkout of anything,
# and that is the entire point of the edge.
#
# It records what each root was composed from, in .provenance inside the root
# (written by build-env.sh), and REFUSES to pack one that cannot be named --
# an unversioned tree, uncommitted changes, or an environment holding no
# compiler passes.  Everything downstream of a dist is a binary: a root whose
# origin cannot be reconstructed makes "which compiler built this" unanswerable
# for every artifact any consumer ever builds with it.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/publish.sh"			# $BUILD

out=${1:-$BUILD}
mkdir -p "$out"

# The tag is DECLARED, not derived: `fallback-N', and both assets carry it.
# A date-and-commit tag reads like a nightly, and this is the opposite of one --
# it is a frozen bootstrap that retires when the OS repository ships its dist
# package, so the name a consumer pins should say what the thing IS and change
# only when somebody decides it should.  Which commit it was cut from is not
# lost: .provenance inside each root records it, along with the COHERENT commit
# behind `ours' libc and headers.  Bump N when a new pair is published.
#
# AND THE TAG IS MUTABLE.  A bootstrap edge is re-cut in place -- fallback-1's
# assets are overwritten -- so the tag names the ROLE, not a set of bytes, and
# two roots tagged fallback-1 need not be the same ones.  What distinguishes
# them is the `toolchain <commit>' line in .provenance, which is why that line
# is not optional and why a dirty tree is refused.  Consequences a consumer
# lives with: `make deps' leaves an already-unpacked dist alone, so a machine
# or CI cache holding the previous cut keeps it silently, and `rm -rf external/<x>'
# is what forces the new one.
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
	echo "pack-fallback.sh: $ROOT is not a git checkout." >&2
	echo "  Each dist names the commit it was cut from; an unversioned tree" >&2
	echo "  cannot be named, so nothing is packed." >&2
	exit 2
}
dirty=$(git -C "$ROOT" status --porcelain)
if [ -n "$dirty" ]; then
	echo "pack-fallback.sh: the toolchain checkout has uncommitted changes:" >&2
	echo "$dirty" >&2
	echo "  Commit them first: the dists would claim a commit they are not." >&2
	exit 2
fi
commit=$(git -C "$ROOT" rev-parse HEAD)
tag=${C900_FALLBACK_TAG:-fallback-1}

# pack <name> -- one dist, from the environment build-env.sh published.
pack() {
	env=$BUILD/env/$1
	[ -d "$env" ] || {
		echo "pack-fallback.sh: no environment at $env" >&2
		echo "  Compose it first: make env CCENV=$1" >&2
		exit 2; }
	want=".provenance CCENV lib/cc0 lib/cc1 lib/cc2 bin/as bin/ld"
	# mwc1985 is also the SYSTEM compiler -- the kernel, the drivers and the
	# boot ROM are built with it -- so its dist must carry the kernel header
	# trees, the 32-bit linkage editor cc2's objects need, and the variant
	# word the passes are run with.  A dist missing any of them links and
	# reads as complete and cannot build the ROM; requiring them here is what
	# stops one being published.  `ours' is a userland compiler environment
	# and wants none of it -- see host/build-env.sh on why they differ.
	[ "$1" = mwc1985 ] &&
		want="$want bin/nld VARIANT usr/sys/h usr/sys/z8001/h"
	for f in $want; do
		[ -e "$env/$f" ] || {
			echo "pack-fallback.sh: $env has no $f." >&2
			echo "  A dist is a working compiler; this tree is not one." >&2
			echo "  Recompose it: make env CCENV=$1" >&2
			exit 2; }
	done
	if grep -q '+dirty' "$env/.provenance"; then
		echo "pack-fallback.sh: $env was composed from a tree with uncommitted" >&2
		echo "  changes (see $env/.provenance).  Commit them and recompose:" >&2
		echo "  make env CCENV=$1" >&2
		exit 2
	fi
	# The dist records the tag it is published under, which is what a
	# consumer's DEPS pins: `unpacked from which release' has to be
	# answerable inside the root, not only from the file it arrived in.
	stage=$out/.fallback.$$
	rm -rf "$stage"
	mkdir -p "$stage"
	cp -RL "$env" "$stage/env-$1"
	echo "release $tag" >> "$stage/env-$1/.provenance"
	tar czf "$out/$tag-$1.tar.gz" -C "$stage" "env-$1"
	rm -rf "$stage"
	echo "pack-fallback.sh: $out/$tag-$1.tar.gz"
}

pack ours
pack mwc1985

# And the OS SOURCE SUBSET, as a third asset of the same release.
#
# It is not a compiler dist and does not count against the two: a consumer
# never wants it.  THIS repository wants it, to build the C library, libm and
# libmisc a release archive ships and to run S2/S3 -- work that needs SOURCE,
# because it produces libraries, and no arrangement of prebuilt roots can
# substitute for that.
#
# One release rather than two tags, because they retire together: when the OS
# repository ships its own dist package, this whole bootstrap goes, and two
# tags that must be bumped in step are two tags that will not be.
C900_OS_ASSET=$tag-coherent-os sh "$HERE/pack-coherent-os.sh" "$out"

echo "pack-fallback.sh: publish all three as ONE release tagged $tag ($commit),"
echo "  then pin that tag in each consumer's DEPS."
