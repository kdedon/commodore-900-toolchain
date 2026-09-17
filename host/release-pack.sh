#!/bin/sh
# release-pack.sh - package the three deliverables into the release assets.
#
#	sh host/release-pack.sh [-hostonly] [VERSION] [DESTDIR]
#
# VERSION = the tag, without the v.  -hostonly packs THIS host's archive and
# nothing else: the other assets are host-independent, so only one host's
# copies can be published and the second host's are waste.  See "the packages
# that are not this host's" below.
#
# VERSION defaults to what `git describe' says this checkout is, DESTDIR to
# $BUILD/dist.  Writes, for
# the host it is run on:
#
#	c900-toolchain-vX.Y.Z-<host>.tar.gz|.zip   deliverable 1 or 2
#	c900-toolchain-vX.Y.Z-z8001.tar.gz         deliverable 3
#	c900-libc-vX.Y.Z-z8001.tar.gz              the Z8001 libraries alone
#	c900-include-vX.Y.Z.tar.gz                 the target headers alone
#	c900-tools-vX.Y.Z-<host>.tar.gz|.zip       the tools, host-run
#	c900-tools-vX.Y.Z-z8001.tar.gz             the tools, target-run
#
# EVERY ARCHIVE'S bin/ HOLDS PROGRAMS THE MACHINE IN ITS NAME CAN RUN, AND NO
# OTHERS.  That is the whole layout rule, and it is worth stating because it was
# broken once: the host archives carried native/cc, native/as, native/ld and the
# three compiler passes -- Z8001 l.out files -- which no host can execute and
# which nothing in a host archive resolves.  They rode in all three archives, so
# a release shipped them three times and published two copies no code path could
# reach; the Windows job existed partly to copy them from the Linux one so the
# two agreed.  Now they ship once, in the archive named for the machine that
# runs them.
#
# A TARGET LIBRARY IS NOT A TARGET PROGRAM.  lib/ -- crt0.o, libc-z8001.a,
# libm-z8001.a, libmisc-z8001.a, kobj/ -- and usr/include are Z8001 bytes that
# ride in the host archives too, and that is not a violation of the rule above:
# they are INPUTS the host cross compiler reads to produce a Z8001 binary, not
# programs anybody runs.  host/ccz resolves lib/ for exactly that, and a host
# archive without them is a cross compiler that can emit an object and link
# nothing.  So they are shipped by both, and the same bytes: the z8001 archive's
# lib/ is copied from the host archive's staged tree, and cmp-archives.sh holds
# the two hosts' copies to byte equality.
#
# Deliverable 3 is the driver, the assembler, the linker AND the three compiler
# passes cc0/cc1/cc2, which are what the driver execs: a package that carried
# the driver alone would compile nothing on the machine it names.  It lays them
# out in the GUEST's own paths -- bin/cc, lib/cc0, lib/crts0.o via the view --
# and carries host/build/env/ours, the shape host/build-env.sh composes from a
# built checkout, so a consumer stages a compiler from an unpacked release by
# the same paths it spells against a source tree.  The view is here and only
# here, because every file it names is here and only here.
#
# The libc and include packages are the same files again, cut from the SAME
# staged tree the host archive was built from, so all three carry one build of
# them by construction rather than by comparison.  They exist so that a
# consumer can take, and name, the parts separately: the archive is the
# deliverable for a library (ld scans members linearly, and the member order is
# the packer's), so the .a files ship as archives and only the objects a
# consumer NAMES on a link line ship loose: crt0.o, on every program's, and
# kobj/'s five, on the kernel's -- the libc routines the kernel used to compile
# for itself out of the OS tree.  Each package's .provenance carries the full
# compiler stamp, tcid
# included, because a libc built by one compiler and unpacked beside another is
# exactly the mixed codegen the consumer toolchain check exists to refuse.
#
# Prereqs: make all libc.  The z8001 archive additionally needs `make selfhost
# native' and `make check-selfhost'; -hostonly does not, and no longer asks for
# them, because a host archive carries nothing either target builds.
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
HOSTONLY=no
case ${1:-} in
-hostonly)	HOSTONLY=yes; shift ;;
-*)		echo "release-pack.sh: unknown option \`$1'" >&2; exit 2 ;;
esac
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

# mkarz is shipped, and nothing in this repository archives anything: arz builds
# it on first use, and its first use is in a CONSUMER's tree.  So the packer
# asks for it rather than waiting to find it missing.
sh "$HERE/arz" -b

