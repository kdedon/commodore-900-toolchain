#!/bin/sh
# cmp-objdirs.sh - byte-compare two directories of objects, and name what differs.
#
#	sh host/cmp-objdirs.sh DIR-A DIR-B [LABEL-A LABEL-B]
#
# S4's second half: the Linux and Windows builds of the same compiler compile the
# same 86 translation units, and the objects must be identical.  Two builds of
# one source are not one compiler until that is checked -- and the check is the
# ONLY place an LLP64-versus-LP64 defect can surface, since Windows `long' is 32
# bits (closer to the target than Linux's 64) and so the risk there is not
# truncation but anything that assumed a host pointer fits in a host long.
#
# A bare mismatch count would be useless for that, so every differing object is
# named with the offset cmp reports.
set -e
[ $# -ge 2 ] || { echo "usage: cmp-objdirs.sh DIR-A DIR-B [LABEL-A LABEL-B]" >&2; exit 2; }
A=$1; B=$2; la=${3:-$1}; lb=${4:-$2}

[ -d "$A" ] || { echo "cmp-objdirs: no directory $A" >&2; exit 2; }
[ -d "$B" ] || { echo "cmp-objdirs: no directory $B" >&2; exit 2; }

same=0; diff=0; only=0
for f in "$A"/*.o; do
	b=$(basename "$f")
	if [ ! -f "$B/$b" ]; then
		echo "ONLY IN $la: $b"; only=$((only + 1)); continue
	fi
	if cmp -s "$f" "$B/$b"; then
		same=$((same + 1))
	else
		echo "DIFFER   $b ($(cmp "$f" "$B/$b" 2>&1 | head -1))"
		diff=$((diff + 1))
	fi
done
for f in "$B"/*.o; do
	b=$(basename "$f")
	[ -f "$A/$b" ] || { echo "ONLY IN $lb: $b"; only=$((only + 1)); }
done

echo "=== $la vs $lb: $same identical, $diff differ, $only unpaired ==="
[ "$diff" = 0 ] && [ "$only" = 0 ]
