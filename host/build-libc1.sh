#!/bin/sh
# build-libc1.sh - build the Z8001 shared C library, libc.1.
#
# libc's members compiled -VPIC, plus csu/slrt.s, through slgen: a shared
# segment (code, read-only tables, export table at 0) and a private one (data
# and bss, copied per client).  src/libc/libc.1.exp is the ABI.
#
# Publishes $BUILD/libc1/{libc.1,crt0sl.o}; a client links crt0sl.o in place
# of crt0.o.
#
# Prereq: build-as.sh, build-ld.sh, `make slgen', build-libc-z8001.sh.
# Usage: build-libc1.sh [-v]
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/coherent-os.sh"		# $COHERENT_OS -- this repo's src/
. "$HERE/publish.sh"			# $BUILD, stagedir, publish_dir

AS="$BUILD/as-z8001"
LD="$BUILD/ld-z8001"
SLGEN="$BUILD/slgen"
LIBC="$BUILD/libc-z8001-pic"
EXP="$COHERENT_OS/libc/libc.1.exp"
verbose=
[ "${1:-}" = -v ] && verbose=-v

for f in "$AS" "$LD" "$SLGEN" "$BUILD/libc-z8001/obj" "$EXP"; do
	[ -e "$f" ] || { echo "build-libc1: missing $f -- build the tool chain and libc first" >&2; exit 1; }
done

# The same sources as the static archive, compiled -VPIC.  Every slot inside
# the library is local: ld fills it and the fixup list patches its segment.
LIBCNAME=libc-z8001-pic VAR=800000020808 sh "$HERE/build-libc-z8001.sh" >/dev/null

OUT=$(stagedir libc1)
trap 'rm -rf "$OUT"' EXIT INT TERM

# The library's own start-off glue, and the client's.
"$AS" -o "$OUT/slrt.o"   "$COHERENT_OS/csu/slrt.s"
"$AS" -o "$OUT/crt0sl.o" "$COHERENT_OS/csu/crt0sl.s"

# Excluded members:
#   _prof.o    refers to etext_, which is per-program and cannot be in a library
#   strrchr.o  strrchr_ defined twice (gen/strchr.c has the other)
#   _finish.o  _finish_ defined twice; stdio/finit.c's is the one a libc with
#              stdio wants
members=$(ls "$LIBC"/obj/*.o | grep -vE '/(_prof|strrchr|_finish)\.o$')
nmem=$(echo "$members" | wc -w)

"$SLGEN" $verbose -A "$AS" -L "$LD" -T "$OUT" -e "$EXP" -o "$OUT/libc.1" \
	"$OUT/slrt.o" $members

rm -f "$OUT"/slrt.o
publish_dir libc1
trap - EXIT INT TERM

# A library past either 64 KB ceiling cannot load; say so here.
python3 - "$BUILD/libc1/libc.1" "$nmem" "$EXP" <<'PY'
import sys
b = open(sys.argv[1], 'rb').read()
sh = lambda o: b[o] | b[o+1] << 8
ln = lambda o: ((b[o] | b[o+1] << 8) << 16) | (b[o+2] | b[o+3] << 8)
SHRI, PRVI, BSSI, SHRD, PRVD, BSSD = range(6)
sz = [ln(8 + 4*i) for i in range(9)]
shared = sz[SHRI] + sz[SHRD]
private = sz[PRVI] + sz[BSSI] + sz[PRVD] + sz[BSSD]
tb = sh(6)				# the shared segment starts the file
nexp = (b[tb+4] << 8) | b[tb+5]		# sl_nexp, plain big-endian target bytes
nfix = (b[tb+8] << 8) | b[tb+9]
nlist = sum(1 for l in open(sys.argv[3])
            if l.strip() and not l.lstrip().startswith('#'))
print("libc.1: %d B on disk, %s members + slrt.o, %d exports (list names %d), %d fixups"
      % (len(b), sys.argv[2], nexp, nlist, nfix))
print("  shared  seg  SHRI %6d + SHRD %5d = %6d B of 65536  (%d B free)"
      % (sz[SHRI], sz[SHRD], shared, 65536 - shared))
print("  private seg  PRVD %6d + BSSD %5d = %6d B of 65536  (%d B free)"
      % (sz[PRVD], sz[BSSD], private, 65536 - private))
if shared > 65536 or private > 65536:
    raise SystemExit("build-libc1: a segment is over 64 KB")
PY
