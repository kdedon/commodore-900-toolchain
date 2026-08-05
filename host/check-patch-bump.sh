#!/bin/sh
# check-patch-bump.sh - refuse a PATCH bump that moved an emitted byte.
#
#	sh host/check-patch-bump.sh OLDVER NEWVER OLD-codegen.tar.gz NEW-codegen.tar.gz
#
# vMAJOR.MINOR.PATCH means something here (AUTOMATION.md 13.3): PATCH promises
# that codegen did NOT change, MINOR says it did.  That promise is mechanically
# checkable, which is the reason to state it so precisely -- the self-host
# fixpoint compiles all 86 compiler translation units and its objects are
# deterministic, so "no emitted byte moved" is a byte comparison of two archives
# and not a judgement call.  A promise a workflow can check is worth making; one
# it cannot is decoration.
#
# Exit 0 = the bump is allowed.  Exit 1 = it is refused, and the objects whose
# bytes moved are named: the release must be MINOR, or the change reverted.
# A MAJOR or MINOR bump is allowed unconditionally -- it is the version number
# that ANNOUNCES moved bytes.  A first release, or a missing previous archive,
# is allowed and says so; there is nothing to compare against.
set -e

usage() { echo "usage: check-patch-bump.sh OLDVER NEWVER OLDTGZ NEWTGZ" >&2; exit 2; }
[ $# -eq 4 ] || usage
old=${1#v}; new=${2#v}; oldtgz=$3; newtgz=$4

fld() { echo "$1" | cut -d. -f"$2"; }
for v in "$old" "$new"; do
	case "$v" in
	[0-9]*.[0-9]*.[0-9]*) ;;
	*) echo "check-patch-bump: \`$v' is not MAJOR.MINOR.PATCH" >&2; exit 2 ;;
	esac
done

if [ "$(fld "$old" 1)" != "$(fld "$new" 1)" ] || [ "$(fld "$old" 2)" != "$(fld "$new" 2)" ]; then
	echo "v$old -> v$new is not a PATCH bump; codegen is allowed to move."
	exit 0
fi
if [ "$(fld "$old" 3)" = "$(fld "$new" 3)" ]; then
	echo "check-patch-bump: v$new does not bump anything over v$old" >&2
	exit 1
fi

if [ ! -f "$oldtgz" ]; then
	echo "check-patch-bump: no codegen archive for v$old ($oldtgz);"
	echo "  nothing to compare against, so the bump is allowed."
	exit 0
fi
[ -f "$newtgz" ] || { echo "check-patch-bump: no codegen archive for v$new ($newtgz)" >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT INT TERM
mkdir "$T/old" "$T/new"
tar xzf "$oldtgz" -C "$T/old"
tar xzf "$newtgz" -C "$T/new"

moved=0; added=0; removed=0
for f in "$T"/new/*.o; do
	b=$(basename "$f")
	if [ ! -f "$T/old/$b" ]; then
		echo "ADDED    $b"
		added=$((added + 1))
		continue
	fi
	if ! cmp -s "$T/old/$b" "$f"; then
		echo "MOVED    $b ($(cmp "$T/old/$b" "$f" 2>&1 | head -1))"
		moved=$((moved + 1))
	fi
done
for f in "$T"/old/*.o; do
	b=$(basename "$f")
	[ -f "$T/new/$b" ] || { echo "REMOVED  $b"; removed=$((removed + 1)); }
done

n=$(ls "$T"/new/*.o | wc -l)
echo "=== patch bump v$old -> v$new: $n objects, $moved moved, $added added, $removed removed ==="
if [ "$moved" = 0 ] && [ "$added" = 0 ] && [ "$removed" = 0 ]; then
	exit 0
fi
echo "*** REFUSED: v$new is a PATCH bump, and PATCH means no emitted byte moved." >&2
echo "*** Release this as a MINOR bump, or take the codegen change back out." >&2
exit 1
# end of check-patch-bump.sh
