#!/bin/sh
# build-env.sh -- compose a COMPILER ENVIRONMENT: a host directory tree holding
# everything needed to compile ON the target, laid out in the guest's own paths,
# for a guest to reach through a host-mapped filesystem.
#
#	sh host/build-env.sh [-o DIR] [CCENV]
#	CCENV		ours (default), inherited, mwc1985 -- see the table below
#	-o DIR		where to build it (default build/env/<CCENV>)
#
# The consumer is a guest that mounts a host directory via COHERENT's hostfs.
# The emulator renders the directory onto a floppy at RUN time;
# the simulator serves it live.
#
# The layout mirrors the guest paths (cc driver looks them up by path, not
# adjacency; see src/cc/coh/cc.c):
#
#	bin/	cc as ld ar		P_BIN passes
#	lib/	cc0 cc1 cc2 crts0.o libc.a libm.a	P_LIB passes and libraries
#	usr/include/			system headers
#
# mwc1985 adds usr/sys/h and usr/sys/z8001/h for kernel builds; others do not.
#
# When mounted at /mnt, use -B/mnt/bin:/mnt/lib -I/mnt/usr/include, or
# copy the contents to / and use stock paths. See docs/ENVIRONMENTS.md.
#
# THE ENVIRONMENTS.  Each is a (compiler, C library, headers) triple; the tree's
# shape is the same for all of them, which is the point of having a table.
#
# CCENV NAMES A COMPILER, NOT AN INSTALLED SYSTEM.  The OS tree's dist names
# (stock, extended) say what an owner of a real Commodore 900 wants installed;
# these say WHOSE COMPILER stages the environment.  The table below is the proof
# they are different axes: `inherited' and `mwc1985' take their C library and
# headers from the SAME staging root -- one installed system -- and differ only
# in whose compiler binaries sit beside them.  No name here may encode a release
# number; the release lives in the OS tree's VERSION files.
#
#   ours       THIS repository's compiler, built for the target: the cc0/cc1/cc2
#              self-host fixpoint (build-selfhost.sh) plus the driver, assembler
#              and linker (build-native.sh), with the C library and headers of
#              the extended COHERENT tree named by $COHERENT_OS.
#   inherited  the COHERENT tree's OWN compiler -- the Mark Williams lineage as
#              that tree builds and installs it -- taken from a built stock
#              staging root ($C900_STOCK_ROOT, e.g. commodore-900-coherent's
#              build/root): lib/{cc0,cc1,cc2,cpp,crts0.o,libc.a}, bin/{cc,as,ld,ar}
#              and usr/include, exactly as that tree installs them.
#   mwc1985    the ORIGINAL Mark Williams binaries recovered from the machine:
#              the driver, assembler, linker and archiver from vendor/mwc-1985,
#              its C library and headers from $C900_STOCK_ROOT, and the
#              PASSES (cpp cc0 cc1 cc2 cc3) from a commodore-900-coherent
#              checkout's src/dist/lib, which is the only place they exist.  The
#              date is part of a THIRD PARTY's artifact, not a claim about this
#              tree, which is why it keeps its number.  Their `cc' is a two-line
#              shell script that execs /bin/ccx by ABSOLUTE path, so this one
#              must be installed into the guest's own /bin rather than run from
#              a mount point.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/publish.sh"		# $BUILD, stage_at, publish_at
B="$BUILD"

OUTDIR=""
CCENV=""
while [ $# -gt 0 ]; do
	case "$1" in
	-o)	OUTDIR="$2"; shift;;
	-*)	echo "build-env.sh: unknown option $1" >&2; exit 2;;
	*)	CCENV="$1";;
	esac
	shift
done
CCENV=${CCENV:-ours}
PUBENV=${OUTDIR:-$B/env/$CCENV}

# One missing input, one line, naming what produces it.  A staging step that
# reports "3 of 9 files copied" and exits 0 is how an environment that cannot
# compile anything gets shipped.
need() {	# need <path> <how to produce it>
	[ -e "$1" ] && return 0
	echo "build-env.sh: missing $1" >&2
	echo "  produce it with: $2" >&2
	exit 1
}

# install <mode> <src> <dst-relative-to-$ENV>
inst() {
	mkdir -p "$ENV/$(dirname "$3")"
	cp -f "$2" "$ENV/$3"
	chmod "$1" "$ENV/$3"
}

