#!/bin/sh
# deps.sh -- resolve the two things this repository consumes from elsewhere,
# and refuse by name when one is missing.
#
#   sh host/deps.sh <dep>              print the resolved path, or nothing
#   sh host/deps.sh -n <dep> [value]   print nothing; refuse and exit 2 if
#                                      <value> (or, empty, the search) does
#                                      not resolve
#
# The two modes exist because the search runs early -- when a Makefile is read
# or a script starts, so a variable can be assigned from it -- while the
# REFUSAL belongs where the thing is actually wanted.  -n takes the caller's
# current value, so a wrong C900_EMU= is refused as what the user asked for
# rather than silently re-searched.
#
#   dep        variable      what it names
#   emu        C900_EMU      the emulator BINARY (bin/c900)
#   coherent   COHERENT_OS   a COHERENT OS source tree (include/, libc/, csu/)
#
# NEITHER IS NEEDED TO BUILD THE TOOLCHAIN.  `make' and the table gates run
# from this repository alone.  The emulator is needed by the tests that RUN
# what they compiled, and an OS tree by the few harnesses that build OS
# artifacts WITH the toolchain (libc-z8001.a, libm, the native self-host,
# ccz's system include path) rather than the toolchain itself.
#
# Search order for each: the variable wins; then (emulator only) the pinned
# release under deps/ and a c900 on $PATH; then a sibling checkout, walking
# outward AT MOST THREE PARENTS, then one inside a `repos/' directory beside
# this repository.  Three parents is what reaches the enclosing workspace from
# a repository staged at <workspace>/repos/<repo>; further out is not a
# sibling, it is a coincidence -- an unbounded walk finds another job's
# checkout on a CI runner and reports a false success.
#
# host/runner.sh and host/coherent-os.sh are the callers' entry points and keep
# their names and their contracts; the search lives here so that `make deps',
# which places a clone or an unpacked release, and the build, which looks for
# one, cannot drift apart.

root=$(cd "$(dirname "$0")/.." && pwd)

# The sibling search list for a repository name: three parents, then repos/.
siblings() {
	_d=$root
	_n=0
	while [ $_n -lt 3 ] && [ "$_d" != / ]; do
		_d=$(cd "$_d/.." && pwd)
		echo "$_d/$1"
		_n=$((_n + 1))
	done
	echo "$root/repos/$1"
}

case "$1" in
-n) mode=need; dep=$2; given=$3 ;;
*)  mode=find; dep=$1; given= ;;
esac

case "$dep" in
emu)
	VAR="C900_EMU"
	WANT="the Commodore 900 emulator"
	LIST="$root/deps/commodore-900-emulator"
	p=$(command -v c900 2>/dev/null) && LIST="$LIST $p"
	LIST="$LIST $(siblings commodore-900-emulator)"
	[ -n "$given" ] || given=${C900_EMU:-}
	# A directory names the checkout, a file the binary; both spellings are
	# accepted and the BINARY is what is printed, because that is what
	# runner.sh's callers exec.
	# On Windows the binary is c900.exe.  MSYS2's stat resolves a bare name
	# to it, but the path printed here is exec'd by scripts that also print
	# it, so the real name is what gets printed.
	fixup() {
		if [ -d "$1" ]; then
			if [ -f "$1/bin/c900" ]; then echo "$1/bin/c900"
			else echo "$1/bin/c900.exe"; fi
		else echo "$1"; fi
	}
	# -f as well as -x: EVERY directory is executable, so testing -x alone
	# accepted a checkout path and printed it as if it were the binary.  The
	# tests then "ran" a directory, got no output, and reported 652 wrong
	# answers -- a compiler bug report, from a variable pointed at a
	# directory.
	ok() { [ -f "$1" ] && [ -x "$1" ]; }
	HOW="  The emulator RUNS Z8001 code on the host (\`c900 --exec'), which is how a
  compiler test executes what it just compiled.  It is not built here:
      git clone https://github.com/MichalPleban/commodore-900-emulator
      make -C commodore-900-emulator
  or run \`make deps' to unpack the pinned release named in DEPS, or set
  C900_EMU to the checkout or to its bin/c900, or put c900 on \$PATH.
  Tests that only COMPILE do not need it; tests that RUN the result do."
	;;
coherent)
	VAR="COHERENT_OS"
	WANT="a COHERENT OS source tree"
	# A checkout first, the unpacked snapshot last: the fallback is what
	# there is when the OS repository is not to hand, never a thing that
	# quietly outranks a tree somebody is editing.
	LIST="$(siblings commodore-900-coherent) $root/deps/coherent-os"
	[ -n "$given" ] || given=${COHERENT_OS:-}
	# The variable has always named the OS tree itself (.../os), and a
	# checkout of the OS repository holds it one level down; both are
	# accepted.
	fixup() { if [ -d "$1/os/include" ]; then echo "$1/os"; else echo "$1"; fi; }
	ok() { [ -d "$1/include" ] && [ -d "$1/libc" ] && [ -d "$1/csu" ]; }
	HOW="  These harnesses do not build the TOOLCHAIN, they build OS artifacts WITH
  it -- libc-z8001.a, libm, the native self-host -- so they need the C
  library's own source, which belongs to the operating system.
  That repository is not published yet, so \`make deps DEP=coherent' places a
  SNAPSHOT of the three directories instead -- the release DEPS pins.  Or
  point COHERENT_OS at the os/ directory of a checkout you have, or put one
  beside this repository; either supersedes the snapshot.
  Everything the toolchain itself needs -- build-cc.sh, build-as.sh,
  build-ld.sh, tests/regress.sh -- is in this repository and does not want
  this variable.  A RELEASED toolchain does not want it either: the archive
  ships usr/include and the Z8001 libraries already built."
	;;
*)
	echo "deps.sh: unknown dependency \`$dep' (emu, coherent)" >&2
	exit 2
	;;
esac

found=
if [ -n "$given" ]; then
	given=$(fixup "$given")
	ok "$given" && found=$given
else
	for c in $LIST; do
		c=$(fixup "$c")
		ok "$c" && { found=$c; break; }
	done
fi

if [ -n "$found" ]; then
	[ "$mode" = find ] && echo "$found"
	exit 0
fi

[ "$mode" = find ] && exit 0

{
	if [ -n "$given" ]; then
		echo "*** $WANT: nothing usable at $VAR=$given."
		echo "*** That is $VAR's own value, so nothing else was tried."
		echo "*** Unset it to search these instead:"
	else
		echo "*** $WANT: none found, and this target needs one."
		echo "*** $VAR is unset; the paths tried were:"
	fi
	for c in $LIST; do echo "***     $c"; done
	echo "$HOW" | sed 's/^/*** /'
} >&2
exit 2
