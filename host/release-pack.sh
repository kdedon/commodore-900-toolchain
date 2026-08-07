#!/bin/sh
# release-pack.sh - package the three deliverables into the release assets.
#
#	sh host/release-pack.sh [VERSION] [DESTDIR]	# VERSION = the tag, without the v
#
# VERSION defaults to what `git describe' says this checkout is, DESTDIR to
# $BUILD/dist.  Writes, for
# the host it is run on:
#
#	c900-toolchain-vX.Y.Z-<host>.tar.gz|.zip   deliverables 1|2 + 3
#	c900-toolchain-vX.Y.Z-z8001.tar.gz         deliverable 3 alone
#	c900-toolchain-vX.Y.Z-codegen.tar.gz       the fixpoint objects (below)
#
# Deliverable 3 rides in the host archive AND ships alone: it is
# host-independent, so shipping it twice looks redundant, but a Windows user
# must not have to work out that a second archive is needed to build anything
# for the machine, and an image builder wanting only the native binaries should
# not download a host compiler to get them.  150 KB against archives measured
# in megabytes.
#
# The codegen archive is not a deliverable, it is the EVIDENCE for the version
# number: the 86 objects the self-host fixpoint (S3) produced.  They are
# deterministic -- the target-run passes reproduce them byte for byte with no
# host clock involved -- so the next release can compare against them and refuse
# a PATCH bump that moved an emitted byte.  See check-patch-bump.sh.
#
# Prereqs: make all, make libc selfhost native, make check-selfhost.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/publish.sh"			# $BUILD

# THE TAG IS THE VERSION, and it is the only statement of it: there is no
# VERSION file in this repository to disagree with the tag that started the
# release.  Given as an argument (CI passes the tag it was triggered by), or
# read from the checkout's own description when packing by hand.  A tree with no
# tag reachable cannot name what it is packing, and is refused rather than
# guessed at -- an archive called 0.0.0 outlives whoever knew what it held.
# `|| true' is not decoration: under set -e an assignment whose command
# substitution fails takes the script with it, and a tagless tree would exit 128
# having said nothing at all.  The refusal below is the diagnosis.
V=${1:-}
[ -n "$V" ] || V=$(git -C "$ROOT" describe --tags --match 'v[0-9]*' --dirty 2>/dev/null || true)
V=${V#v}
[ -n "$V" ] || {
	echo "release-pack.sh: no version." >&2
	echo "  The tag names it: pass it as the first argument, or pack from a" >&2
	echo "  checkout with a v* tag reachable (git describe finds none here)." >&2
	exit 2
}
DEST=${2:-$BUILD/dist}
case $(uname -s) in
Linux)			HOSTTAG=linux-x86_64;   ARCH=tar; X= ;;
MINGW*|MSYS*|CYGWIN*)	HOSTTAG=windows-x86_64; ARCH=zip; X=.exe ;;
*)	echo "release-pack.sh: no asset is defined for $(uname -s)" >&2; exit 2 ;;
esac

. "$HERE/coherent-os.sh"		# usr/include ships WITH the archive

# ---- release identity: WHICH COHERENT source is inside this archive ----
#
# The archive carries usr/include and native/libc-z8001.a, libm and libmisc,
# and none of that source is in this repository.  A tag that cannot name the
# OS commit those came from cannot be rebuilt by anybody, including us -- and
# while the OS repository is unpublished, the commit id is the ONLY thing that
# will still identify them on the day it is public.  A path is not an answer (it
# names a machine), and a date is not an answer (it names nothing).  So the
# commit is recorded here, by the packer, and the same stamp goes into every
# archive whether it was packed by CI or by hand.
#
# A tree that cannot supply one is refused rather than packed with something
# weaker.  Dirt is measured over the three directories this archive actually
# consumes, never the whole tree: an OS checkout in use normally carries other
# work, and an alarm that is always on is read as decoration.
# A SNAPSHOT answers this too, and answers it better: it was cut by
# host/pack-coherent-os.sh, which refuses a dirty or unversioned tree, so its
# .provenance names a commit that describes the sources exactly.
#
# ITS .provenance IS ASKED FIRST, and that order is load-bearing.  `make deps'
# unpacks the snapshot at external/, which is inside THIS repository's working tree
# -- gitignored, but still inside it -- so `git rev-parse' run there answers
# with the TOOLCHAIN's commit, and the archive would name this repository as the
# source of somebody else's C library.  It did, once, before this test moved up.
if [ -f "$COHERENT_OS/.provenance" ]; then
	COHTREE=$COHERENT_OS
	COHCOMMIT=$(awk '$1=="commit"{print $2}' "$COHERENT_OS/.provenance")
	COHDIRTY=0
	[ -n "$COHCOMMIT" ] || {
		echo "release-pack.sh: $COHERENT_OS/.provenance names no commit." >&2
		exit 1
	}