# ---------------------------------------------------------------- ours
env_ours() {
	. "$HERE/coherent-os.sh"	# $COHERENT_OS, or a legible refusal
	SH="$B/selfhost"
	NAT="$B/native"
	LIBC="$B/libc-z8001"
	LIBM="$B/libm-z8001"
	need "$SH/cc0"		"COHERENT_OS=... sh host/build-selfhost.sh"
	need "$SH/cc1"		"COHERENT_OS=... sh host/build-selfhost.sh"
	need "$SH/cc2"		"COHERENT_OS=... sh host/build-selfhost.sh"
	need "$NAT/cc"		"COHERENT_OS=... sh host/build-native.sh"
	need "$NAT/as"		"COHERENT_OS=... sh host/build-native.sh"
	need "$NAT/ld"		"COHERENT_OS=... sh host/build-native.sh"
	need "$LIBC/crt0.o"	"COHERENT_OS=... sh host/build-libc-z8001.sh"
	need "$LIBC/libc-z8001.a" "COHERENT_OS=... sh host/build-libc-z8001.sh"
	need "$LIBM/libm-z8001.a" "COHERENT_OS=... sh host/build-libm-z8001.sh"
	need "$COHERENT_OS/include" "a COHERENT 3.5 source tree at \$COHERENT_OS"
	need "$COHERENT_OS/ar/ar.c" "a COHERENT 3.5 source tree at \$COHERENT_OS"

	inst 755 "$NAT/cc" bin/cc
	inst 755 "$NAT/as" bin/as
	inst 755 "$NAT/ld" bin/ld
	inst 755 "$SH/cc0" lib/cc0
	inst 755 "$SH/cc1" lib/cc1
	inst 755 "$SH/cc2" lib/cc2
	# pass[CRT].p_pln is the literal "crts0.o": the driver asks for that
	# name, so the startoff is installed under it.
	inst 644 "$LIBC/crt0.o" lib/crts0.o
	# makelib() composes "lib" + the -l name + ".a", so the default -lc
	# resolves to libc.a and nothing else.
	inst 644 "$LIBC/libc-z8001.a" lib/libc.a
	# -lm resolves the same way, to libm.a: the maths library is not linked
	# by default, so a guest program that calls sqrt() names it.
	inst 644 "$LIBM/libm-z8001.a" lib/libm.a

	# ar is an OS command, not a compiler pass, but a build that makes a
	# library needs it and the guest this environment serves is minimal by
	# design.  Cross-built here from the OS tree's own source, the same way
	# libc-z8001.a is -- see coherent-os.sh on OS artifacts built WITH the
	# toolchain.
	echo "== ar (from \$COHERENT_OS/ar/ar.c)"
	mkdir -p "$ENV/obj"
	CCZ_VAR=800000020800 "$HERE/ccz" -s -i -L -o "$ENV/obj/ar" \
		"$COHERENT_OS/ar/ar.c" > "$ENV/obj/ar.log" 2>&1 || {
		echo "build-env.sh: ar failed to build:" >&2
		tail -3 "$ENV/obj/ar.log" >&2; exit 1; }
	inst 755 "$ENV/obj/ar" bin/ar
	rm -rf "$ENV/obj"

	copy_headers "$COHERENT_OS/include" usr/include
	echo "this repository's compiler, self-hosted, over the extended tree's libc" \
		> "$ENV/CCENV"
	PROV="coherent $(os_origin)"
}

# ------------------------------------------------------------ inherited
# The stock tree installs a complete compiler into its staging root already
# (lib/cc0 lib/cc1 lib/cc2 lib/cpp lib/crts0.o lib/libc.a, bin/cc bin/as bin/ld
# bin/ar, usr/include), so composing this one is selection, not building.
env_inherited() {
	R=${C900_STOCK_ROOT:-}
	if [ -z "$R" ] || [ ! -d "$R/lib" ]; then
		echo "build-env.sh: the \`inherited' environment is composed from a BUILT" >&2
		echo "  stock COHERENT staging root; set C900_STOCK_ROOT to one (it must" >&2
		echo "  have lib/ and usr/include/), e.g." >&2
		echo "  C900_STOCK_ROOT=.../commodore-900-coherent/build/root" >&2
		exit 2
	fi
	for f in cc as ld ar; do
		need "$R/bin/$f" "build the stock userland in that tree"
		inst 755 "$R/bin/$f" "bin/$f"
	done
	for f in cc0 cc1 cc2 crts0.o libc.a; do
		need "$R/lib/$f" "build the stock libraries in that tree"
		inst 644 "$R/lib/$f" "lib/$f"
	done
	# cpp and cc3 are separate programs in this system; ship them when the
	# tree has them, since its driver may exec them.
	for f in cpp cc3; do
		[ -f "$R/lib/$f" ] && inst 755 "$R/lib/$f" "lib/$f"
	done
	chmod 755 "$ENV/lib/cc0" "$ENV/lib/cc1" "$ENV/lib/cc2"
	copy_headers "$R/usr/include" usr/include
	echo "the stock COHERENT tree's own compiler, as that tree installs it" \
		> "$ENV/CCENV"
	PROV="stock-root $R"
}

