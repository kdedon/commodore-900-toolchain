#!/bin/sh
# build-libm-z8001.sh - build the Coherent Z8001 math library (libm-z8001.a) on the
# host, so math-using commands (awk, factor, the games) can be linked.  Mirrors
# build-libc-z8001.sh: cc0->cc1->cc2 each donor libm/*.c, then mkarz the objects into
# a Coherent l.out archive.  ld pulls only the members a program references; modf/
# ldexp/frexp come from libc's .s stubs, so libm need not supply them.
# Prereqs: build-z8001.sh, build-cc2-z8001.sh, build-as.sh, build-ld.sh (canon.o),
# and build-libc-z8001.sh (mkarz + libc-z8001.a for the smoke test).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/coherent-os.sh"; OSL="$COHERENT_OS"
. "$HERE/publish.sh"			# $BUILD, stagedir, publish_dir
. "$HERE/buildlog.sh"			# c900_buildlog: records $C900_BUILD_LOG, or nothing
O="$BUILD/z8001"
AS="$BUILD/as-z8001"
LDDIR="$BUILD/ld"
PUB="$BUILD/libm-z8001"
OUT=$(stagedir libm-z8001)
LIBC="$BUILD/libc-z8001"
VAR="${VAR:-800000020800}"
INC="-I$OSL/include -I$OSL/include/sys"
trap 'rm -rf "$OUT"' EXIT INT TERM
mkdir -p "$OUT/obj"

# mkarz: the archive writer, same recipe as build-libc-z8001.sh.
[ -f "$LDDIR/canon.o" ] || { echo "run build-ld.sh first (need build/ld headers + canon.o)"; exit 1; }
gcc -std=gnu89 -w -DBREADBOX=0 -I"$LDDIR" -o "$OUT/mkarz" "$HERE/mkarz.c" "$LDDIR/canon.o"

ncc=0; skip=""
for c in "$OSL"/libm/*.c; do
	[ -f "$c" ] || continue
	b=$(basename "$c" .c)
	c900_buildlog "$c"
	if "$O/cc0-z8001" $VAR "$c" "$OUT/obj/$b.z0" $INC >/dev/null 2>&1 \
	 && "$O/cc1-z8001" $VAR "$OUT/obj/$b.z0" "$OUT/obj/$b.z1" >/dev/null 2>&1 \
	 && "$O/cc2-z8001" 0010 "$OUT/obj/$b.z1" "$OUT/obj/$b.o" "$OUT/obj/$b.scr" 0 >/dev/null 2>&1; then
		ncc=$((ncc+1))
	else
		skip="$skip $b"
	fi
	rm -f "$OUT/obj/$b.z0" "$OUT/obj/$b.z1" "$OUT/obj/$b.scr"
done

"$OUT/mkarz" "$OUT/libm-z8001.a" "$OUT"/obj/*.o
echo "libm-z8001: libm-z8001.a  ($ncc C objects, $(stat -c%s "$OUT/libm-z8001.a") B)"
if [ -n "$skip" ]; then
	echo "libm-z8001: THESE SOURCES DID NOT COMPILE:$skip" >&2
	exit 1
fi
rm -f "$OUT/mkarz"
publish_dir libm-z8001
trap - EXIT INT TERM			# $OUT is published now

# ---- smoke: a program that pulls sqrt from the archive ----
# The link is deliberately crt0-less (entry is f_ itself), so it must supply the
# absolute symbols crt0 would have defined: SS and errno_, which libm's domain-error
# paths reference.  csu/crts0.s has the definitions -- errno_ = SS|0xFFFE.
# runner.sh's refusal is the diagnostic; swallowing it and substituting a path
# that cannot exist turned "no emulator" into a SKIPPED smoke and a green build.
N2=${N2:-$(sh "$HERE/runner.sh")} || exit 1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '\t.globl\tSS\nSS = 0\n\t.globl\terrno_\nerrno_ = 0x0000FFFE\n' > "$T/ss.s"
"$AS" -o "$T/ss.o" "$T/ss.s" 2>/dev/null
printf '#include <math.h>\nf(){ return (int)sqrt(144.0); }\n' > "$T/p.c"
"$O/cc0-z8001" $VAR "$T/p.c" "$T/p.z0" $INC >/dev/null 2>&1
"$O/cc1-z8001" $VAR "$T/p.z0" "$T/p.z1" >/dev/null 2>&1
"$O/cc2-z8001" 0010 "$T/p.z1" "$T/p.o" "$T/scr" 0 >/dev/null 2>&1
"$BUILD/ld-z8001" -R 0x200 -e f_ -o "$T/a.out" "$T/p.o" "$T/ss.o" \
	"$PUB/libm-z8001.a" "$LIBC/libc-z8001.a"
[ -x "$N2" ] || { echo "libm smoke: no guest runner at '$N2'" >&2; exit 1; }
r=$("$N2" -runobjint "$T/a.out" 2>/dev/null | grep -oP 'R1 = \K-?[0-9]+') || r=
[ "$r" = 12 ] || { echo "libm smoke: got [$r] want 12  FAIL" >&2; exit 1; }
echo "libm smoke: (int)sqrt(144.0) = 12  PASS"