else
	COHTREE=$(git -C "$COHERENT_OS" rev-parse --show-toplevel 2>/dev/null) || COHTREE=
	if [ -z "$COHTREE" ]; then
		echo "release-pack.sh: COHERENT_OS=$COHERENT_OS is neither a git checkout" >&2
		echo "  nor an unpacked snapshot with a .provenance." >&2
		echo "  The libraries and headers in this archive come from there, so the" >&2
		echo "  release cannot say what it was built from and could not be rebuilt." >&2
		echo "  Pack from a checkout, or from what \`make deps DEP=coherent' places." >&2
		exit 1
	fi
	COHCOMMIT=$(git -C "$COHTREE" rev-parse HEAD)
	COHSCOPE="$COHERENT_OS/include $COHERENT_OS/libc $COHERENT_OS/csu"
	# shellcheck disable=SC2086
	COHDIRTY=$(git -C "$COHTREE" status --porcelain -- $COHSCOPE | wc -l)
fi
if [ "$COHDIRTY" -ne 0 ]; then
	echo "release-pack.sh: $COHDIRTY uncommitted file(s) in the OS source this" >&2
	echo "  archive is built from -- so commit $(echo "$COHCOMMIT" | cut -c1-8) does not describe it:" >&2
	# shellcheck disable=SC2086
	git -C "$COHTREE" status --porcelain -- $COHSCOPE | sed 's/^/    /' >&2
	if [ -n "${C900_RELEASE_ACCEPT_DIRTY_OS:-}" ]; then
		echo "  C900_RELEASE_ACCEPT_DIRTY_OS is set -- packing, and the archive's" >&2
		echo "  .provenance will say coherent_dirtysrc=$COHDIRTY." >&2
	else
		echo "  Commit them, or set C900_RELEASE_ACCEPT_DIRTY_OS=1 to pack a release" >&2
		echo "  whose .provenance says it matches no OS commit." >&2
		exit 1
	fi
fi

# mkarz is shipped, and nothing in this repository archives anything: arz builds
# it on first use, and its first use is in a CONSUMER's tree.  So the packer
# asks for it rather than waiting to find it missing.
sh "$HERE/arz" -b

