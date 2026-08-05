#!/bin/sh
# pack-coherent-os.sh -- cut the OS-source fallback archive from a checkout.
#
#	COHERENT_OS=... sh host/pack-coherent-os.sh [OUTDIR]
#
# The archive holds ONLY what this repository compiles, which is more than the
# three obvious directories -- see DIRS below.  It is uploaded as a release
# asset and placed by `make deps DEP=coherent'; DEPS says why the edge exists.
#
# DIRS IS THE LIST, and it is checked rather than trusted: the paths the build
# scripts name are read out of them and matched against it, and an uncovered
# one refuses the pack.  A snapshot missing an input does not fail loudly --
# build-libc-z8001.sh takes its malloc from libc-4.2/stdlib/malloc through a
# `[ -f ] &&', so a snapshot without that directory yields a C library with no
# malloc, free or realloc in it, and the build says PASS.
#
# It records the commit it was cut from, in .provenance beside the sources, and
# REFUSES to pack a dirty or unversioned tree.  A snapshot whose origin cannot
# be named is the failure mode this whole edge has to avoid: everything built
# against it -- libc-z8001.a, the self-host fixpoint's objects, a release
# archive -- would carry an OS version nobody can reconstruct.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/coherent-os.sh"		# $COHERENT_OS, or a refusal naming it

out=${1:-${C900_BUILD:-$HERE/build}}
mkdir -p "$out"

# Every part of the OS tree this repository's build scripts read.
DIRS="include libc csu libm libc-4.2/stdlib/malloc usr.lib-3.x/misc cmd/ar.c"

# What those scripts actually name, against DIRS.
miss=
for p in $(grep -rhoE '\$\{?(OSL|COHERENT_OS)\}?/[a-zA-Z0-9_./-]+' \
		"$HERE"/*.sh "$HERE/ccz" 2>/dev/null \
	   | sed -e 's/^[^/]*\///' | grep -v '^\.provenance$' | sort -u); do
	for d in $DIRS; do
		case "$p" in "$d"|"$d"/*) continue 2 ;; esac
	done
	miss="$miss $p"
done
[ -z "$miss" ] || {
	echo "pack-coherent-os.sh: the build reads OS paths this archive would not carry:" >&2
	for m in $miss; do echo "    \$COHERENT_OS/$m" >&2; done
	echo "  Add them to DIRS, or the snapshot builds a quietly smaller library." >&2
	exit 2
}

# The checkout is the OS repository; $COHERENT_OS is its os/ directory.
repo=$COHERENT_OS
[ -d "$repo/.git" ] || repo=$(dirname "$COHERENT_OS")
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || {
	echo "pack-coherent-os.sh: $COHERENT_OS is not in a git checkout." >&2
	echo "  The archive names the commit it was cut from; an unversioned tree" >&2
	echo "  cannot be named, so it is not packed." >&2
	exit 2
}
commit=$(git -C "$repo" rev-parse HEAD)

# Dirty over what is PACKED only.  A stray build directory elsewhere in the OS
# tree says nothing about the sources going into the archive, and refusing on
# one would make this unrunnable in any tree that has been built in.
paths=
for d in $DIRS; do paths="$paths $COHERENT_OS/$d"; done
dirty=$(git -C "$repo" status --porcelain -- $paths)
if [ -n "$dirty" ]; then
	echo "pack-coherent-os.sh: what would be packed has uncommitted changes:" >&2
	echo "$dirty" >&2
	echo "  Commit them first: the archive would claim $commit and not be it." >&2
	exit 2
fi
date=$(git -C "$repo" show -s --format=%cs "$commit")
short=$(git -C "$repo" rev-parse --short "$commit")

stage=$out/.coherent-os.$$
trap 'rm -rf "$stage"' EXIT INT TERM
rm -rf "$stage"
mkdir -p "$stage/coherent-os"

for d in $DIRS; do
	[ -e "$COHERENT_OS/$d" ] || {
		echo "pack-coherent-os.sh: no $COHERENT_OS/$d" >&2; exit 2; }
	mkdir -p "$stage/coherent-os/$(dirname "$d")"
	cp -R "$COHERENT_OS/$d" "$stage/coherent-os/$d"
done

cat > "$stage/coherent-os/.provenance" <<EOF
# The COHERENT OS sources this repository compiles, cut from a checkout.
# Read by host/coherent-os.sh, which says so whenever a build resolves here
# rather than to a live tree.
commit $commit
date $date
dirs $DIRS
EOF

# The tag and the asset are one name, so DEPS pins with `@REF@.tar.gz' and the
# tag alone says which OS snapshot a build used.
tag=coherent-os-$date-$short
tar czf "$out/$tag.tar.gz" -C "$stage" coherent-os
echo "pack-coherent-os.sh: $out/$tag.tar.gz ($commit)"
echo "  Publish it as a release tagged $tag, then set that tag in DEPS."
