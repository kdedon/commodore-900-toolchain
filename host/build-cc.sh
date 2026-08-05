#!/bin/sh
# build-cc.sh - host cross-build of the Z8001 C compiler FROM the native source
# of record (src/cc).  Copies the tree to a scratch dir, applies the HOST
# SHIMS (LP64/glibc/gcc-strictness workarounds -- the full verdict table is
# docs/PATCHES.md), and builds tabgen + cc0-z8001 + cc1-z8001 + cc2-z8001 +
# cc3-z8001 (the IR printer) with gcc into build/z8001/ (the paths ccz and the
# tests use).
#
# Supersedes build-z8001.sh + build-cc2-z8001.sh (+ build-tabgen.sh) for the
# Z8001 pipeline, which is the only pipeline: there is no i386 harness.
# Every shim ASSERTS it changed its target -- if the native source drifts under
# a shim's pattern, the build fails loudly instead of silently diverging.
#
# build/z8001 is SHARED: the kernel link, the driver link, every userland sweep
# and every test harness in the tree spawn compilers out of it, so it is built
# privately and published by rename -- see host/publish.sh.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/publish.sh"				# $BUILD, stagedir, publish_dir/_file
. "$HERE/provenance.sh"				# prov_pub_check, prov_write, prov_srcid
. "$HERE/srcman.sh"				# srcman_list, srcman_check
# Asked BEFORE the build, not after it: the answer does not depend on anything
# the build produces, and a refusal is worth more before two minutes of gcc than
# after.  See prov_pub_check for what it refuses and why.
prov_pub_check "$BUILD" z8001 "$HERE" || exit 2
SRC="$ROOT/src/cc"				# native source of record
# What the compiler is made of is src/cc/Makefile's object lists (the NATIVE
# build's), read here so both builds compile one list.  Asked before the copy:
# an undeclared .c under src/cc is refused by name rather than shimmed and
# linked into the compiler this script publishes.
srcman_check cc "$SRC" || exit 2
OSI="$HERE/include"				# vendored Coherent headers the host lacks
W=$(stagedir cc)				# scratch working copy (shimmed)
PUB="$BUILD/z8001"				# what everything else reads
OUT=$(stagedir z8001)				# staging; renamed onto PUB at the end
trap 'rm -rf "$W" "$OUT"' EXIT INT TERM

mkdir -p "$W/shim" "$OUT/n0" "$OUT/n1" "$OUT/n2" "$OUT/n3" "$OUT/common" "$OUT/commch"
cp -r "$SRC"/h "$SRC"/common "$SRC"/n0 "$SRC"/n1 "$SRC"/n2 "$SRC"/n3 "$SRC"/coh "$SRC"/generated "$W/"

# src/cc/generated/ is the ONE copy of the machine-generated opcode tables:
# genz8001tab writes opcode.h straight into it and the compile below includes it
# from there.  (The generator itself is not in this repository -- it drives a
# decoder that is not public -- so opcode.h is a committed artifact here and
# nothing in this build regenerates it; see src/cc/generated/README.md.)  There used to be a second copy under
# z8001-backend/generated and a diff guard here to catch them drifting; with one
# copy there is nothing to drift.

# ---- host shims (host/shims/*.patch; the verdict table is docs/PATCHES.md) ----
. "$HERE/shims.sh"
shim_apply "$HERE/shims" "$W" || { echo "build-cc: host shims are stale against src/cc"; exit 1; }
# x86-64 UB: diag walks &args up the stack -> stdarg host port.  A whole-file
# replacement, so it is a copy and not a patch -- but it must REPLACE, and a
# copy over a file that has moved would silently add one instead.
[ -f "$W/common/diag.c" ] || { echo "build-cc: common/diag.c is gone; the host port replaces nothing"; exit 1; }
cp "$HERE/port/diag.c" "$W/common/diag.c"
# Coherent libc routine the host lacks
cp "$HERE/port/shellsort.c" "$W/n1/shellsort.c"
# Coherent headers the host lacks, vendored in host/include (cc0.c/cc.c
# include <path.h>, which pulls <access.h>; the 4.2-era common/feature.h shim is
# gone -- nothing on the Z8001 path consumes it once path.h is the 3.2 one)
cp "$OSI/path.h" "$W/shim/path.h"
cp "$OSI/access.h" "$W/shim/access.h"

# ---- tabgen (host) + the selection tables ----
# The scratch copy's name carries the pid so two builds cannot share it, and -g
# would then bake that name into every binary's debug info -- making the compiler
# differ between runs that compiled identical source.  Map it back to a fixed
# path so a rebuilt cc0-z8001 is byte-identical when nothing changed, which is
# how this project tells "it relinked" from "it did not".
DBGMAP="-fdebug-prefix-map=$W=$BUILD/cc"
gcc -std=gnu89 -w -DCOHERENT $DBGMAP -I "$W/n1/z8001" -I "$W/h/z8001" -I "$W/generated" -I "$W/h" -I "$W/coh" \
    -o "$OUT/tabgen" "$W/coh/tabgen.c"
( cd "$W/n1/tables" && "$OUT/tabgen" -s prefac.f *.t >/dev/null )

# ---- compile the passes (Z8001 IR widths: h/z8001 mch.h wins the include order) ----
INC="-I $W/n1/z8001 -I $W/n0/z8001 -I $W/h/z8001 -I $W/generated -I $W/n0 -I $W/n1 -I $W/h -I $W/shim -I $W/common"
cc1of() { gcc -std=gnu89 -g -w -c -DCOHERENT $DBGMAP $INC "$1" -o "$2" 2>>"$OUT/cc.err" \
	|| { echo "  CC ERR $1"; tail -3 "$OUT/cc.err"; exit 1; }; }