# Named prerequisites, so a missing stage is refused by the target that builds
# it rather than as a cp diagnostic thirty lines in.
for p in "$BUILD/z8001/cc0-z8001:make all" \
	 "$BUILD/as-z8001:make all" \
	 "$BUILD/libc-z8001/libc-z8001.a:make libc" \
	 "$BUILD/libm-z8001/libm-z8001.a:sh host/build-libm-z8001.sh" \
	 "$BUILD/libmisc-z8001/libmisc-z8001.a:sh host/build-libmisc-z8001.sh" \
	 "$BUILD/mkarz:make ld -- host/arz -b compiles mkarz against its canon.o" \
	 "$BUILD/native/cc:make native"; do
	f=${p%:*}; t=${p#*:}
	[ -e "$f" ] || { echo "release-pack.sh: $f is missing -- run \`$t'" >&2; exit 1; }
done

mkdir -p "$DEST"
W=$(stage_at "$DEST/pack")
trap 'rm -rf "$W"' EXIT INT TERM

name=c900-toolchain-v$V-$HOSTTAG
zname=c900-toolchain-v$V-z8001
A="$W/$name"; Z="$W/$zname"

# The stamp every archive carries: the compiler's own (host/build-cc.sh wrote
# it) plus what only a release knows -- the version, the pinned emulator, and
# the OS source above.  Composed rather than appended to the build's copy, so
# packing twice cannot leave a build artifact with two answers in it.
S="$W/provenance"
{
	cat "$BUILD/z8001/.provenance"
	echo "version=$V"
	echo "emu=$(awk '$1=="emu"{print $4}' "$ROOT/DEPS")"
	echo "coherent_commit=$COHCOMMIT"
	echo "coherent_dirtysrc=$COHDIRTY"
	echo "coherent_tree=$COHTREE"
} > "$S"

# ---- the host archive: deliverables 1 (or 2) and 3 ----
mkdir -p "$A/bin" "$A/include" "$A/usr" "$A/native"
for f in cc0-z8001 cc1-z8001 cc2-z8001 cc3-z8001 tabgen; do
	cp "$BUILD/z8001/$f"* "$A/bin/" 2>/dev/null || cp "$BUILD/z8001/$f" "$A/bin/"
done
cp "$BUILD/as-z8001"* "$A/bin/"
cp "$BUILD/ld-z8001"* "$A/bin/"
cp "$BUILD/mkarz" "$A/bin/"		# what arz execs; needs no ld sources beside it
cp "$HERE/ccz" "$HERE/cppz" "$A/bin/"	# resolve the unpacked layout by themselves
cp "$HERE/buildlog.sh" "$A/bin/"	# ccz sources it from beside itself; inert unset
cp "$HERE"/include/*.h "$A/include/"
cp -r "$HERE/include/sys" "$A/include/"
cp -r "$COHERENT_OS/include" "$A/usr/include"
cp "$BUILD/native/cc" "$BUILD/native/as" "$BUILD/native/ld" "$A/native/"
cp "$BUILD/libc-z8001/crt0.o" "$BUILD/libc-z8001/libc-z8001.a" "$A/native/"
# libm and libmisc ride with libc for the same reason libc does: they are Z8001
# libraries this repository builds from an OS tree, the archive is already
# identified by the COHERENT commit that produced libc, and a consumer that has
# to build them itself has to have the OS tree and the harnesses -- which is to
# say, has to be a source checkout after all.
cp "$BUILD/libm-z8001/libm-z8001.a" "$BUILD/libmisc-z8001/libmisc-z8001.a" "$A/native/"
echo "$V" > "$A/VERSION"			# written, not copied: the tag said it
cp "$ROOT/LICENSE" "$ROOT/README.md" "$A/"
cp "$S" "$A/.provenance"

# ---- host/: the checkout-shaped view of the same files ----
# A consumer names one thing, $C900_TOOLCHAIN, and every consuming makefile and
# script then spells the parts as host/ccz and host/build/z8001/cc0-z8001.  A
# release that laid its binaries out differently would make that ONE path
# contract into two, in every consumer, forever; so the archive carries the
# contract instead.  Symlinks, so each binary is still shipped once, and the
# link targets are relative so the tree can be unpacked anywhere.
#
# The drivers are shims rather than links because they locate the passes from
# $0 and must go on finding the ones in bin/ -- that is what makes an unpacked
# release self-contained, headers included, with no OS tree anywhere.
#
# What is NOT here is what a binary archive cannot honestly carry: the
# build-*.sh harnesses, and so the ability to REBUILD any of this.  A consumer
# that needs to compile the toolchain, or to rebuild a Z8001 library against
# its own edits to an OS tree, needs a source checkout -- and its resolver says
# which of the two shapes it got.
#
# The link NAMES carry no executable suffix and the link TARGETS do: a consumer
# spells host/build/z8001/cc0-z8001 on either host, and on Windows that name has
# to resolve to the cc0-z8001.exe that is actually in bin/.
mkdir -p "$A/host/build/z8001" "$A/host/build/libc-z8001"
for f in cc0-z8001 cc1-z8001 cc2-z8001 cc3-z8001 tabgen; do
	ln -s "../../../bin/$f$X" "$A/host/build/z8001/$f"
done
ln -s ../../../.provenance "$A/host/build/z8001/.provenance"
ln -s "../../bin/as-z8001$X" "$A/host/build/as-z8001"
ln -s "../../bin/ld-z8001$X" "$A/host/build/ld-z8001"
ln -s ../../../native/crt0.o "$A/host/build/libc-z8001/crt0.o"
ln -s ../../../native/libc-z8001.a "$A/host/build/libc-z8001/libc-z8001.a"
mkdir -p "$A/host/build/libm-z8001" "$A/host/build/libmisc-z8001"
ln -s ../../../native/libm-z8001.a "$A/host/build/libm-z8001/libm-z8001.a"
ln -s ../../../native/libmisc-z8001.a "$A/host/build/libmisc-z8001/libmisc-z8001.a"
ln -s ../../bin/mkarz "$A/host/build/mkarz"
cp "$HERE/arz" "$A/host/arz"		# execs build/mkarz; nothing else of ld's
cp "$HERE/buildlog.sh" "$A/host/"	# a consumer sources it as $TC/buildlog.sh
for d in ccz cppz; do
	cat >"$A/host/$d" <<EOF
#!/bin/sh
# $d -- the checkout-shaped name for the driver in bin/, which finds the
# compiler passes and the headers beside itself.
exec "\$(dirname "\$0")/../bin/$d" "\$@"
EOF
	chmod +x "$A/host/$d"
done

# ---- deliverable 3 alone ----
mkdir -p "$Z/native" "$Z/usr"
cp "$A"/native/* "$Z/native/"
cp -r "$COHERENT_OS/include" "$Z/usr/include"
echo "$V" > "$Z/VERSION"
cp "$ROOT/LICENSE" "$Z/"
cp "$S" "$Z/.provenance"

# ---- one mode rule, so the two hosts agree by construction ----
#
# In the archive a file is executable iff THIS HOST can run it, and that is
# decided from the file rather than inherited from the build tree.
#
# Inheriting it does not survive the crossing.  as-z8001 and ld-z8001 chmod
# their output +x -- so crt0.o and native/cc,as,ld arrive 0755 -- and those are
# l.out files for the machine, which no host can execute.  MSYS does not store
# mode bits at all: it derives them from the content, calls a PE image or a #!
# script executable and everything else not, and the tarball's 0755 on an l.out
# object is simply gone by the time zip stats it.  The layouts then differ on
# five entries, in the one direction that cannot be fixed by chmod.
#
# So the rule is MSYS's own, applied on both sides: PE, ELF or #! is 0755, the
# rest 0644.  A consumer loses nothing -- it copies native/ to the machine,
# where the modes are the installer's business.  -type f skips the symlinks in
# host/, which must not be chmod'd through to their targets.
canon_modes() {			# canon_modes <dir>
	find "$1" -type d -exec chmod 755 {} +
	find "$1" -type f -print | while read -r f; do
		case $(dd if="$f" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n') in
		7f454c46*|4d5a*|2321*)	chmod 755 "$f" ;;
		*)			chmod 644 "$f" ;;
		esac
	done
}
canon_modes "$A"
canon_modes "$Z"

( cd "$W" && case $ARCH in
	tar) tar czf "$name.tar.gz" "$name" ;;
	# -y: store host/'s symlinks as links rather than following them, so the
	# zip carries each binary once, like the tarball.
	zip) zip -qry "$name.zip" "$name" ;;
  esac
  tar czf "$zname.tar.gz" "$zname" )

# ---- the codegen evidence ----
SH="$BUILD/selfhost/root/work/h2"
[ -d "$SH" ] || { echo "release-pack.sh: no fixpoint objects at $SH (run make check-selfhost)" >&2; exit 1; }
n=$(ls "$SH"/*.o 2>/dev/null | wc -l)
[ "$n" -gt 0 ] || { echo "release-pack.sh: no objects in $SH" >&2; exit 1; }
( cd "$SH" && tar czf "$W/c900-toolchain-v$V-codegen.tar.gz" *.o )
echo "codegen: $n objects"

for f in "$W"/*.tar.gz "$W"/*.zip; do
	[ -f "$f" ] || continue
	mv "$f" "$DEST/"
	echo "packed: $DEST/$(basename "$f")"
done
# end of release-pack.sh
