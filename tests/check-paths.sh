#!/bin/sh
# check-paths.sh -- every tracked path can be checked out on Windows.
#
#	sh tests/check-paths.sh
#
# git refuses a checkout OUTRIGHT -- "invalid path", no files written -- when a
# tracked name is one Windows cannot create.  It is not a warning and there is
# no partial clone to work in, so ONE such name makes the whole repository
# unusable on that platform, and whoever added it sees nothing: on Linux and
# macOS it checks out fine.  This ran nowhere until a `usr/sys/h/con.h' spent a
# while tracked here.
#
# The reserved DEVICE names are the trap: `con', `prn', `aux', `nul', `com1'..
# `com9' and `lpt1'..`lpt9' name devices with or without an extension, so con.h
# is as unusable as con.  The rest are characters no Windows name may hold, and
# a trailing dot or space, which the API silently strips.
#
# Committed inputs only: no build directory, no emulator, no OS tree.

cd "$(dirname "$0")/.." || exit 2

bad=$(git ls-files | awk '
	{
		n = $0
		sub(/^.*\//, "", n)
		stem = tolower(n)
		sub(/\..*$/, "", stem)
		if (stem ~ /^(con|prn|aux|nul|com[1-9]|lpt[1-9])$/)
			print $0 "\t`" stem "'"'"' is a reserved DOS device name"
		else if (n ~ /[<>:"|?*\\]/)
			print $0 "\ta character Windows forbids in a file name"
		else if (n ~ /[. ]$/)
			print $0 "\ta trailing dot or space, which Windows strips"
	}')

# Without git there is nothing to walk, and "0 tracked paths, all
# checkoutable" is a pass this cannot have earned.
command -v git >/dev/null 2>&1 || {
	echo "*** check-paths: no git on \$PATH, so no path was examined." >&2
	exit 1
}
git rev-parse --git-dir >/dev/null 2>&1 || {
	echo "*** check-paths: not a git checkout, so no path was examined." >&2
	exit 1
}

# A case-insensitive filesystem folds two names into one path.  Windows and
# macOS both do; a tracked file and a directory the build creates collide there
# and nowhere else, which is the hardest version of this to find -- the failure
# is a mkdir refusing a path that looks fine in the repository.  Directories
# `make deps' and the build write into are named here because they exist only
# at build time and git cannot see them.
made="external build"
clash=$({ git ls-files | sed 's|/.*||'; echo "$made" | tr ' ' '\n'; } |
	sort -u | awk '{ k=tolower($0); if (k in seen) print seen[k] "\t" $0; seen[k]=$0 }')
if [ -n "$clash" ]; then
	echo "*** check-paths: these top-level names differ only by case:" >&2
	echo "$clash" | sed 's/^/***   /' >&2
	echo "*** On Windows and macOS they are the same path, so whichever is a" >&2
	echo "*** directory cannot be created beside the file." >&2
	exit 1
fi

if [ -n "$bad" ]; then
	echo "*** check-paths: these tracked names fail a Windows checkout:" >&2
	echo "$bad" | sed 's/^/***   /' >&2
	echo "*** git aborts the whole checkout on the first one, so the" >&2
	echo "*** repository cannot be cloned on Windows at all." >&2
	exit 1
fi

echo "check-paths: $(git ls-files | wc -l | tr -d ' ') tracked paths, all checkoutable on Windows"
