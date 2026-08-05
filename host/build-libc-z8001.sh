#!/bin/sh
# build-libc-z8001.sh - build the Coherent 3.2 Z8001 C library (crt0 + libc-z8001.a)
# on the host, so cc2-z8001 output links into runnable C900 l.out binaries.
#   as-z8001  csu/crts0.s + libc/*/*.s   -> crt0.o + syscall/asm stubs
#   cc0/cc1/cc2-z8001  libc/*/*.c        -> compiled libc objects
#   mkarz     *.o                        -> libc-z8001.a  (Coherent ar: ARMAG + members;
#                                           ld does the linear member scan, no __.SYMDEF)
#
# SOURCE is the in-tree COHERENT 3.2 stack under coherent/os (NOT the 0.7.3 donor):
# $COHERENT_OS/{libc,csu} compiled against its include/ -- the SAME headers the kernel
# builds against (host/build.sh), so libc + userland + kernel share one header
# set.  See memory coherent-32-unified-target.
# Prereq: build-z8001.sh (APPENDBAR: C names carry the trailing '_'), build-cc2-z8001.sh,
# build-as.sh, build-ld.sh.  VREADONLY (VAR bit 25) lets cc0 accept ctype.h's `readonly'.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/coherent-os.sh"
. "$HERE/publish.sh"			# $BUILD, stagedir, publish_dir
. "$HERE/buildlog.sh"			# c900_buildlog: records $C900_BUILD_LOG, or nothing
OSL="$COHERENT_OS"			# the COHERENT 3.2 OS tree (headers + libc + csu)
O="$BUILD/z8001"
AS="$BUILD/as-z8001"
LDDIR="$BUILD/ld"
PUB="$BUILD/libc-z8001"			# what ccz, build-env.sh and the tests read
OUT=$(stagedir libc-z8001)		# staging; renamed onto PUB once the archive is written
VAR="${VAR:-800000020800}"		# 800000000800 | VREADONLY(bit25)
INC="-I$OSL/include -I$OSL/include/sys"
trap 'rm -rf "$OUT"' EXIT INT TERM
mkdir -p "$OUT/obj"

# mkarz: minimal Coherent l.out archive writer (reuses ld's ar.h/canon for layout parity).
[ -f "$LDDIR/canon.o" ] || { echo "run build-ld.sh first (need build/ld headers + canon.o)"; exit 1; }
gcc -std=gnu89 -w -DBREADBOX=0 -I"$LDDIR" -o "$OUT/mkarz" "$HERE/mkarz.c" "$LDDIR/canon.o"

