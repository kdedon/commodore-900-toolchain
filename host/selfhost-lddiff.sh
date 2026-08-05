#!/bin/sh
# selfhost-lddiff.sh - link the same objects with the host-built ld and with the
# TARGET-RUN ld (build/selfhost/ld-native under the guest harness), identical
# argv (relative paths from the fake root), and byte-compare the executables.
#     selfhost-lddiff.sh OBJ.o [OBJ.o ...]   (paths relative to the fake root)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SH="$HERE/build/selfhost"
HLD="$HERE/build/ld-z8001"
: "${N2:?set N2 to the n2z8001 simulator binary}"
cd "$SH/root"

args="-n -i -o work/ld.h.out lib/crt0.o $* lib/libc-z8001.a"
"$HLD" $args
# The runner's STATUS decides; its `[exit N]' banner is the guest's status and a
# run stopped by a fault or by the budget never reached one.
rc=0
N2ROOT="$SH/root" timeout 600 "$N2" -runexec "$SH/ld-native" -n -i -o work/ld.t.out lib/crt0.o "$@" lib/libc-z8001.a >"$SH/work/ld.t.log" 2>&1 || rc=$?
[ "$rc" = 0 ] && grep -q "^\[exit 0\]$" "$SH/work/ld.t.log" || {
	echo "TARGET ld FAILED:"; tail -4 "$SH/work/ld.t.log"; exit 1; }
if cmp -s work/ld.h.out work/ld.t.out; then
	echo "ld output IDENTICAL ($(wc -c < work/ld.h.out) bytes)"
else
	echo "ld output DIFFERS ($(cmp work/ld.h.out work/ld.t.out 2>&1 | head -1))"
fi
