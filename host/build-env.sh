#!/bin/sh
# build-env.sh -- compose a COMPILER ENVIRONMENT: a host directory tree holding
# everything needed to compile ON the target, laid out in the guest's own paths,
# for a guest to reach through a host-mapped filesystem.
#
#	sh host/build-env.sh [-o DIR] [CCENV]
#	CCENV		ours (default), inherited, mwc1985 -- see the table below
#	-o DIR		where to build it (default build/env/<CCENV>)
#
# WHY A DIRECTORY AND NOT AN IMAGE.  The consumer is a guest that mounts a host
# directory (COHERENT's hostfs; the emulator transport renders the
# directory onto a floppy medium at RUN time, the simulator transport serves it
# live).  Keeping the environment a plain tree means the host updates it with
# `cp' and the next guest run sees the change, with nothing repacked -- and it
# means a container ships a directory rather than a disk.
#
# THE LAYOUT MIRRORS THE GUEST PATHS IT STANDS IN FOR, because the `cc' driver
# looks its parts up by path and not by adjacency (src/cc/coh/cc.c):
#
#	bin/	cc as ld ar		P_BIN passes: searched on ":/bin:/usr/bin"
#	lib/	cc0 cc1 cc2		P_LIB passes: searched on "/lib:/usr/lib"
#		crts0.o			pass[CRT], the C runtime startoff
#		libc.a			makelib() builds "lib" + "c" + ".a"
#	usr/include/			the system headers cc0 reads with -I
#
# Mounted at /mnt, nothing is where cc looks, so the environment is used in one
# of two ways -- both documented in docs/ENVIRONMENTS.md, neither invented here:
#
#	cc -t012sdlr -B/mnt/bin:/mnt/lib -I/mnt/usr/include ...
#		-t names the passes to relocate and -B gives the search list
#		they are taken from (cc.c getpass()).  Nothing is installed.
#	or copy bin/* to /bin, lib/* to /lib, usr/include to /usr/include,
#		after which the stock `cc x.c' works with no options at all.
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
#              its C library and headers from vendor/mwc-1985/root, and the
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
	need "$SH/cc0"		"COHERENT_OS=... sh host/build-selfhost.sh"
	need "$SH/cc1"		"COHERENT_OS=... sh host/build-selfhost.sh"
	need "$SH/cc2"		"COHERENT_OS=... sh host/build-selfhost.sh"
	need "$NAT/cc"		"COHERENT_OS=... sh host/build-native.sh"
	need "$NAT/as"		"COHERENT_OS=... sh host/build-native.sh"
	need "$NAT/ld"		"COHERENT_OS=... sh host/build-native.sh"
	need "$LIBC/crt0.o"	"COHERENT_OS=... sh host/build-libc-z8001.sh"
	need "$LIBC/libc-z8001.a" "COHERENT_OS=... sh host/build-libc-z8001.sh"
	need "$COHERENT_OS/include" "a COHERENT 3.5 source tree at \$COHERENT_OS"
	need "$COHERENT_OS/cmd/ar.c" "a COHERENT 3.5 source tree at \$COHERENT_OS"

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

	# ar is an OS command, not a compiler pass, but a build that makes a
	# library needs it and the guest this environment serves is minimal by
	# design.  Cross-built here from the OS tree's own source, the same way
	# libc-z8001.a is -- see coherent-os.sh on OS artifacts built WITH the
	# toolchain.
	echo "== ar (from \$COHERENT_OS/cmd/ar.c)"
	mkdir -p "$ENV/obj"
	CCZ_VAR=800000020800 "$HERE/ccz" -s -i -L -o "$ENV/obj/ar" \
		"$COHERENT_OS/cmd/ar.c" > "$ENV/obj/ar.log" 2>&1 || {
		echo "build-env.sh: ar failed to build:" >&2
		tail -3 "$ENV/obj/ar.log" >&2; exit 1; }
	inst 755 "$ENV/obj/ar" bin/ar
	rm -rf "$ENV/obj"

	copy_headers "$COHERENT_OS/include"
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
	copy_headers "$R/usr/include"
	echo "the stock COHERENT tree's own compiler, as that tree installs it" \
		> "$ENV/CCENV"
	PROV="stock-root $R"
}