echo "--- compiling cc0/cc1/cc2/cc3-z8001 from src/cc ---"
# The declared list, not a glob of the directory.  A pass's own sources and its
# z8001/ ones flatten into one object directory (srcman_check refuses a name
# used twice); cc3 (the IR printer) additionally links common/z8001, the machine
# NAME tables, which build into commch/ rather than common/ because cc0/cc1/cc2
# do not link them -- TINY=1 compiles out the -S dumps that are their only other
# reader.  coh/ is not in this loop: coh/tabgen.c is built above, and coh/cc.c
# is the native driver, cross-built by host/build-native.sh.  n1/shellsort.c is
# the host's, a Coherent libc routine the host lacks.
for f in $(srcman_list cc "$SRC") n1/shellsort.c; do
	case $f in
	coh/*)		continue ;;
	common/z8001/*)	d=commch ;;
	*)		d=${f%%/*} ;;
	esac
	cc1of "$W/$f" "$OUT/$d/$(basename "${f%.c}").o"
done

# ---- link ----
gcc -g -o "$OUT/cc0-z8001" "$OUT"/n0/*.o "$OUT"/common/*.o \
  && echo "cc0-z8001: LINKED ($(stat -c%s "$OUT/cc0-z8001") B)"
gcc -g -o "$OUT/cc1-z8001" "$OUT"/n1/*.o "$OUT"/common/*.o \
  && echo "cc1-z8001: LINKED ($(stat -c%s "$OUT/cc1-z8001") B)"
gcc -g -o "$OUT/cc2-z8001" "$OUT"/n2/*.o "$OUT"/common/*.o \
  && echo "cc2-z8001: LINKED ($(stat -c%s "$OUT/cc2-z8001") B)"
gcc -g -o "$OUT/cc3-z8001" "$OUT"/n3/*.o "$OUT"/commch/*.o "$OUT"/common/*.o \
  && echo "cc3-z8001: LINKED ($(stat -c%s "$OUT/cc3-z8001") B)"

# ---- smoke: full cc0 -> cc1 -> cc2 on a K&R snippet ----
set +e
printf 'int g;\nint add(a, b) int a; int b; { return a + b; }\n' > "$OUT/smoke.c"
"$OUT/cc0-z8001" 800000 "$OUT/smoke.c" "$OUT/smoke.z0" 2>/dev/null &&
"$OUT/cc1-z8001" 800000 "$OUT/smoke.z0" "$OUT/smoke.z1" 2>/dev/null &&
"$OUT/cc2-z8001" 0010 "$OUT/smoke.z1" "$OUT/smoke.o" "$OUT/smoke.scr" 0 2>/dev/null \
  && echo "smoke: cc0->cc1->cc2 CLEAN ($(stat -c%s "$OUT/smoke.o") B object)" \
  || { echo "smoke: pipeline FAILED"; exit 1; }
# cc3 reads BOTH intermediates: the cc0 tree stream and the cc1 CODE stream.  A
# desynchronized reader shows up as a cbotch, so run it over both and insist on
# a clean exit -- that is the whole self-check this pass admits of.
"$OUT/cc3-z8001" 800000 "$OUT/smoke.z0" "$OUT/smoke.d0" >/dev/null 2>&1 &&
"$OUT/cc3-z8001" 800000 "$OUT/smoke.z1" "$OUT/smoke.d1" >/dev/null 2>&1 \
  && echo "smoke: cc3 read both intermediates CLEAN" \
  || { echo "smoke: cc3 FAILED"; exit 1; }
set -e

# ---- provenance ----
# Stamped INSIDE $OUT, so it is published by the same rename as the binaries and
# can never describe a different toolchain than the one at build/z8001.
#
# The scope is the compiler's OWN source, not the whole worktree.  A whole-tree
# dirty flag is on permanently here (several lanes, one checkout, 100+ modified
# files at any moment) and a warning that is always on gets read as decoration.
# `dirtysrc' counts only src/{cc,as,ld} plus this script -- it is nonzero
# exactly when these binaries correspond to no commit, which is the condition
# that once turned a local edit into a phantom compiler ICE reported to another
# lane as a source bug.
#
# `tcid' is the same scope reduced to one name: the id a consumer records and
# compares against on its next build, so a compiler swapped underneath a half
# built system is a refusal rather than a wrong object.  It names the SOURCE
# (see prov_srcid) -- the binaries below differ between build directories even
# when nothing was changed, so their hashes describe the build and only the id
# describes the compiler.
TCSCOPE="src/cc src/as src/ld host"
# shellcheck disable=SC2086
prov_write "$OUT/.provenance" toolchain \
	$TCSCOPE \
	-- "tcid=$(prov_srcid "$(prov_repo "$HERE")" $TCSCOPE)" \
	   "cc0=$(sha1sum "$OUT/cc0-z8001" | cut -c1-12)" \
	   "cc1=$(sha1sum "$OUT/cc1-z8001" | cut -c1-12)" \
	   "cc2=$(sha1sum "$OUT/cc2-z8001" | cut -c1-12)" \
	   "cc3=$(sha1sum "$OUT/cc3-z8001" | cut -c1-12)"

# ---- publish ----
publish_dir z8001
trap 'rm -rf "$W"' EXIT INT TERM		# $OUT is published now; do not remove it

# tabgen is read by build-selfhost.sh, a separate track: install it by rename
# too rather than truncating it under that build.
publish_file "$PUB/tabgen" tabgen
echo "published: $PUB -> z8001.$$"
prov_header "toolchain" "$PUB/.provenance" || true
