#!/bin/sh
# build-libmisc-z8001.sh - build usr.lib-3.x/misc as libmisc-z8001.a on the host.
# It's the Coherent "misc" support library (alloc/fatal/usage/regexp/getline/match/
# span/skip/qsort/...) that several utilities (cgrep, ...) link against.  Mirrors
# build-libm-z8001.sh: cc0->cc1->cc2 each .c, mkarz into the archive.  A few files
# carry an #ifdef test main() that never fires in library use.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/coherent-os.sh"; OSL="$COHERENT_OS"
. "$HERE/publish.sh"			# $BUILD, stagedir, publish_dir
. "$HERE/buildlog.sh"			# c900_buildlog: records $C900_BUILD_LOG, or nothing
O="$BUILD/z8001"
LDDIR="$BUILD/ld"
OUT=$(stagedir libmisc-z8001)
VAR="${VAR:-800000020800}"
INC="-I$OSL/usr.lib-3.x/misc -I$OSL/include -I$OSL/include/sys"
trap 'rm -rf "$OUT"' EXIT INT TERM
mkdir -p "$OUT/obj"

[ -f "$LDDIR/canon.o" ] || { echo "run build-ld.sh first (need build/ld headers + canon.o)"; exit 1; }
gcc -std=gnu89 -w -DBREADBOX=0 -I"$LDDIR" -o "$OUT/mkarz" "$HERE/mkarz.c" "$LDDIR/canon.o"

ncc=0; skip=""
for c in "$OSL"/usr.lib-3.x/misc/*.c; do
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
"$OUT/mkarz" "$OUT/libmisc-z8001.a" "$OUT"/obj/*.o
echo "libmisc-z8001: libmisc-z8001.a  ($ncc objects, $(stat -c%s "$OUT/libmisc-z8001.a") B)"
if [ -n "$skip" ]; then
	echo "libmisc-z8001: THESE SOURCES DID NOT COMPILE:$skip" >&2
	exit 1
fi
rm -f "$OUT/mkarz"
publish_dir libmisc-z8001
trap - EXIT INT TERM			# $OUT is published now