# ---- crt0 + the .s stubs (syscalls, string ops, soft-float) --------------------
"$AS" -o "$OUT/crt0.o" "$OSL/csu/crts0.s"
nas=0; asfail=""
for s in "$OSL"/libc/sys/*.s "$OSL"/libc/gen/*.s "$OSL"/libc/crt/*.s; do
	[ -f "$s" ] || continue
	b=$(basename "$s" .s)
	c900_buildlog "$s"
	"$AS" -o "$OUT/obj/$b.o" "$s" 2>/dev/null && nas=$((nas+1)) || asfail="$asfail $b"
done
[ -z "$asfail" ] || { echo "libc-z8001: as-z8001 REJECTED:$asfail" >&2; exit 1; }

# ---- the .c library sources (cc0->cc1->cc2).  sdtoa.c is the DUMMY _dtefg stub
# ("No floating point!"); the real dtefg.c now compiles, so drop the stub (else it
# wins the gen/-before-crt/ archive scan and every float print aborts).
#
# EVERY remaining source must compile.  A file that does not is collected and the
# build is REFUSED below: this harness is `make libc', a CI stage, and a compiler
# regression that stops ten library sources compiling would otherwise print a
# line naming them and exit 0 -- a green stage over a library that lost members.
# The expected skip set is empty, and an empty set is the only baseline that
# cannot rot. ----
ncc=0; skip=""
compile_c() {	# <src> ; compiles $1 -> $OUT/obj/<base>.o, updates ncc/skip
	local c="$1" b; b=$(basename "$c" .c)
	c900_buildlog "$c"
	if "$O/cc0-z8001" $VAR "$c" "$OUT/obj/$b.z0" $INC >/dev/null 2>&1 \
	 && "$O/cc1-z8001" $VAR "$OUT/obj/$b.z0" "$OUT/obj/$b.z1" >/dev/null 2>&1 \
	 && "$O/cc2-z8001" 0010 "$OUT/obj/$b.z1" "$OUT/obj/$b.o" "$OUT/obj/$b.scr" 0 >/dev/null 2>&1; then
		ncc=$((ncc+1))
	else
		skip="$skip $b"
	fi
	rm -f "$OUT/obj/$b.z0" "$OUT/obj/$b.z1" "$OUT/obj/$b.scr"
}
for c in "$OSL"/libc/gen/*.c "$OSL"/libc/stdio/*.c "$OSL"/libc/sys/*.c "$OSL"/libc/crt/*.c; do
	[ -f "$c" ] || continue
	b=$(basename "$c" .c)
	[ "$b" = sdtoa ] && continue
	# os/libc's malloc.c/realloc.c are the OLD alloc_t allocator; include/sys/malloc.h
	# is the newer MBLOCK API (a 4.0 backport).  Use the matching MBLOCK malloc/realloc
	# from libc-4.2 instead (added below).  os/libc calloc.c is API-agnostic -- keep it.
	{ [ "$b" = malloc ] || [ "$b" = realloc ]; } && continue
	compile_c "$c"
done
# MBLOCK malloc/realloc matching include/sys/malloc.h (self-contained: malloc/free/realloc).
# Named, and REQUIRED.  These three came in through `[ -f "$c" ] && compile_c',
# so an OS tree without libc-4.2 produced an archive with no malloc, free or
# realloc in it -- and the smoke test below calls strlen and strcmp, so it
# passed.  A missing input is a build failure, not a smaller library.
for c in "$OSL"/libc-4.2/stdlib/malloc/malloc.c "$OSL"/libc-4.2/stdlib/malloc/realloc.c "$OSL"/libc-4.2/stdlib/malloc/memok.c; do
	[ -f "$c" ] || { echo "libc-z8001: no $c -- the archive would have no malloc" >&2; exit 1; }
	compile_c "$c"
done

# ---- archive (all compiled + assembled members except crt0, which stays standalone) ----
"$OUT/mkarz" "$OUT/libc-z8001.a" "$OUT"/obj/*.o
echo "libc-z8001: crt0.o + libc-z8001.a  ($nas asm, $ncc C objects, $(stat -c%s "$OUT/libc-z8001.a") B)"
if [ -n "$skip" ]; then
	echo "libc-z8001: THESE SOURCES DID NOT COMPILE:$skip" >&2
	echo "  (host/buildlog.sh holds each one's diagnostics)" >&2
	exit 1
fi
rm -f "$OUT/mkarz"
publish_dir libc-z8001
trap - EXIT INT TERM			# $OUT is published now

# ---- smoke: a real program that pulls from the archive ----
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '\t.globl\tSS\nSS = 0\n' > "$T/ss.s"; "$AS" -o "$T/ss.o" "$T/ss.s" 2>/dev/null
printf 'f(){ return strlen("hello") + strcmp("a","a"); }\n' > "$T/p.c"
"$O/cc0-z8001" $VAR "$T/p.c" "$T/p.z0" $INC >/dev/null 2>&1
"$O/cc1-z8001" $VAR "$T/p.z0" "$T/p.z1" >/dev/null 2>&1
"$O/cc2-z8001" 0010 "$T/p.z1" "$T/p.o" "$T/scr" 0 >/dev/null 2>&1
"$BUILD/ld-z8001" -R 0x200 -e f_ -o "$T/a.out" "$T/p.o" "$T/ss.o" "$PUB/libc-z8001.a" 2>/dev/null
# The smoke is an ASSERTION, so its verdict is the script's exit status.  Printed
# and discarded, it announced a broken library and left the stage green.
N2=${N2:-$(sh "$HERE/runner.sh")} || exit 1
r=$("$N2" -runobjint "$T/a.out" 2>/dev/null | grep -oP 'R1 = \K-?[0-9]+')
[ "$r" = 5 ] || { echo "libc smoke: got '$r' (want 5)  FAIL" >&2; exit 1; }
echo "libc smoke: strlen(\"hello\")+strcmp(\"a\",\"a\") = 5  PASS"