# ---------------------------------------------------------------- mwc1985
env_mwc1985() {
	V="$ROOT/vendor/mwc-1985"
	# This repository vendors the 1985 COMPILER and nothing it compiles
	# against: the C library, the C runtime startoff and the kernel header
	# trees are a 1985 SYSTEM, not a compiler, and they live with the
	# repository that builds a 1985 artifact -- commodore-900-bios, at its
	# vendor/mwc-1985.  So the root to compose over is named, never guessed.
	R=${C900_STOCK_ROOT:-}
	if [ -z "$R" ] || [ ! -d "$R/lib" ]; then
		echo "build-env.sh: the 1985 binaries are a COMPILER only; they need a C" >&2
		echo "  library, a C runtime startoff and headers to compile against," >&2
		echo "  and this repository does not carry them." >&2
		echo "  Set C900_STOCK_ROOT to a guest root holding lib/libc.a," >&2
		echo "  lib/crts0.o, usr/include, usr/sys/h and usr/sys/z8001/h --" >&2
		echo "  a built COHERENT staging root, or commodore-900-bios's" >&2
		echo "  vendor/mwc-1985, which is the 1985 originals." >&2
		exit 2
	fi
	# The passes are vendored beside the driver: cpp/cc0/cc1/cc2/cc3 moved
	# into vendor/mwc-1985 on 2026-08-21.  Before that they lived in the
	# operating system's distribution tree, so selecting the 1985 compiler
	# needed a checkout of the OS to find half of itself; a compiler is its
	# passes, and nothing outside this repository is wanted to run it now.
	# C900_MWC1985_PASSES still overrides, for a tree of passes under test.
	P=${C900_MWC1985_PASSES:-$V}
	if [ ! -f "$P/cc0" ]; then
		echo "build-env.sh: no 1985 compiler passes at $P." >&2
		echo "  cpp, cc0, cc1, cc2 and cc3 are vendored at vendor/mwc-1985;" >&2
		echo "  see its SOURCES.md.  Unset C900_MWC1985_PASSES to use them." >&2
		exit 2
	fi
	# nld as well as ld: cc2 emits the 32-bit object format (l_flag LF_32)
	# and nld is the loader for it.  A consumer linking what these passes
	# produced needs that one, and it survives nowhere else either.
	for f in cc ccx as ld nld ar nm size; do
		need "$V/$f" "vendor/mwc-1985 is missing -- see its SOURCES.md"
		inst 755 "$V/$f" "bin/$f"
	done
	for f in cpp cc0 cc1 cc2 cc3; do
		need "$P/$f" "vendor/mwc-1985 is missing a compiler pass -- see its SOURCES.md"
		inst 755 "$P/$f" "lib/$f"
	done
	for f in crts0.o libc.a; do
		need "$R/lib/$f" "build the stock libraries in \$C900_STOCK_ROOT"
		inst 644 "$R/lib/$f" "lib/$f"
	done
	copy_headers "$R/usr/include" usr/include
	# The kernel header trees, at the guest paths they are named by.  A
	# system artifact compiles with -I/usr/sys/z8001/h and includes
	# <../../h/...> across into /usr/sys/h, so the two are staged together
	# or neither is usable.  They are absent from a stock staging root that
	# installed only /usr/include, and that is refused rather than composed:
	# an environment that cannot build a kernel is not this environment.
	for t in usr/sys/h usr/sys/z8001/h; do
		[ -d "$R/$t" ] || {
			echo "build-env.sh: no $R/$t." >&2
			echo "  The 1985 environment builds SYSTEM artifacts -- the kernel," >&2
			echo "  the drivers, the boot ROM -- and those compile with" >&2
			echo "  -I/usr/sys/z8001/h.  Point C900_STOCK_ROOT at a root that" >&2
			echo "  has the kernel headers too." >&2
			exit 2; }
		copy_headers "$R/$t" "$t"
	done
	# The variant word cc0/cc1/cc2 must be run with is a property of THESE
	# binaries, so it travels with them: a consumer that unpacked a dist has
	# no vendor/mwc-1985 to read it out of, and the wrong word silently
	# produces objects that are not the ones the machine shipped.
	need "$V/VARIANT" "vendor/mwc-1985 is missing -- see its SOURCES.md"
	inst 644 "$V/VARIANT" VARIANT
	echo "Mark Williams 1985 originals over the stock COHERENT library" \
		> "$ENV/CCENV"
	# The 1985 parts are recovered artifacts: what identifies them is the
	# tree they were taken from, at the commit that held them.
	_pr=$(cd "$P/../../.." && pwd)
	PROV="library $R
passes $(repo_origin "$_pr" "$P")"
}

