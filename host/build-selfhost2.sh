#!/bin/sh
# build-selfhost2.sh - the self-host fixpoint: compile EVERY compiler source with
# (1) the host-run cross passes and (2) the TARGET-RUN passes (build/selfhost/cc0..cc2
# under the guest harness; cc3 there prints the intermediates when a file differs
# and the divergence has to be attributed), with IDENTICAL argv (relative paths from the
# fake root), and byte-compare the objects.  Identical objects for every file =
# the target-run compiler reproduces the cross compiler exactly.
#
#     build-selfhost2.sh [-hostonly] [FILE ...]   default: the full 86-file set
#
# -hostonly runs the HOST side only, writing work/h2/*.o and comparing nothing.
# It is not a weaker fixpoint, it is the other half of a different check: the
# Windows runner builds the same compiler under LLP64 and its objects are
# compared against the Linux runner's (S4), which is the only place a
# pointer-in-a-long defect can surface.  It needs no emulator and no target
# passes, so it costs a couple of seconds.
#
# $N2 selects the guest runner and still wins; without it, host/runner.sh
# resolves one exactly as the rest of the tree does, so the gate runs from a
# fresh checkout with nothing set.  Its -runexec/N2ROOT interface is what the C
# emulator implements.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/publish.sh"			# $BUILD
SH="$BUILD/selfhost"
O="$BUILD/z8001"
VAR="${CCZ_VAR:-800000020800}"
hostonly=0
if [ "${1:-}" = "-hostonly" ]; then hostonly=1; shift; fi
[ "$hostonly" = 1 ] || N2="${N2:-$(sh "$HERE/runner.sh")}"

# The fake root: built by build-selfhost.sh, rebuilt here if this tree predates
# it or the passes were published by hand.
[ -d "$SH/root" ] || sh "$HERE/selfhost-root.sh" "$SH"
mkdir -p "$SH/root/work/h2" "$SH/root/work/t2"
cd "$SH/root"

INC="-Isrc/n1/z8001 -Isrc/n0/z8001 -Isrc/h/z8001 -Isrc/generated -Isrc/n0 -Isrc/n1 -Isrc/h -Isrc/common -Iusr/include -Iusr/include/sys"

COMMON="bget bput dget diag dput getvar iget iput lget lput makvar milnam mionam newlab newseg nput segnam sget sput talloc tcpy unbget"
N0="cc0 cc0key cc0sym cpp dbgt0 ddecl dope double etc expand expr fold gcandt gdecl get init lex locals sharp size stat"
N1="cc1 cc1sym code mtree0 mtree1 mtree3 node out pool reg0 sel0 sel1 snap0 tree0 tree1"
N1MD="altemp amd fixtop gen1 gen2 mtree2 mtree4 outmch reg1 sel2 snap1 table0 table1"
N2P="cc2 cc2sym dbgt2 emit0 getfun optim"
N2MD="afield emit1 getcod optab outcoh peep"

srcs=""
if [ $# -gt 0 ]; then
	srcs="$*"
else
	for f in $COMMON; do srcs="$srcs src/common/$f.c"; done
	for f in $N0;     do srcs="$srcs src/n0/$f.c"; done
	srcs="$srcs src/n0/z8001/bind.c"
	for f in $N1;     do srcs="$srcs src/n1/$f.c"; done
	for f in $N1MD;   do srcs="$srcs src/n1/z8001/$f.c"; done
	srcs="$srcs tables/macros.c tables/patern.c"
	for f in $N2P;    do srcs="$srcs src/n2/$f.c"; done
	for f in $N2MD;   do srcs="$srcs src/n2/z8001/$f.c"; done
fi

# The corpus is stated, so the verdict can say how much of it was reached.  A
# fixpoint over a subset is not a weaker result, it is a different one, and the
# summary counted only what ran: dropping a name from the lists above (or a
# `continue' added to the loop) shrank the gate with nothing to say so.
nsrc=$(echo $srcs | wc -w)
# The default corpus is the WHOLE compiler, and its size is stated rather than
# derived from the lists above: derived, a name deleted from one of them shrinks
# both the corpus and the expectation, and the fixpoint quietly covers less.
# Adding a compiler source means adding it here too -- which is the point.
NSRC=86
if [ $# -eq 0 ] && [ "$nsrc" != "$NSRC" ]; then
	echo "selfhost stage2: the corpus is $nsrc sources, not $NSRC -- update NSRC" >&2
	exit 1
fi
# whichpass <host-base> <target-base> -- name the first pass whose output
# differs, comparing the two pipelines' INTERMEDIATES as cc3 prints them.
#
# The intermediate FILES cannot be compared: iput/iget memcpy an ival_t, so a
# host .z0/.z1 and a target one differ in most of their bytes for an identical
# compile, and a cmp of them answers `cc0' whatever happened -- which is worse
# than no answer, because it is confident and it sent a lane to the front end
# for a back-end bug.  cc3 prints an intermediate as text, and that text
# compares -- once every integer in it is read as the 32 bits it stands for.
# cc3 prints a U32 constant with the host's `long': 0x80000000 comes out
# 2147483648 from the host cc3 and -2147483648 from the target's, one value in
# two renderings.  dumpnorm folds every integer into 0..2^32-1, so the two
# renderings meet and nothing else moves -- no two distinct 32-bit values are
# 2^32 apart, so it cannot hide a difference.
#
# Anything that stops the dumps being taken yields `pass unknown' with the
# reason, never a guess.
dumpnorm() {	# dumpnorm <in> <out>
	awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^-?[0-9]+$/) {
		 v = $i + 0; if (v < 0) v += 4294967296; $i = sprintf("%.0f", v) }
	       print }' "$1" > "$2"
}
whichpass() {
	[ -x "$SH/cc3" ] || { echo "pass unknown: no target cc3 in $SH"; return 0; }
	for wp_s in 0 1; do
		if ! "$O/cc3-z8001" "$VAR" "$1.z$wp_s" "$1.d$wp_s" >/dev/null 2>&1; then
			echo "pass unknown: host cc3 could not read $1.z$wp_s"; return 0
		fi
		if ! N2ROOT="$SH/root" N2QUIET=1 timeout 600 "$N2" -runexec "$SH/cc3" \
		     "$VAR" "$2.z$wp_s" "$2.d$wp_s" >/dev/null 2>&1; then
			echo "pass unknown: target cc3 could not read $2.z$wp_s"; return 0
		fi
		dumpnorm "$1.d$wp_s" "$1.n$wp_s"
		dumpnorm "$2.d$wp_s" "$2.n$wp_s"
		cmp -s "$1.n$wp_s" "$2.n$wp_s" || { echo "cc$wp_s"; return 0; }
	done
	echo cc2
}

