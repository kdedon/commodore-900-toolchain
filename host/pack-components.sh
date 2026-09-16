#!/bin/sh
# pack-components.sh - cut the toolchain's remaining release packages: the
# ones commodore-900-dist declares that host/release-pack.sh does not cut.
#
#	sh host/pack-components.sh [VERSION] [DESTDIR]
#
# release-pack.sh cuts the four single-archive kinds dist/packages already
# named (compiler, z8001, libc, include).  Three more belong to this
# repository and had no packer:
#
#   codegen           dist/packages/codegen.pkg: the 86 self-host fixpoint
#                      objects (host-run cross passes), evidence for
#                      check-patch-bump.sh's next-release comparison.
#   toolchain-src      the userland's generic dist/packages/component-src.pkg
#                      (@C@=toolchain), because the userland no longer carries
#                      a toolchain-src obligation of its own (dist/lists/
#                      toolchain.list dropped its `package' line) and every
#                      other -src package now names this one via
#                      `toolchain_src' instead of copying src/csu, src/libm
#                      and src/libmisc.
#   toolchain-man      the same userland dist/packages/component-man.pkg
#                      (@C@=toolchain): the Lexicon articles this repository
#                      owns -- the C language, the compiler passes, and the C
#                      library it builds.
#
# toolchain-1985 (vendor/mwc-1985, the recovered 1985 binaries) is cut too,
# in the same flat single-archive shape as compiler/z8001/libc/include,
# because it answers for bytes with no source in any repository here and the
# component-bin.pkg template's identity assertion (`ulid' or
# `kernel_linkid') names producers that are not this one.  No .pkg in either
# repository currently names a `toolchain-1985' kind; see the run notes this
# packing was done for.  It is written and judged the same way, but
# commodore-900-dist's check-package.sh has nothing to recognise it by.
#
# Prereqs: make all libc, sh host/build-libm-z8001.sh, sh
# host/build-libmisc-z8001.sh, sh host/build-selfhost2.sh -hostonly.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/publish.sh"			# $BUILD
. "$HERE/provenance.sh"		# prov_srcid, prov_repo

V=${1:-}
[ -n "$V" ] || V=$(git -C "$ROOT" describe --tags --match 'v[0-9]*' --dirty 2>/dev/null || true)
V=${V#v}
[ -n "$V" ] || { echo "pack-components.sh: no version." >&2; exit 2; }
DEST=${2:-$BUILD/dist}
mkdir -p "$DEST"

W=$(stage_at "$DEST/pack-components")
trap 'rm -rf "$W"' EXIT INT TERM

Z="$BUILD/z8001"
[ -f "$Z/.provenance" ] || { echo "pack-components.sh: $Z/.provenance is missing -- run \`make all'" >&2; exit 1; }
TCID=$(sed -n 's/^tcid=//p' "$Z/.provenance" | head -1)
COMMIT=$(sed -n 's/^commit=//p' "$Z/.provenance" | head -1)
CC0=$(sed -n 's/^cc0=//p' "$Z/.provenance" | head -1)
CC1=$(sed -n 's/^cc1=//p' "$Z/.provenance" | head -1)
CC2=$(sed -n 's/^cc2=//p' "$Z/.provenance" | head -1)
CC3=$(sed -n 's/^cc3=//p' "$Z/.provenance" | head -1)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

seal() {			# seal <tree> -- same rule as release-pack.sh
	( cd "$1" && find . -type f ! -path ./.contents ! -path ./.provenance -print |
	  LC_ALL=C sort | sed 's|^\./||' | xargs md5sum ) > "$1/.contents"
	echo "contentid=$(sha1sum "$1/.contents" | cut -c1-12)" >> "$1/.provenance"
	chmod 644 "$1/.contents" "$1/.provenance"
}
canon_modes() {
	find "$1" -type d -exec chmod 755 {} +
	find "$1" -type f -exec chmod 644 {} +
}

nbad=0
refuse() { echo "pack-components.sh: $1: $2" >&2; nbad=$((nbad + 1)); }
kv() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1; }