# Named prerequisites, so a missing stage is refused by the target that builds
# it rather than as a cp diagnostic thirty lines in.
for p in "$BUILD/z8001/cc0-z8001:make all" \
	 "$BUILD/as-z8001:make all" \
	 "$BUILD/libc-z8001/libc-z8001.a:make libc" \
	 "$BUILD/libc-z8001/kobj/l3tol.o:make libc" \
	 "$BUILD/libm-z8001/libm-z8001.a:sh host/build-libm-z8001.sh" \
	 "$BUILD/libmisc-z8001/libmisc-z8001.a:sh host/build-libmisc-z8001.sh" \
	 "$BUILD/mkarz:make ld -- host/arz -b compiles mkarz against its canon.o" \
	 "$BUILD/tools/loutid:make tools" \
	 "$BUILD/tools/lout2cpm:make tools" \
	 "$BUILD/tools/loutdis:make tools"; do
	f=${p%:*}; t=${p#*:}
	[ -e "$f" ] || { echo "release-pack.sh: $f is missing -- run \`$t'" >&2; exit 1; }
done
# The target-run programs and tools are host-independent, so only the host that
# packs them needs them built.  A host archive carries none of them, which is
# why a -hostonly run is not asked for `make selfhost native' at all.
if [ "$HOSTONLY" = no ]; then
	for p in "$BUILD/native/cc:make native" \
		 "$BUILD/native/as:make native" \
		 "$BUILD/native/ld:make native" \
		 "$BUILD/selfhost/cc0:make selfhost" \
		 "$BUILD/selfhost/cc1:make selfhost" \
		 "$BUILD/selfhost/cc2:make selfhost" \
		 "$BUILD/tools-z8001/loutid:make tools-z8001" \
		 "$BUILD/tools-z8001/lout2cpm:make tools-z8001" \
		 "$BUILD/tools-z8001/loutdis:make tools-z8001"; do
		f=${p%:*}; t=${p#*:}
		[ -e "$f" ] || { echo "release-pack.sh: $f is missing -- run \`$t'" >&2; exit 1; }
	done
fi

mkdir -p "$DEST"
W=$(stage_at "$DEST/pack")
trap 'rm -rf "$W"' EXIT INT TERM

name=c900-toolchain-v$V-$HOSTTAG
zname=c900-toolchain-v$V-z8001
lname=c900-libc-v$V-z8001
iname=c900-include-v$V
tname=c900-tools-v$V-$HOSTTAG
ztname=c900-tools-v$V-z8001
A="$W/$name"; Z="$W/$zname"; L="$W/$lname"; I="$W/$iname"
T="$W/$tname"; ZT="$W/$ztname"

# The stamp every archive carries: the compiler's own (host/build-cc.sh wrote
# it) plus what only a release knows -- the version, the pinned emulator, and
# the OS source above.  Composed rather than appended to the build's copy, so
# packing twice cannot leave a build artifact with two answers in it.
S="$W/provenance"
{
	cat "$BUILD/z8001/.provenance"
	echo "version=$V"
	echo "emu=$(awk '$1=="emu"{print $4}' "$ROOT/DEPS")"
} > "$S"

# Every package carries the same stamp plus its own name, so an unpacked tree
# says which of the release's parts it is and which compiler build produced it.
stamp_at() {	# stamp_at <tree> <package> [k=v ...]
	_t=$1; _p=$2; shift 2
	{ cat "$S"; echo "package=$_p"; for _kv; do echo "$_kv"; done; } > "$_t/.provenance"
}

# THE GUEST LAYOUT IS NOT AN ARCHIVE LAYOUT.  A compiler environment -- bin/cc,
# lib/cc0, lib/crts0.o, lib/libc.a, usr/include -- is what a GUEST looks up by
# path, and host/build-env.sh composes it: from a built checkout, or from this
# archive unpacked (build-env.sh -R).  It is not a shape any release archive is
# cut in.  An env view shipped inside the archives once, and because every file
# it named was a Z8001 binary it pulled those binaries into the host archives to
# have something to point at.  Composing is the composer's job.

# ---- the host archive: deliverable 1 (or 2) ----
# bin/ is host programs, lib/ and usr/include are what they READ.  Nothing here
# is a Z8001 program; see the layout rule at the top.
mkdir -p "$A/bin" "$A/include" "$A/usr" "$A/lib"
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
cp "$BUILD/libc-z8001/crt0.o" "$BUILD/libc-z8001/libc-z8001.a" "$A/lib/"
# lib/kobj: the five libc objects the KERNEL links by name (build-libc-z8001.sh
# says which and proves they are model-neutral).  They ride in every archive that
# carries libc, because a kernel built against an unpacked RELEASE has no
# harnesses to make them with -- that shape "serves a KERNEL and plain
# userland", and this is now part of what a kernel needs.
#
# No .provenance goes in HERE, and the reason is a gate: cmp-archives.sh compares
# lib/ and usr/ byte for byte between the two hosts' archives, and a stamp
# carries the build host and the build time.  The archives that hold a compiler
# already answer "which compiler built these" with the stamp at their root; the
# separately-packaged libc is the shape that needs a stamp beside the objects,
# and gets one below.
mkdir -p "$A/lib/kobj"
cp "$BUILD/libc-z8001/kobj/"*.o "$A/lib/kobj/"
KOBJL=$(cd "$A/lib/kobj" && printf '%s ' *.o); KOBJL=${KOBJL% }
# libm and libmisc ride with libc for the same reason libc does: they are Z8001
# libraries this repository builds from an OS tree, the archive is already
# identified by the commit that produced libc, and a consumer that has
# to build them itself has to have the OS tree and the harnesses -- which is to
# say, has to be a source checkout after all.
cp "$BUILD/libm-z8001/libm-z8001.a" "$BUILD/libmisc-z8001/libmisc-z8001.a" "$A/lib/"
echo "$V" > "$A/VERSION"			# written, not copied: the tag said it
cp "$ROOT/LICENSE" "$ROOT/README.md" "$A/"
# man/: the Lexicon articles for what this repository owns -- the C library, the
# C language, and the compiler passes.  Tracked files copied whole, at the path
# the checkout spells them, so a consumer staging a manual reads man/man.index
# and man/COHERENT.[12] from an unpacked release exactly as from a checkout.
cp -r "$ROOT/man" "$A/man"
# tools/lout2cpm/: SOURCE, not a binary.  commodore-900-cpm's makefile compiles
# lout2cpm.c itself from $(C900_TOOLCHAIN)/tools/lout2cpm/lout2cpm.c -- it wraps
# a linked l.out as a CP/M x.out, so the format it writes belongs to the
# consumer's build, not to ours, and shipping our host binary would pin the
# consumer to our host.  Without this the DEPS contract does not close: `make
# deps && make all' over a release alone dies at build/lout2cpm with "No rule to
# make target .../tools/lout2cpm/lout2cpm.c", because the archive had no tools/
# at all.  Copied at the path a checkout spells, same as man/ above.
mkdir -p "$A/tools"
cp -r "$ROOT/tools/lout2cpm" "$A/tools/lout2cpm"
# src/libc/gen/qsort.c: SOURCE, for the same reason and by the same rule as
# tools/lout2cpm above.  commodore-900-cpm compiles it itself, from
# $(C900_TOOLCHAIN)/src/libc/gen/qsort.c, for its STAT command -- the object
# has to be built by the CONSUMER's compiler and variant word, not ours, so
# only the source can ship.  Without it `make deps && make all' over a release
# dies at build/user/qsort.o with "No rule to make target
# .../src/libc/gen/qsort.c", exactly as it died at build/lout2cpm before the
# line above.  Copied at the path a checkout spells it.
#
# ONE FILE, not src/: this archive deliberately carries no source tree and no
# harnesses (see host/ below), so what ships is what a consumer NAMES, the same
# discipline as lib/kobj.  qsort.c is self-contained K&R with no #include at
# all, so the file alone is the whole of what it needs.
mkdir -p "$A/src/libc/gen"
cp "$ROOT/src/libc/gen/qsort.c" "$A/src/libc/gen/qsort.c"
# Sealed below, after host/: the content id is over every file in the package,
# and host/ adds two shims that are regular files.

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
ln -s "../../bin/as-z8001$X" "$A/host/build/as-z8001"
ln -s "../../bin/ld-z8001$X" "$A/host/build/ld-z8001"
ln -s ../../../lib/crt0.o "$A/host/build/libc-z8001/crt0.o"
ln -s ../../../lib/libc-z8001.a "$A/host/build/libc-z8001/libc-z8001.a"
mkdir -p "$A/host/build/libc-z8001/kobj"
for f in "$A"/lib/kobj/*.o; do
	ln -s "../../../../lib/kobj/$(basename "$f")" \
	      "$A/host/build/libc-z8001/kobj/$(basename "$f")"
done
mkdir -p "$A/host/build/libm-z8001" "$A/host/build/libmisc-z8001"
ln -s ../../../lib/libm-z8001.a "$A/host/build/libm-z8001/libm-z8001.a"
ln -s ../../../lib/libmisc-z8001.a "$A/host/build/libmisc-z8001/libmisc-z8001.a"
ln -s ../../bin/mkarz "$A/host/build/mkarz"
# No compiler-environment view here: it names Z8001 programs, which this archive
# does not carry.  host/build-env.sh composes one, from a checkout or from the
# z8001 archive unpacked (-R); see the head of this file.
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
stamp_at "$A" compiler kobj="$KOBJL"

# AFTER the stamp, because this is the one link in the host/ view whose target
# this script writes rather than finds: .provenance does not exist until
# stamp_at has written it.  A dangling symlink is legal where symlinks are real,
# but MSYS emulates them and has to read the target as it goes, so making this
# link any earlier fails on Windows and nowhere else.
ln -s ../../../.provenance "$A/host/build/z8001/.provenance"

# ---- the tools, host-run ----
#
# Its own package, not a directory in the compiler archive: these are utilities
# a consumer reaches for on their own, and dist installs them or the consumer
# places them.  bin/ is the whole layout -- there is nothing beside them to
# resolve, so no host/ view is owed.
#
# coff2elf and mkfix ride only on Linux: they bridge COFF32 to ELF32 for the
# x86 self-host and name a host format that means nothing elsewhere.
mkdir -p "$T/bin"
tools="loutid lout2cpm loutdis"
[ "$HOSTTAG" = linux-x86_64 ] && tools="$tools coff2elf mkfix"
for f in $tools; do
	cp "$BUILD/tools/$f"* "$T/bin/" 2>/dev/null || cp "$BUILD/tools/$f" "$T/bin/"
done
echo "$V" > "$T/VERSION"
cp "$ROOT/LICENSE" "$T/"
stamp_at "$T" tools

# ---- the packages that are not this host's -------------------------------
#
# Everything from here to the mode rule is HOST-INDEPENDENT: the same bytes
# whichever host cut them.  Only one host's copies can be published, so the
# other's are built and thrown away -- and each one is packing that can fail on
# a host where the result was never going to be released.  -hostonly says "pack
# my archive and nothing else", which is what the second host actually wants.
if [ "$HOSTONLY" = no ]; then
	# ---- deliverable 3 ----
	#
	# THE SAME SHAPE AS A HOST ARCHIVE, and for the same reason any two of
	# them share one: bin/ is the programs this archive's machine runs, lib/
	# is what those programs read, usr/include is the headers they compile
	# against.  Only the machine differs, and the archive's name is where
	# that is said.  A consumer that knows one archive knows all three.
	#
	# So cc0/cc1/cc2 are in bin/ here, beside cc, as and ld: they are
	# PROGRAMS the machine runs -- the driver execs them -- exactly as the
	# host archive's bin/ holds cc0-z8001 beside as-z8001.  A guest driver
	# looks them up in lib/; that is the guest's layout, and build-env.sh
	# composes it.  cc3 is not among them: cc2 emits the object directly in
	# this configuration.
	#
	# lib/ and usr/ are copied from the host archive's staged tree rather
	# than rebuilt, so the two archives carry one build of the libraries by
	# construction.
	mkdir -p "$Z/bin" "$Z/lib/kobj" "$Z/usr"
	cp "$BUILD/native/cc" "$BUILD/native/as" "$BUILD/native/ld" "$Z/bin/"
	cp "$BUILD/selfhost/cc0" "$BUILD/selfhost/cc1" "$BUILD/selfhost/cc2" "$Z/bin/"
	cp "$A"/lib/*.a "$A/lib/crt0.o" "$Z/lib/"
	cp "$A"/lib/kobj/*.o "$Z/lib/kobj/"
	cp -r "$A/usr/include" "$Z/usr/include"
	echo "$V" > "$Z/VERSION"
	cp "$ROOT/LICENSE" "$Z/"
	# The manual rides here too: this is the package an image builder takes
	# when it wants what runs on the machine and no host compiler, and the
	# manual is part of what runs on the machine.
	cp -r "$ROOT/man" "$Z/man"
	stamp_at "$Z" z8001 kobj="$KOBJL"

	# ---- the libraries alone ----
	#
	# lib/, the same name and the same contents as the archives above give it:
	# this package IS their lib/, cut out and stamped.  The host/ view below
	# carries the contract -- host/build/libc-z8001/libc-z8001.a is the path a
	# consuming makefile already spells -- so this package unpacks over an
	# unpacked toolchain archive, file for file, or stands alone under a
	# variable of its own, without either consumer learning a second spelling.
	#
	# lib/kobj/ holds the loose objects the KERNEL links by name -- the five libc
	# routines it used to compile out of the OS tree.  They are archive members as
	# well, and shipping them twice is the point: the kernel must name them (see
	# build-libc-z8001.sh for why not the archive), and no consumer may have to
	# extract a member to link a kernel.
	#
	# It gets its OWN .provenance, and that is not redundancy.  A loose object
	# announces nothing about itself -- an archive at least has one identity and one
	# mtime, while five objects copied out of an unpacked package into a kernel's
	# build tree are five chances to be a different compiler's.  The stamp travels
	# with the directory, so a kernel build can compare its tcid with the compiler's
	# (§A.1's version-skew rule) after the objects have been copied anywhere.
	mkdir -p "$L/lib/kobj" "$L/host/build/libc-z8001" "$L/host/build/libm-z8001" \
		 "$L/host/build/libmisc-z8001"
	cp "$A/lib/crt0.o" "$A/lib/libc-z8001.a" "$A/lib/libm-z8001.a" \
	   "$A/lib/libmisc-z8001.a" "$L/lib/"
	cp "$A"/lib/kobj/*.o "$L/lib/kobj/"
	ln -s ../../../lib/crt0.o "$L/host/build/libc-z8001/crt0.o"
	ln -s ../../../lib/libc-z8001.a "$L/host/build/libc-z8001/libc-z8001.a"
	ln -s ../../../lib/libm-z8001.a "$L/host/build/libm-z8001/libm-z8001.a"
	ln -s ../../../lib/libmisc-z8001.a "$L/host/build/libmisc-z8001/libmisc-z8001.a"
	mkdir -p "$L/host/build/libc-z8001/kobj"
	for f in "$L"/lib/kobj/*.o; do
		ln -s "../../../../lib/kobj/$(basename "$f")" \
		      "$L/host/build/libc-z8001/kobj/$(basename "$f")"
	done
	echo "$V" > "$L/VERSION"
	cp "$ROOT/LICENSE" "$L/"
	#
	stamp_at "$L" libc kobj="$KOBJL"

	# ---- the headers alone ----
	#
	# usr/include, because that is where an unpacked release already carries them
	# and what ccz resolves in the release layout.  include_scope says WHICH
	# headers: `all' is every header the OS tree has, kernel ones included, which
	# is what there is to ship while the kernel publishes nothing of its own.  When
	# it does, this package sheds that half and says `usr'; a consumer can tell the
	# two apart without unpacking either.
	mkdir -p "$I/usr"
	cp -r "$A/usr/include" "$I/usr/include"
	echo "$V" > "$I/VERSION"
	cp "$ROOT/LICENSE" "$I/"
	stamp_at "$I" include include_scope=all

	# ---- the tools, target-run ----
	#
	# The same three tools as the host package, cross-built to run on the
	# machine; coff2elf and mkfix are not among them.  Host-independent like
	# the packages above, so one host cuts it.
	mkdir -p "$ZT/bin"
	cp "$BUILD/tools-z8001/loutid" "$BUILD/tools-z8001/lout2cpm" \
	   "$BUILD/tools-z8001/loutdis" "$ZT/bin/"
	echo "$V" > "$ZT/VERSION"
	cp "$ROOT/LICENSE" "$ZT/"
	stamp_at "$ZT" tools-z8001
fi

# ---- one mode rule, so the two hosts agree by construction ----
#
# In the archive a file is executable iff THIS HOST can run it, and that is
# decided from the file rather than inherited from the build tree.
#
# Inheriting it does not survive the crossing.  as-z8001 and ld-z8001 chmod
# their output +x -- so crt0.o, and the z8001 archive's bin/, arrive 0755 -- and
# those are l.out files for the machine, which no host can execute.  MSYS does not store
# mode bits at all: it derives them from the content, calls a PE image or a #!
# script executable and everything else not, and the tarball's 0755 on an l.out
# object is simply gone by the time zip stats it.  The layouts then differ on
# five entries, in the one direction that cannot be fixed by chmod.
#
# So the rule is MSYS's own, applied on both sides: PE, ELF or #! is 0755, the
# rest 0644.  A consumer loses nothing -- it copies the tree to the machine,
# where the modes are the installer's business.  -type f skips the symlinks in
# host/, which must not be chmod'd through to their targets.
mode_of() {			# mode_of <file> -- the mode the rule gives it
	case $(dd if="$1" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n') in
	7f454c46*|4d5a*|2321*)	echo 755 ;;
	*)			echo 644 ;;
	esac
}
canon_modes() {			# canon_modes <dir>
	find "$1" -type d -exec chmod 755 {} +
	find "$1" -type f -print | while read -r f; do
		chmod "$(mode_of "$f")" "$f"
	done
}
# lib/kobj/ carries its own stamp: five loose objects copied out of the package
# into a kernel's build tree have to be able to say which compiler built them.
[ "$HOSTONLY" = no ] && stamp_at "$L/lib/kobj" libc-kobj kobj="$KOBJL"
canon_modes "$A"; canon_modes "$T"
[ "$HOSTONLY" = no ] && { canon_modes "$Z"; canon_modes "$L"; canon_modes "$I"
			  canon_modes "$ZT"; }

# ---- .contents, and the content id over it ----
# md5sum's own format over every regular file in a tree but the listing and the
# stamp, so `md5sum -c .contents' verifies an unpacked package with the tool a
# consumer already has; .provenance:contentid is the listing's sha1, the id
# commodore-900-dist's format gate recomputes from the bytes.  Last of all, after
# the mode rule, so nothing listed changes once it is listed.  lib/kobj is sealed
# before the package around it, which then lists its .contents and .provenance.
seal() {			# seal <tree>
	( cd "$1" && find . -type f ! -path ./.contents ! -path ./.provenance -print |
	  LC_ALL=C sort | sed 's|^\./||' | xargs md5sum ) > "$1/.contents"
	echo "contentid=$(sha1sum "$1/.contents" | cut -c1-12)" >> "$1/.provenance"
	chmod 644 "$1/.contents" "$1/.provenance"
}
seal "$A"; seal "$T"
[ "$HOSTONLY" = no ] && { seal "$Z"; seal "$L/lib/kobj"; seal "$L"; seal "$I"
			  seal "$ZT"; }

( cd "$W" && case $ARCH in
	tar) tar czf "$name.tar.gz" "$name"; tar czf "$tname.tar.gz" "$tname" ;;
	# -y: store host/'s symlinks as links rather than following them, so the
	# zip carries each binary once, like the tarball.
	zip) zip -qry "$name.zip" "$name"; zip -qry "$tname.zip" "$tname" ;;
  esac
  [ "$HOSTONLY" = no ] || exit 0
  tar czf "$zname.tar.gz" "$zname"
  tar czf "$lname.tar.gz" "$lname"
  tar czf "$iname.tar.gz" "$iname"
  tar czf "$ztname.tar.gz" "$ztname" )

# ---- each package is judged, as cut, before it leaves ----
# The archive just written is unpacked and read back against what it says it
# carries: one top-level directory named for the archive, VERSION, the
# .provenance keys its kind declares, the files and counts a consumer names, no
# link that dangles or leaves the package, each declared link resolving to its
# target, every file at the mode the rule above gives it, and .contents against
# the files present in both directions with contentid its sha1.  These are the
# assertions commodore-900-dist's declarations make of these kinds, made here by
# the packer so that a bad cut is refused where it was cut.  One failure refuses
# the whole cut: nothing is moved into $DEST.
#
# A link the unpacking host cannot represent (MSYS copies rather than links) is
# judged by its bytes against its target instead.
nbad=0
J="$W/judge"
refuse() { echo "release-pack.sh: $1: $2" >&2; nbad=$((nbad + 1)); }
kv() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1; }

judge_contents() {		# judge_contents <archive> <tree> <subdir|.>
	_s=${3#.}; _s=${_s:+$_s/}; _d="$2/$3"
	if [ ! -f "$_d/.contents" ]; then
		refuse "$1" "file.present: ${_s}.contents is missing"; return
	fi
	[ "$(sha1sum "$_d/.contents" | cut -c1-12)" = "$(kv "$_d/.provenance" contentid)" ] ||
		refuse "$1" "content.id: ${_s}.contents is not the file ${_s}.provenance:contentid names"
	(cd "$_d" && md5sum --quiet -c .contents) > "$J/md5" 2>&1 ||
		refuse "$1" "contents.md5: $_s$(grep -v '^md5sum:' "$J/md5" | head -1)"
	# md5sum names a file after the digest and a two-character separator:
	# two spaces when it read the file as text, a space and a `*' when it
	# read it as bytes, which is what a Windows host does by default and
	# what a package of executables wants there.  Both forms are the name
	# of the same file, so strip either one, and read the comparison a
	# line at a time so a name is never split on whitespace or expanded as
	# a glob.
	sed 's/^[0-9a-f]\{32\} [ *]//' "$_d/.contents" | LC_ALL=C sort > "$J/listed"
	(cd "$_d" && find . -type f ! -path ./.contents ! -path ./.provenance |
		sed 's|^\./||' | LC_ALL=C sort) > "$J/present"
	LC_ALL=C comm -13 "$J/listed" "$J/present" > "$J/unlisted"
	while IFS= read -r _f; do
		refuse "$1" "contents.complete: $_s$_f is in the package and ${_s}.contents does not list it"
	done < "$J/unlisted"
	LC_ALL=C comm -23 "$J/listed" "$J/present" > "$J/absent"
	while IFS= read -r _f; do
		refuse "$1" "contents.complete: ${_s}.contents lists $_s$_f and the package does not carry it"
	done < "$J/absent"
}

# judge <archive> <package> <stamp keys> <files> <glob:count ...> [<link> <target>]...
judge() {
	_a=$1; _p=$2; _keys="kind commit version package tcid contentid $3"; _files=$4; _globs=$5
	shift 5
	_n=${_a%.tar.gz}; _n=${_n%.zip}
	_j="$J/$_n"; rm -rf "$_j"; mkdir -p "$_j"
	case "$_a" in
	*.zip)	command -v unzip >/dev/null 2>&1 ||
			{ refuse "$_a" "archive.unpack: this host has no unzip, so the zip cannot be judged"; return; }
		unzip -qq "$W/$_a" -d "$_j" || { refuse "$_a" "archive.unpack: the zip just written does not unpack"; return; } ;;
	*)	tar xpzf "$W/$_a" -C "$_j" || { refuse "$_a" "archive.unpack: the tarball just written does not unpack"; return; } ;;
	esac
	if [ "$(ls -A "$_j")" != "$_n" ] || [ ! -d "$_j/$_n" ]; then
		refuse "$_a" "archive.toplevel: holds \`$(ls -A "$_j" | tr '\n' ' ')', not the one directory $_n"; return
	fi
	_u="$_j/$_n"; _ua=$(cd "$_u" && pwd -P)

	[ "$(sed -n 1p "$_u/VERSION" 2>/dev/null)" = "$V" ] ||
		refuse "$_a" "version.match: VERSION does not say $V"
	for _k in $_keys; do
		[ -n "$(kv "$_u/.provenance" "$_k")" ] || refuse "$_a" "stamp.keys: .provenance carries no $_k"
	done
	grep -qx "package=$_p" "$_u/.provenance" 2>/dev/null ||
		refuse "$_a" "stamp.text: .provenance has no line package=$_p"
	for _f in LICENSE $_files; do
		[ -s "$_u/$_f" ] || refuse "$_a" "file.present: $_f is missing or empty"
	done
	for _g in $_globs; do
		_c=$(cd "$_u" && eval "ls -d ${_g%:*}" 2>/dev/null | wc -l)
		[ "$_c" -ge "${_g##*:}" ] ||
			refuse "$_a" "glob.count: ${_g%:*} matches $_c, at least ${_g##*:} are carried"
	done

	for _l in $(cd "$_u" && find . -type l | LC_ALL=C sort); do
		_t=$(readlink "$_u/$_l")
		case "$_t" in
		/*) refuse "$_a" "path.escape: $_l -> $_t is absolute" ;;
		*)  _r=$(cd "$_u/$(dirname "$_l")" && realpath -m "$_t")
		    case "$_r" in "$_ua"|"$_ua"/*) ;; *) refuse "$_a" "path.escape: $_l -> $_t leaves the package" ;; esac ;;
		esac
		[ -e "$_u/$_l" ] || refuse "$_a" "link.dangling: $_l -> $_t resolves to nothing"
	done
	while [ $# -ge 2 ]; do
		if [ -L "$_u/$1" ]; then
			[ "$(cd "$_u/$(dirname "$1")" && realpath -m "$(readlink "$_u/$1")")" = "$_ua/$2" ] ||
				refuse "$_a" "link.target: $1 does not resolve to $2"
		elif ! cmp -s "$_u/$1" "$_u/$2"; then
			refuse "$_a" "link.target: $1 is neither a link to $2 nor its bytes"
		fi
		shift 2
	done

	(cd "$_u" && find . -type d ! -perm 755 | LC_ALL=C sort) > "$J/dirs"
	for _f in $(cat "$J/dirs"); do refuse "$_a" "mode.rule: directory $_f is not 755"; done
	(cd "$_u" && find . -type f | LC_ALL=C sort) > "$J/files"
	while read -r _f; do
		_m=$(stat -c %a "$_u/$_f"); _w=$(mode_of "$_u/$_f")
		[ "$_m" = "$_w" ] || echo "$_f $_m $_w"
	done < "$J/files" > "$J/modes"
	while read -r _f _m _w; do
		refuse "$_a" "mode.rule: $_f is mode $_m, and its first bytes make it $_w"
	done < "$J/modes"

	judge_contents "$_a" "$_u" .
	if [ "$_p" = libc ]; then
		for _k in kind commit version package tcid kobj contentid; do
			[ -n "$(kv "$_u/lib/kobj/.provenance" "$_k")" ] ||
				refuse "$_a" "stamp.keys: lib/kobj/.provenance carries no $_k"
		done
		grep -qx "package=libc-kobj" "$_u/lib/kobj/.provenance" 2>/dev/null ||
			refuse "$_a" "stamp.text: lib/kobj/.provenance has no line package=libc-kobj"
		[ "$(kv "$_u/lib/kobj/.provenance" tcid)" = "$(kv "$_u/.provenance" tcid)" ] ||
			refuse "$_a" "stamp.pair: lib/kobj/.provenance and .provenance name different compilers"
		judge_contents "$_a" "$_u" lib/kobj
	fi
}

mkdir -p "$J"
case $ARCH in tar) hostarch=$name.tar.gz ;; zip) hostarch=$name.zip ;; esac
TB=host/build
judge "$hostarch" compiler "cc0 cc1 cc2 cc3 kobj" \
	"lib/crt0.o lib/libc-z8001.a lib/libm-z8001.a lib/libmisc-z8001.a host/ccz host/cppz" \
	"lib/kobj/*.o:5 bin/*:10 usr/include/*.h:30" \
	$TB/z8001/cc0-z8001 bin/cc0-z8001$X  $TB/z8001/cc1-z8001 bin/cc1-z8001$X \
	$TB/z8001/cc2-z8001 bin/cc2-z8001$X  $TB/z8001/cc3-z8001 bin/cc3-z8001$X \
	$TB/as-z8001 bin/as-z8001$X  $TB/ld-z8001 bin/ld-z8001$X  $TB/mkarz bin/mkarz \
	$TB/libc-z8001/libc-z8001.a lib/libc-z8001.a  $TB/libc-z8001/crt0.o lib/crt0.o \
	$TB/libm-z8001/libm-z8001.a lib/libm-z8001.a \
	$TB/libmisc-z8001/libmisc-z8001.a lib/libmisc-z8001.a
case $ARCH in tar) toolsarch=$tname.tar.gz ;; zip) toolsarch=$tname.zip ;; esac
judge "$toolsarch" tools "" "" "bin/*:3"
if [ "$HOSTONLY" = no ]; then
	judge "$ztname.tar.gz" tools-z8001 "" "" "bin/*:3"
	judge "$zname.tar.gz" z8001 kobj \
		"bin/cc bin/as bin/ld bin/cc0 bin/cc1 bin/cc2 lib/crt0.o lib/libc-z8001.a lib/libm-z8001.a lib/libmisc-z8001.a" \
		"bin/*:6 lib/kobj/*.o:5 usr/include/*.h:30"
	judge "$lname.tar.gz" libc kobj \
		"lib/libc-z8001.a lib/libm-z8001.a lib/libmisc-z8001.a lib/crt0.o" \
		"lib/kobj/*.o:5" \
		$TB/libc-z8001/libc-z8001.a lib/libc-z8001.a  $TB/libc-z8001/crt0.o lib/crt0.o \
		$TB/libm-z8001/libm-z8001.a lib/libm-z8001.a \
		$TB/libmisc-z8001/libmisc-z8001.a lib/libmisc-z8001.a
	judge "$iname.tar.gz" include include_scope "" \
		"usr/include/*.h:30 usr/include/sys/*.h:20"
fi
if [ "$nbad" -gt 0 ]; then
	echo "release-pack.sh: $nbad assertion(s) failed against what the packages say they carry; nothing was left in $DEST" >&2
	exit 1
fi
echo "judged: every package matches its .contents and .provenance"

for f in "$W"/*.tar.gz "$W"/*.zip; do
	[ -f "$f" ] || continue
	mv "$f" "$DEST/"
	echo "packed: $DEST/$(basename "$f")"
done

# end of release-pack.sh
