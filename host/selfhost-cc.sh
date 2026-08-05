#!/bin/sh
# selfhost-cc.sh - run the TARGET-BUILT compiler passes (build/selfhost/cc0,cc1,cc2)
# under the n2z8001 guest-exec harness, as the compile engine of a cc-like driver:
#
#     selfhost-cc.sh [-o OUT.o] FILE.c
#
# The guest sees a fake root (build/selfhost/root): /usr/include -> $COHERENT_OS/include and
# /work -> build/selfhost/work, so the passes run with target-authentic paths.
# The input is copied to /work, all three passes run ON the (emulated) target, and
# the resulting object is copied to OUT.o (default: FILE.o beside FILE.c is NOT
# written; default is ./FILE.o).
#
# N2 selects the harness binary (a `go build` of tools/go/n2z8001); required.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SH="$HERE/build/selfhost"
ROOT="$SH/root"
VAR="${CCZ_VAR:-800000020800}"
: "${N2:?set N2 to the n2z8001 simulator binary}"

out=""
case "$1" in
-o) out="$2"; shift 2;;
esac
src="$1"
[ -f "$src" ] || { echo "selfhost-cc: no input $src" >&2; exit 2; }
b=$(basename "$src" .c)
[ -n "$out" ] || out="./$b.o"

cp "$src" "$SH/work/$b.c"
rm -f "$SH/work/$b.z0" "$SH/work/$b.z1" "$SH/work/$b.o" "$SH/work/$b.scr"

run1() {	# run1 <pass> <args...>: one pass on the guest; fail on nonzero guest exit
	p="$1"; shift
	# The runner's STATUS decides.  Its `[exit N]' banner is the guest's
	# status, and a run stopped by a fault or by the instruction budget never
	# reached one -- an older runner printed `[exit 0]' for it and returned 4.
	rc=0
	N2ROOT="$ROOT" "$N2" -runexec "$SH/$p" "$@" >"$SH/work/$b.$p.log" 2>&1 || rc=$?
	[ "$rc" = 0 ] && grep -q "^\[exit 0\]$" "$SH/work/$b.$p.log" || {
		echo "selfhost-cc: TARGET $p FAILED on $src:" >&2
		tail -5 "$SH/work/$b.$p.log" >&2
		exit 1
	}
}

run1 cc0 "$VAR" "/work/$b.c" "/work/$b.z0"
run1 cc1 "$VAR" "/work/$b.z0" "/work/$b.z1"
run1 cc2 0010 "/work/$b.z1" "/work/$b.o" "/work/$b.scr" 0

cp "$SH/work/$b.o" "$out"
echo "selfhost-cc: $src -> $out ($(wc -c < "$out") bytes, compiled ON TARGET)"