# judge <dir> <keys> <files> <glob:count...> -- the same shape as
# release-pack.sh's own judge(), read back after the tarball is written so a
# bad cut is refused here rather than left for a consumer to find.
judge() {
	_a=$1; _u=$2; _keys=$3; _files=$4; _globs=$5
	[ "$(sed -n 1p "$_u/VERSION" 2>/dev/null)" = "$V" ] ||
		refuse "$_a" "version.match: VERSION does not say $V"
	for _k in $_keys; do
		[ -n "$(kv "$_u/.provenance" "$_k")" ] || refuse "$_a" "stamp.keys: .provenance carries no $_k"
	done
	for _f in LICENSE $_files; do
		[ -s "$_u/$_f" ] || refuse "$_a" "file.present: $_f is missing or empty"
	done
	for _g in $_globs; do
		_c=$(cd "$_u" && eval "ls -d ${_g%:*}" 2>/dev/null | wc -l)
		[ "$_c" -ge "${_g##*:}" ] ||
			refuse "$_a" "glob.count: ${_g%:*} matches $_c, at least ${_g##*:} are carried"
	done
	[ -f "$_u/.contents" ] || { refuse "$_a" "file.present: .contents is missing"; return; }
	(cd "$_u" && md5sum --quiet -c .contents) > "$W/md5" 2>&1 ||
		refuse "$_a" "contents.md5: $(grep -v '^md5sum:' "$W/md5" | head -1)"
}

# ---- codegen: the 86 self-host fixpoint objects (host-run cross passes) ----
H2="$BUILD/selfhost/root/work/h2"
if [ -d "$H2" ] && [ "$(ls -1 "$H2"/*.o 2>/dev/null | wc -l)" -ge 80 ]; then
	cname=c900-toolchain-v$V-codegen
	CG="$W/$cname"
	mkdir -p "$CG"
	cp "$H2"/*.o "$CG/"
	echo "$V" > "$CG/VERSION"
	cp "$ROOT/LICENSE" "$CG/"
	nobj=$(ls -1 "$CG"/*.o | wc -l)
	{
		echo "kind=codegen"
		echo "commit=$COMMIT"
		echo "version=$V"
		echo "package=codegen"
		echo "built=$NOW"
		echo "tcid=$TCID"
		echo "cc0=$CC0"
		echo "cc1=$CC1"
		echo "cc2=$CC2"
		echo "cc3=$CC3"
		echo "objects=$nobj"
	} > "$CG/.provenance"
	canon_modes "$CG"
	seal "$CG"
	( cd "$W" && tar czf "$cname.tar.gz" "$cname" )
	judge "$cname.tar.gz" "$W/$cname" "kind commit version package tcid cc0 cc1 cc2 cc3 objects" "" "*.o:80"
else
	echo "pack-components.sh: codegen: skipped -- $H2 has no 86-object set (run \`sh host/build-selfhost2.sh -hostonly')" >&2
fi

# ---- toolchain-src: dist/packages/component-src.pkg, @C@=toolchain ----
# The complete corresponding source for the compiler passes, the assembler and
# the linker (compiler.pkg's programs), plus the recipe that builds them and,
# by ruling R7-114t/3, the runtime source every -src package elsewhere now
# names this package for instead of copying: src/csu, src/libm, src/libmisc.
sname=c900-toolchain-src-v$V
SR="$W/$sname/files"
mkdir -p "$SR"
for d in cc as ld csu libm libmisc; do
	cp -r "$ROOT/src/$d" "$SR/$d"
done
mkdir -p "$SR/host"
for f in build-cc.sh build-as.sh build-ld.sh build-libc-z8001.sh \
	 build-libm-z8001.sh build-libmisc-z8001.sh shims.sh provenance.sh \
	 publish.sh gensys.sh gensrc.sh coherent-os.sh; do
	cp "$ROOT/host/$f" "$SR/host/$f"
done
cp -r "$ROOT/host/shims" "$SR/host/shims"
echo "$V" > "$W/$sname/VERSION"
cp "$ROOT/LICENSE" "$W/$sname/"
{
	echo "# manifest.tab -- toolchain-src, PACKAGE-FORMAT's component-src.pkg shape"
	for d in cc as ld csu libm libmisc; do echo "t files/$d 644 0 1"; done
	for f in build-cc.sh build-as.sh build-ld.sh build-libc-z8001.sh \
		 build-libm-z8001.sh build-libmisc-z8001.sh shims.sh provenance.sh \
		 publish.sh gensys.sh gensrc.sh coherent-os.sh; do
		echo "f files/host/$f 644 0 1"
	done
	echo "t files/host/shims 644 0 1"
} > "$W/$sname/manifest.tab"
PROGRAMS=6	# cc0 cc1 cc2 cc3 as ld -- compiler.pkg's Z8001 passes and tools
MAPPED=6	# src/cc (four passes), src/as, src/ld: all present above
entries=$(find "$SR" -mindepth 1 -maxdepth 1 | wc -l)
{
	echo "kind=component-src"
	echo "commit=$COMMIT"
	echo "version=$V"
	echo "package=toolchain-src"
	echo "component=toolchain"
	echo "pkgkind=src"
	echo "built=$NOW"
	echo "entries=$entries"
	echo "programs=$PROGRAMS"
	echo "mapped=$MAPPED"
} > "$W/$sname/.provenance"
canon_modes "$W/$sname"
seal "$W/$sname"
( cd "$W" && tar czf "$sname.tar.gz" "$sname" )
judge "$sname.tar.gz" "$W/$sname" \
	"kind commit version package component pkgkind entries programs mapped" \
	"manifest.tab" "files/*:1"
[ "$PROGRAMS" = "$MAPPED" ] || refuse "$sname.tar.gz" "keymatch: programs=$PROGRAMS mapped=$MAPPED"

# ---- toolchain-man: dist/packages/component-man.pkg, @C@=toolchain ----
# man/ here already IS the toolchain's whole manual: the C language and
# preprocessor (COHERENT.1), the C library this repository builds
# (COHERENT.2), the three compiler passes documented in COHERENT.1 (cc0,
# cc1, cc2), and the three programs this repository builds for the machine
# (as, cc, ld).  No subsetting is needed the way the userland's man/ needs
# it, because this repository owns nothing else the manual could be
# describing.
mname=c900-toolchain-man-v$V
MR="$W/$mname/files"
mkdir -p "$MR"
cp -r "$ROOT/man/COHERENT.1" "$MR/COHERENT.1"
cp -r "$ROOT/man/COHERENT.2" "$MR/COHERENT.2"
cp "$ROOT/man/man.index" "$MR/man.index"
echo "$V" > "$W/$mname/VERSION"
cp "$ROOT/LICENSE" "$W/$mname/"
{
	echo "# manifest.tab -- toolchain-man, PACKAGE-FORMAT's component-man.pkg shape"
	echo "f man.index 644 0 1"
	(cd "$MR" && find COHERENT.1 COHERENT.2 -type f | LC_ALL=C sort |
		while read -r p; do echo "f $p 644 0 1"; done)
} > "$W/$mname/manifest.tab"
DOCUMENTED=5	# of PROGRAMS: cc0, cc1, cc2, as and ld carry a page in
		# COHERENT.1; cc3 does not.  The driver's own page, COHERENT.1/cc,
		# is carried too and is not counted here: cc is not one of the six
		# programs compiler.pkg names.
mentries=$(find "$MR" -mindepth 1 -maxdepth 1 | wc -l)
{
	echo "kind=component-man"
	echo "commit=$COMMIT"
	echo "version=$V"
	echo "package=toolchain-man"
	echo "component=toolchain"
	echo "pkgkind=man"
	echo "built=$NOW"
	echo "entries=$mentries"
	echo "programs=$PROGRAMS"
	echo "documented=$DOCUMENTED"
	echo "libraries=libc"
} > "$W/$mname/.provenance"
canon_modes "$W/$mname"
seal "$W/$mname"
( cd "$W" && tar czf "$mname.tar.gz" "$mname" )
judge "$mname.tar.gz" "$W/$mname" \
	"kind commit version package component pkgkind entries programs documented libraries" \
	"manifest.tab files/man.index" "files/COHERENT.*/*:1"