nid=0; ndif=0; nfail=0
for src in $srcs; do
	b=$(basename "$src" .c)
	h="work/h2/$b"; t="work/t2/$b"
	# host-run cross passes
	if ! { "$O/cc0-z8001" "$VAR" "$src" "$h.z0" $INC \
	    && "$O/cc1-z8001" "$VAR" "$h.z0" "$h.z1" \
	    && "$O/cc2-z8001" 0010 "$h.z1" "$h.o" "$h.scr" 0; } >"$h.log" 2>&1; then
		echo "HOSTFAIL $src: $(tail -1 "$h.log")"
		nfail=$((nfail+1)); continue
	fi
	if [ "$hostonly" = 1 ]; then
		echo "HOST     $src"
		nid=$((nid+1)); continue
	fi
	# target-run passes, identical argv
	ok=1
	for stage in 0 1 2; do
		case $stage in
		0) args="$VAR $src $t.z0 $INC";;
		1) args="$VAR $t.z0 $t.z1";;
		2) args="0010 $t.z1 $t.o $t.scr 0";;
		esac
		# The verdict is the runner's exit STATUS.  Its `[exit N]' banner
		# reports the GUEST's status, and a run that never reached a guest
		# exit -- a fault, or the instruction budget -- has none: an older
		# runner printed `[exit 0]' for it and returned 4, so reading the
		# banner scored a compile that never finished as one that succeeded
		# and wrote no object.  The banner is still required as well,
		# because a runner killed before printing one (timeout, signal) has
		# delivered no verdict at all.
		rc=0
		N2ROOT="$SH/root" timeout 600 "$N2" -runexec "$SH/cc$stage" $args >"$t.$stage.log" 2>&1 || rc=$?
		if [ "$rc" != 0 ] || ! grep -q "^\[exit 0\]$" "$t.$stage.log"; then
			echo "FAIL     $src (target cc$stage, status $rc): $(grep -v "^\[exit\|^\[no exit" "$t.$stage.log" | tail -1)"
			ok=0; nfail=$((nfail+1)); break
		fi
	done
	[ "$ok" = 1 ] || continue
	# A pass that reported [exit 0] and wrote no object is not a byte
	# difference, and scoring it as one sends the reader to compare two
	# streams of which one does not exist -- `cmp' then fails on BOTH, so
	# the divergence is attributed to cc0 whatever actually happened.
	if [ ! -f "$t.o" ]; then
		echo "FAIL     $src (target cc2 exited 0 and wrote no object)"
		nfail=$((nfail+1)); continue
	fi
	if cmp -s "$h.o" "$t.o"; then
		echo "IDENT    $src"
		nid=$((nid+1))
	else
		echo "DIFFER   $src ($(whichpass "$h" "$t")) ($(cmp "$h.o" "$t.o" 2>&1 | head -1))"
		ndif=$((ndif+1))
	fi
done
nran=$((nid + ndif + nfail))
if [ "$nran" != "$nsrc" ]; then
	echo "=== selfhost stage2: $nran of $nsrc sources reached the comparison ===" >&2
	exit 1
fi
if [ "$hostonly" = 1 ]; then
	echo "=== selfhost stage2 (host only): $nid of $nsrc compiled, $nfail failed ==="
	[ "$nfail" = 0 ]
	exit
fi
echo "=== selfhost stage2: $nid of $nsrc identical, $ndif differ, $nfail failed ==="
[ "$ndif" = 0 ] && [ "$nfail" = 0 ]