# ---------------------------------------------------------------- headers
# Copied, not linked: the consumer renders this tree onto a medium or serves it
# block by block, and a symlink is skipped by the renderer (HOSTFS-NOTES §7).
#
# This ADDS files and removes none, so it stages a faithful mirror only because
# the tree it writes into was emptied first (below).  A header dropped upstream
# -- <sys/bootinfo.h>, which now lives in the loader alone -- disappears here on
# the next build for that reason and no other.  Anything that stages headers
# incrementally instead reintroduces the copy the guest then compiles against.
#
# copy_headers <srcdir> <dest relative to the environment root>.  The
# destination is the GUEST path the tree stands at, because that is what the
# consumer's -I names once $N2ROOT points at this root.
copy_headers() {
	src=$1
	dst=$ENV/$2
	mkdir -p "$dst"
	( cd "$src" && find . -type f -name '*.h' -print ) | while read -r h; do
		mkdir -p "$dst/$(dirname "$h")"
		cp -f "$src/$h" "$dst/$h"
	done
	find "$dst" -type f -exec chmod 644 {} +
}

# ------------------------------------------------------------- provenance
# WHICH COMPILER BUILT THIS BINARY has to be answerable from an environment
# alone: a consumer that fetches one as an archive has none of the trees it was
# composed from.  So each environment carries .provenance naming its inputs by
# commit, and a tree with uncommitted changes says so -- host/pack-fallback.sh
# refuses to publish one that does.

# repo_origin <dir> [path...] -- `<commit> <date>', with `+dirty' when the
# working tree has changes.  An unversioned tree cannot be named and says so.
# The paths narrow the dirty test to what was actually compiled: a build
# directory elsewhere in a tree says nothing about the sources that went in,
# and refusing on one would make every dist uncuttable in a tree anyone works
# in.  No paths means the whole checkout.
repo_origin() {
	_r=$1; shift
	git -C "$_r" rev-parse --git-dir >/dev/null 2>&1 || { echo unversioned; return; }
	_c=$(git -C "$_r" rev-parse HEAD)
	_d=$(git -C "$_r" show -s --format=%cs HEAD)
	[ -z "$(git -C "$_r" status --porcelain -- "$@")" ] || _c="$_c+dirty"
	echo "$_c $_d"
}

# os_origin -- where $COHERENT_OS came from: a checkout by commit, or the
# pinned source snapshot, which records its own.
os_origin() {
	if [ -f "$COHERENT_OS/.provenance" ]; then
		echo "$(awk '$1=="commit"{print $2}' "$COHERENT_OS/.provenance")" \
		     "$(awk '$1=="date"{print $2}' "$COHERENT_OS/.provenance")" snapshot
	else
		_r=$COHERENT_OS
		[ -d "$_r/.git" ] || _r=$(dirname "$COHERENT_OS")
		# The directories this environment is compiled FROM -- the same
		# set host/pack-coherent-os.sh packs (its DIRS).
		echo "$(repo_origin "$_r" "$COHERENT_OS/include" "$COHERENT_OS/libc" \
			"$COHERENT_OS/csu" "$COHERENT_OS/libm" \
			"$COHERENT_OS/malloc" \
			"$COHERENT_OS/libmisc" "$COHERENT_OS/ar/ar.c")" checkout
	fi
}

case "$CCENV" in
ours|inherited|mwc1985) ;;
*)	echo "build-env.sh: unknown environment \`$CCENV' (ours, inherited, mwc1985)" >&2
	exit 2;;
esac

# Built from empty, every time.  An environment assembled on top of a previous
# one hides a part that stopped being produced: the file is still there, the
# tree still looks complete, and the guest runs last week's compiler.
ENV=$(stage_at "$PUBENV")
trap 'rm -rf "$ENV"' EXIT INT TERM
mkdir -p "$ENV/bin" "$ENV/lib" "$ENV/usr/include"

echo "== environment $CCENV -> $PUBENV"
PROV=""
env_$CCENV

