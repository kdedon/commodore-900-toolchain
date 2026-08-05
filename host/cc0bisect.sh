#!/bin/sh
# cc0bisect.sh SRC NLINES [CLOSERS] - take the first NLINES lines of SRC (a
# root-relative path), append CLOSERS (e.g. "}"), run host cc0 and TARGET cc0
# with identical argv, and report exit status + z0 comparison (byte-order-blind:
# just sizes) for each.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SH="$HERE/build/selfhost"
O="$HERE/build/z8001"
VAR="${CCZ_VAR:-800000020800}"
: "${N2:?set N2 to the n2z8001 simulator binary}"
src="$1"; nl="$2"; closer="$3"
cd "$SH/root"
INC="-Isrc/n1/z8001 -Isrc/n0/z8001 -Isrc/h/z8001 -Isrc/generated -Isrc/n0 -Isrc/n1 -Isrc/h -Isrc/common -Iusr/include -Iusr/include/sys"
head -"$nl" "$src" > work/bis.c
[ -n "$closer" ] && printf '%s\n' "$closer" >> work/bis.c
hrc=0; trc=0
"$O/cc0-z8001" "$VAR" work/bis.c work/bis.h.z0 $INC > work/bis.h.log 2>&1 || hrc=$?
# The runner's STATUS decides; its `[exit N]' banner is the guest's status and a
# run stopped by a fault or by the budget never reached one.
N2ROOT="$SH/root" timeout 600 "$N2" -runexec "$SH/cc0" "$VAR" work/bis.c work/bis.t.z0 $INC > work/bis.t.log 2>&1 || trc=$?
[ "$trc" = 0 ] && grep -q "^\[exit 0\]$" work/bis.t.log || trc=1
echo "host rc=$hrc ($(wc -c < work/bis.h.z0 2>/dev/null || echo 0) B); target rc=$trc ($(wc -c < work/bis.t.z0 2>/dev/null || echo 0) B)"
[ "$trc" = 1 ] && grep -v "exit" work/bis.t.log | tail -3
exit 0