# ---------------------------------------------------------------- mwc1985
env_mwc1985() {
	V="$ROOT/vendor/mwc-1985"
	# The 1985 C library and headers are vendored beside the binaries, so this
	# environment composes with no OS tree at all.  $C900_STOCK_ROOT still
	# wins, for composing the same compiler over a library somebody built.
	R=${C900_STOCK_ROOT:-$V/root}
	if [ ! -d "$R/lib" ]; then
		echo "build-env.sh: the 1985 binaries are a COMPILER only; they need a C" >&2
		echo "  library and headers to compile against, and there are none at $R." >&2
		echo "  Set C900_STOCK_ROOT to a built COHERENT staging root (lib/ +" >&2
		echo "  usr/include/), or restore vendor/mwc-1985/root." >&2
		exit 2
	fi
	# The PASSES are not vendored: cpp/cc0/cc1/cc2/cc3 survive only in the
	# COHERENT distribution tree (src/dist/lib), which is a checkout and not
	# the OS-source snapshot.  Without them this tree holds a driver that
	# cannot compile, so it is refused rather than composed.
	P=${C900_MWC1985_PASSES:-}
	if [ -z "$P" ]; then
		_coh=$(COHERENT_OS="${COHERENT_OS:-}" sh "$HERE/deps.sh" coherent)
		[ -n "$_coh" ] && P=$(dirname "$_coh")/src/dist/lib
	fi
	if [ -z "$P" ] || [ ! -f "$P/cc0" ]; then
		echo "build-env.sh: no 1985 compiler passes at ${P:-<unresolved>}." >&2
		echo "  cpp, cc0, cc1, cc2 and cc3 exist only in the COHERENT" >&2
		echo "  distribution tree: commodore-900-coherent/src/dist/lib.  Point" >&2
		echo "  C900_MWC1985_PASSES at it, or put that checkout beside this one." >&2
		exit 2
	fi
	for f in cc ccx as ld ar nm size; do
		need "$V/$f" "vendor/mwc-1985 is missing -- see its SOURCES.md"
		inst 755 "$V/$f" "bin/$f"
	done
	for f in cpp cc0 cc1 cc2 cc3; do
		need "$P/$f" "a commodore-900-coherent checkout's src/dist/lib"
		inst 755 "$P/$f" "lib/$f"
	done
	for f in crts0.o libc.a; do
		need "$R/lib/$f" "build the stock libraries in \$C900_STOCK_ROOT"
		inst 644 "$R/lib/$f" "lib/$f"
	done
	copy_headers "$R/usr/include"
	echo "Mark Williams 1985 originals over the stock COHERENT library" \
		> "$ENV/CCENV"
	# The 1985 parts are recovered artifacts: what identifies them is the
	# tree they were taken from, at the commit that held them.
	_pr=$(cd "$P/../../.." && pwd)
	PROV="library $(if [ "$R" = "$V/root" ]; then echo "vendor/mwc-1985/root@$(repo_origin "$ROOT" "$V/root")"; else echo "$R"; fi)
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
copy_headers() {
	src=$1
	mkdir -p "$ENV/usr/include"
	( cd "$src" && find . -type f -name '*.h' -print ) | while read -r h; do
		mkdir -p "$ENV/usr/include/$(dirname "$h")"
		cp -f "$src/$h" "$ENV/usr/include/$h"
	done
	find "$ENV/usr/include" -type f -exec chmod 644 {} +
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
			"$COHERENT_OS/libc-4.2/stdlib/malloc" \
			"$COHERENT_OS/usr.lib-3.x/misc" "$COHERENT_OS/cmd/ar.c")" checkout
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
# that mounts, lists, and fails only inside the guest.  loutid.py reads the
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
python3 "$HERE/loutid.py" -m z8001 $checked

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
# end of build-env.sh
