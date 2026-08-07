#!/bin/sh
# check-tools.sh -- every external command `make all' and `make check' invoke.
#
#	sh tests/check-tools.sh
#
# Names EVERY missing one, then exits.  A build that discovers them one at a
# time costs a CI round each, and on a host nobody develops on that is how a
# morning goes.
set -u
missing=
# git is here because the build STAMPS with it -- without it every artifact
# says `commit unknown' -- and because check-paths cannot examine a path
# without it.
for t in awk basename cc cmp dirname find git grep install make md5sum mktemp \
	 patch sed sort stat tail tr uniq wc; do
	command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
# python3 runs the ISA and MI gates; MSYS2 ships it as `python'.
command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 ||
	missing="$missing python3"

if [ -n "$missing" ]; then
	echo "*** check-tools: not on \$PATH:$missing" >&2
	echo "*** These are what the build and the gates run.  On MSYS2 they come" >&2
	echo "*** from coreutils diffutils findutils gawk grep sed patch." >&2
	exit 1
fi
echo "check-tools: every command the build runs is present"
