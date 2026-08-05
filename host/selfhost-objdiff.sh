#!/bin/sh
# selfhost-objdiff.sh - full host pipeline vs full TARGET pipeline on one source,
# comparing the final OBJECTS (the IR streams are native-byte-order and cannot be
# cross-compared; the object format is fixed).  Identical argv both sides.
#     selfhost-objdiff.sh NAME    (NAME.c must be in build/selfhost/work)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SH="$HERE/build/selfhost"
O="$HERE/build/z8001"
. "$HERE/coherent-os.sh"; OS="$COHERENT_OS"
VAR="${CCZ_VAR:-800000020800}"
: "${N2:?set N2 to the n2z8001 simulator binary}"

b="$1"
cd "$SH/work"
"$O/cc0-z8001" "$VAR" "$b.c" "$b.h.z0" -I"$OS/include" -I"$OS/include/sys"
"$O/cc1-z8001" "$VAR" "$b.h.z0" "$b.h.z1"
"$O/cc2-z8001" 0010 "$b.h.z1" "$b.h.o" "$b.h.scr" 0

tpass() {	# tpass <pass> <args...>
	p="$1"; shift
	# The runner's STATUS decides; its `[exit N]' banner is the guest's status
	# and a run stopped by a fault or by the budget never reached one.
	rc=0
	N2ROOT="$SH/root" "$N2" -runexec "$SH/$p" "$@" >"$b.$p.log" 2>&1 || rc=$?
	[ "$rc" = 0 ] && grep -q "^\[exit 0\]$" "$b.$p.log" || {
		echo "$b: TARGET $p FAILED: $(tail -2 "$b.$p.log" | head -1)"; exit 1; }
}
tpass cc0 "$VAR" "$b.c" "$b.t.z0"
tpass cc1 "$VAR" "$b.t.z0" "$b.t.z1"
tpass cc2 0010 "$b.t.z1" "$b.t.o" "$b.t.scr" 0

if cmp -s "$b.h.o" "$b.t.o"; then
	echo "$b: object IDENTICAL"
else
	echo "$b: object DIFFERS ($(cmp "$b.h.o" "$b.t.o" 2>&1 | head -1))"
fi