# ---- toolchain-1985: vendor/mwc-1985, no dist .pkg names this kind ----
# The twelve bytes lists/toolchain-1985.list stages (cc, ccx, db, l, nld,
# cc0..cc3, cpp, scrts0.o, slibc.a -- ar/as/ld/nm/size sit beside them in
# vendor/mwc-1985 and are not staged by any list) have no source in any
# repository here, so this is a payload package: VERSION, LICENSE and a
# content id, and .provenance says so with `payload=' rather than a tcid.
tname=c900-toolchain-1985-v$V
TD="$W/$tname/bin"
mkdir -p "$TD"
for f in cc ccx db l nld cc0 cc1 cc2 cc3 cpp scrts0.o slibc.a; do
	cp "$ROOT/vendor/mwc-1985/$f" "$TD/$f"
done
echo "$V" > "$W/$tname/VERSION"
cp "$ROOT/LICENSE" "$W/$tname/"
{
	echo "kind=toolchain-1985"
	echo "commit=$COMMIT"
	echo "version=$V"
	echo "package=toolchain-1985"
	echo "built=$NOW"
	echo "payload=vendor/mwc-1985 has no source in any repository of ours"
} > "$W/$tname/.provenance"
canon_modes "$W/$tname"
seal "$W/$tname"
( cd "$W" && tar czf "$tname.tar.gz" "$tname" )
judge "$tname.tar.gz" "$W/$tname" "kind commit version package payload" "" "bin/*:12"

if [ "$nbad" -gt 0 ]; then
	echo "pack-components.sh: $nbad assertion(s) failed; nothing was left in $DEST" >&2
	exit 1
fi
echo "judged: every component package matches its .contents and .provenance"
for f in "$W"/*.tar.gz; do
	[ -f "$f" ] || continue
	mv "$f" "$DEST/"
	echo "packed: $DEST/$(basename "$f")"
done

# end of pack-components.sh
