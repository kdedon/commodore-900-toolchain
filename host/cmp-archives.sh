#!/bin/sh
# cmp-archives.sh - the two host archives are the same archive.
#
#	sh host/cmp-archives.sh ARCHIVE-A ARCHIVE-B [LABEL-A LABEL-B]
#
# The Linux tarball and the Windows zip are two builds of one release, and what
# a consumer gets from either is a LAYOUT: it unpacks the archive, points
# $C900_TOOLCHAIN at it, and every consuming makefile then spells the parts as
# host/ccz and host/build/z8001/cc0-z8001.  A release that laid one host's
# archive out differently would be unconsumable on that host -- and nothing
# about the binaries themselves would look wrong.
#
# So this compares CONTENTS, not bytes:
#
#   the entry list   every path, and what it RESOLVES to: a directory, an
#                    executable, or a plain file.  A Windows executable is
#                    named cc0-z8001.exe and a Linux one cc0-z8001, so `.exe'
#                    is normalised away -- it is the only difference between the
#                    two layouts that is allowed to exist.
#   dangling links   host/ is a view over bin/ made of relative symlinks, and a
#                    link naming a file that is not there is a path a consumer
#                    resolves to nothing.  That is how the .exe suffix breaks a
#                    layout, so it is checked by name.
#   deliverable 3    native/ and usr/ must be IDENTICAL BYTES.  One of them is
#                    copied from the other's archive precisely so that both
#                    ship the same native compiler; that is a claim, and this
#                    is where it is checked rather than hoped.
#
# This existed as neither a check nor a shared script once, and the two layouts
# were maintained by hand in two places.  They drifted: the Windows zip lost
# host/ entirely, along with cppz, mkarz and buildlog.sh, and no gate noticed.
set -e
[ $# -ge 2 ] || { echo "usage: cmp-archives.sh ARCHIVE-A ARCHIVE-B [LABEL-A LABEL-B]" >&2; exit 2; }
A=$1; B=$2; la=${3:-$1}; lb=${4:-$2}

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT INT TERM

# Unpack into <dir>/root, then descend through the archive's single top-level
# directory: its name carries the host tag, which is the one thing about the
# two archives that is SUPPOSED to differ.
unpack() {	# unpack <archive> <label> -- print the unpacked top-level directory
	_l=$2; _d=$T/$2; mkdir -p "$_d"
	case "$1" in
	*.tar.gz|*.tgz)	tar xzf "$1" -C "$_d" ;;
	*.zip)		unzip -qq "$1" -d "$_d" ;;
	*) echo "cmp-archives: $1 is neither a .tar.gz nor a .zip" >&2; exit 2 ;;
	esac
	set -- "$_d"/*
	[ $# -eq 1 ] && [ -d "$1" ] ||
		{ echo "cmp-archives: $_l does not hold one top-level directory" >&2; exit 2; }
	echo "$1"
}

# What each path resolves to, with .exe normalised out of it.  Tests that
# FOLLOW the link, deliberately: whether a part is shipped as a link or as a
# copy is the archive's business, and MSYS is entitled to answer it differently
# from tar; what a consumer can spell, and whether it lands on something
# executable, is the contract.  A link with nothing at the far end is the one
# representation difference that matters, and it is reported as `BROKEN'.
manifest() {	# manifest <dir> -- print the sorted entry list
	( cd "$1" && find . -mindepth 1 | LC_ALL=C sort | while read -r p; do
		q=${p#./}
		if [ ! -e "$p" ]; then
			echo "BROKEN ${q%.exe} -> $(readlink "$p")"
		elif [ -d "$p" ]; then
			echo "d ${q%.exe}"
		elif [ -x "$p" ]; then
			echo "fx ${q%.exe}"
		else
			echo "f- ${q%.exe}"
		fi
	  done )
}

da=$(unpack "$A" a); db=$(unpack "$B" b)
manifest "$da" >"$T/ma"; manifest "$db" >"$T/mb"

rc=0
# Named separately, because two archives can be broken in the SAME way and a
# comparison alone would call that agreement.
for m in a b; do
	eval "l=\$l$m"
	if grep '^BROKEN' "$T/m$m" >"$T/broken"; then
		echo "*** $l resolves to nothing at:"
		sed 's/^BROKEN /***   /' "$T/broken"
		rc=1
	fi
done

if diff -u "$T/ma" "$T/mb" >"$T/d"; then
	echo "layout: $(wc -l <"$T/ma") entries, identical in $la and $lb"
else
	echo "*** the two archives are not the same archive (-$la +$lb):"
	sed -n '3,$p' "$T/d"
	rc=1
fi

# Deliverable 3 rides in both host archives and must be one build of it.
same=0
for sub in native usr; do
	[ -d "$da/$sub" ] || { echo "*** $la has no $sub/"; rc=1; continue; }
	[ -d "$db/$sub" ] || { echo "*** $lb has no $sub/"; rc=1; continue; }
	for f in $(cd "$da/$sub" && find . -type f | LC_ALL=C sort); do
		if [ ! -f "$db/$sub/$f" ]; then
			rc=1			# the manifest named it already
		elif cmp -s "$da/$sub/$f" "$db/$sub/$f"; then
			same=$((same + 1))
		else
			echo "*** $sub/${f#./} differs between $la and $lb"
			rc=1
		fi
	done
done
echo "deliverable 3: $same files byte-identical in both archives"

[ $rc = 0 ] || echo "*** REFUSED: a release a consumer cannot unpack and use is not a release." >&2
exit $rc
# end of cmp-archives.sh