{
	echo "# What this compiler environment is composed of.  A consumer has"
	echo "# nothing else to go on: everything here is a binary."
	echo "env $CCENV"
	echo "compiler $(cat "$ENV/CCENV")"
	echo "toolchain $(repo_origin "$ROOT")"
	[ -n "$PROV" ] && echo "$PROV"
} > "$ENV/.provenance"

# ---------------------------------------------------------------- the gate
# EVERY executable and object in the tree must be a Z8001 program.  This is not
# a formality: each environment's parts come from a directory that also holds HOST
# binaries built by the same harnesses, and a wrong path here produces a tree
# that mounts, lists, and fails only inside the guest.  tools/loutid reads the
# l.out header's machine field (include/mtype.h M_Z8001) and exits nonzero on
# anything else -- including an ELF, which is the mistake being guarded.
echo "== verify: every binary is a Z8001 l.out"
files=$(find "$ENV/bin" "$ENV/lib" -type f | sort)
[ -n "$files" ] || { echo "build-env.sh: the tree is EMPTY" >&2; exit 1; }
# mwc1985's cc is a shell script by construction; every other file is checked.
checked=""
for f in $files; do
	case "$f" in
	*/bin/cc)
		if head -c 4 "$f" | grep -q 'set'; then
			echo "$f                        shell script (1985 cc)"
			continue
		fi;;
	esac
	checked="$checked $f"
done
"$BUILD/tools/loutid" -m z8001 $checked

n=$(find "$ENV" -type f | wc -l)
b=$(find "$ENV" -type f -exec cat {} + | wc -c)
echo "== $CCENV: $n files, $b bytes in $PUBENV"

# The manifest is written last and installed with the tree, so a build that
# stops early leaves the previous one beside a tree that is missing or
# half-composed -- a file list that answers "what is in this environment" with
# last build's answer.
( cd "$ENV" && find . -type f | sort ) > "$ENV.list"
publish_at "$PUBENV"
trap - EXIT INT TERM			# $ENV is published now
publish_file_at "$ENV.list" "$PUBENV.manifest"
rm -f "$ENV.list"
echo "== manifest: $PUBENV.manifest"

# ------------------------------------------------------------- the source map
# WHICH SOURCES EACH PROGRAM IN THE ENVIRONMENT IS MADE OF, published at the
# ONE relative path every producer in this project publishes a map at --
# hostbuild/build/.ulsrcmap under the tree a consumer's descriptor paths are
# resolved against (commodore-900-dist os/dist/PACKAGE-FORMAT, THE SOURCE
# MAP; dist.py SRCMAP).  It is what lets that repository cut a `-src' package
# for the compiler it installs on an image: the complete corresponding source
# for every shipped binary, the recipe that compiles it, and the licence text
# governing it.  Paths are relative to this repository's root, one program per
# line, `#' comments.
#
# ONLY `ours' HAS A MAP, and the other environments have it REMOVED rather than
# left behind.  `inherited' and `mwc1985' hold binaries built from trees this
# repository does not contain -- the COHERENT tree's own compiler and Mark
# Williams' 1985 originals -- so a map naming src/cc for them would be a
# licence claim about somebody else's bytes, and a stale map from an earlier
# `ours' build would make it silently.
SRCMAP="$ROOT/hostbuild/build/.ulsrcmap"
if [ "$CCENV" = ours ]; then
	mkdir -p "$(dirname "$SRCMAP")"
	{
		echo "# .ulsrcmap -- which sources each program of the \`ours'"
		echo "# compiler environment is made of.  GENERATED by"
		echo "# host/build-env.sh; paths are relative to this repository's"
		echo "# root.  Read by commodore-900-dist (dist.py, SRCMAP) to"
		echo "# cut the toolchain component's -src package."
		echo "# The driver, the assembler and the linker are separate"
		echo "# programs from separate source trees; the three passes share"
		echo "# one tree and are built by one harness, so they share a row."
		for p in cc0 cc1 cc2; do
			echo "$p	src/cc host/build-cc.sh host/build-selfhost.sh host/ccz host/publish.sh Makefile LICENSE"
		done
		echo "cc	src/cc host/build-native.sh host/ccz host/publish.sh Makefile LICENSE"
		echo "as	src/as host/build-as.sh host/build-native.sh host/ccz host/publish.sh Makefile LICENSE"
		echo "ld	src/ld host/build-ld.sh host/build-native.sh host/ccz host/publish.sh Makefile LICENSE"
	} > "$SRCMAP"
	echo "== source map: $SRCMAP"
else
	rm -f "$SRCMAP"
fi
# end of build-env.sh
