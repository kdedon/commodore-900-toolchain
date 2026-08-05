#!/bin/sh
# codesize.sh -- measure OUR generated code for a C function: instruction count and
# byte size, read from cc2-z8001's own object by loutdis.  The differential bar is
# the ORIGINAL MWC backend (loutdis on C900/firmware/floppy_extracted/bin/*) -- the same
# tool on both sides, so the two numbers are comparable; this tracks our size so an
# optimization's effect is measurable.
#   codesize.sh '<C source>'        -> "insns=N bytes=B"
#   codesize.sh -v '<C source>'     -> ... plus the disassembly
H="$(cd "$(dirname "$0")/.." && pwd)"
B="${C900_BUILD:-$H/host/build}"	# the lane's build dir; see host/publish.sh
O="$B/z8001"; VAR="${VAR:-800000000800}"
LOUTDIS=$(sh "$H/host/loutdis.sh"); PEEP="${PEEP:-0010}"
v=0; [ "$1" = "-v" ] && { v=1; shift; }
src="$1"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '%s\n' "$src" > "$T/c.c"
"$O/cc0-z8001" $VAR "$T/c.c" "$T/c.z0" 2>/dev/null || { echo "cc0 FAIL"; exit 1; }
"$O/cc1-z8001" $VAR "$T/c.z0" "$T/c.z1" 2>/dev/null || { echo "cc1 FAIL"; exit 1; }
"$O/cc2-z8001" $PEEP "$T/c.z1" "$T/c.o" "$T/c.scr" 0 2>/dev/null || { echo "cc2 FAIL"; exit 1; }
dis=$("$LOUTDIS" -v "$T/c.o" 2>/dev/null | grep -E '^ +[0-9a-f]{4}: ')
# per-function `addr bytes insns ...' rows: sum the whole object's instructions and bytes
sums=$("$LOUTDIS" -funcs "$T/c.o" 2>/dev/null | awk '$1 ~ /^[0-9a-f]{8}$/ { b+=$2; n+=$3 } END { print n, b }')
n=${sums%% *}; b=${sums##* }
echo "insns=$n bytes=${b:-?}"
[ $v = 1 ] && printf '%s\n' "$dis"
exit 0
