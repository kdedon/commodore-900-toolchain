#!/bin/sh
# build-native.sh -- cross-build the TARGET (Z8001) `cc' driver, assembler and
# linker, so the compiler can be run on the machine it compiles for.
#
#	sh host/build-native.sh			all three
#	sh host/build-native.sh as ld cc		named ones
#
# The compiler PASSES are built by build-selfhost.sh (cc0/cc1/cc2, the
# byte-identical self-host fixpoint); this script builds the three programs
# around them that nothing else did:
#
#	cc	src/cc/coh/cc.c + src/cc/common/makvar.c  -> build/native/cc
#	as	src/as/*.c + src/as/z8001/*.c             -> build/native/as
#	ld	src/ld/all.c (unity build)                -> build/native/ld
#
# Together with build-selfhost.sh and build-libc-z8001.sh this is everything a
# COHERENT environment tree needs; build-env.sh composes them.
#
# SOURCE IS PRISTINE except where named below.  build-as.sh and build-ld.sh
# apply a long list of shims -- getline/asm renames, exact-width packed on-file
# structs, a stdarg message.c, a byte-swapping canon.c -- and every one of them
# is an LP64/glibc/gcc workaround that does not apply here: on the target, `int'
# is 16 bits, `long' is 32, the on-file structs ARE the native layout, canon.c
# comes from libc (libc/gen/canon.s), and the varargs the donor uses are the
# ones this libc implements.  So the native build takes the source as it is.
#
# The three exceptions, all in the cc DRIVER and all supplied with -D so the
# source of record is not forked:
#
#   X_OK/R_OK	cc.c uses the 4.x spelling of the access(2) modes; COHERENT 3.x
#		include/access.h spells them AEXEC/AREAD.  Defined, not edited,
#		because the 4.x names are the ones the donor driver was written
#		against and a future 4.x header would supply them.
#   VERSMWC	the version string, which no header in this tree defines.
#   V8087 ...	the i386/i8086 floating-point and OMF variant bits (V8087, VNDP,
#		VOMF, V80186, V80287, VEMU87).  The driver names them in its
#		option table unconditionally; h/z8001/varmch.h has no such
#		hardware to describe.  They are mapped onto ONE unused
#		machine-dependent slot (VMBASE+13, inside the VMBASE..VMAXIM
#		range so that setting one cannot write outside the VARIANT
#		array), which makes `cc -VNDP' on the Z8001 a request the
#		back end ignores rather than a link failure.
#
# and one rename in a scratch copy: the driver's static getpass() collides with
# libc's getpass(3).
#
# Prereqs: build-cc.sh, build-as.sh, build-ld.sh, build-libc-z8001.sh (ccz needs
# the host cross passes and the target libc), and $COHERENT_OS for the headers.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/../src"
CCZ="$HERE/ccz"
. "$HERE/coherent-os.sh"		# sets/exports $COHERENT_OS
. "$HERE/publish.sh"			# $BUILD, stagecopy, publish_dir
. "$HERE/srcman.sh"			# srcman_list, srcman_check

# The shipped userland's link convention (os/hostbuild/build-cmd.sh): stripped,
# separated I/D with shared text, large model.  These programs are the same kind
# of thing as any other /bin command and are linked the same way.
LFLAGS="-s -i -L"

[ -x "$CCZ" ] || { echo "build-native.sh: no ccz at $CCZ" >&2; exit 1; }
# Seeded from what is published: a run naming one target keeps the other two.
OUT=$(stagecopy native)
trap 'rm -rf "$OUT"' EXIT INT TERM
W="$OUT/obj"

# Build what was asked for, or everything.
what=${*:-as ld cc}

# Nothing is published until its link succeeds, and the OLD artifact is removed
# FIRST.  A build that fails after overwriting nothing leaves the previous
# binary in place, and a staging step that only checks for the file's existence
# then ships it -- which is exactly how a stale artifact reads as a fresh one.
fail=0

build_as() {
	echo "== as"
	rm -f "$OUT/as"
	rm -rf "$W/as"; mkdir -p "$W/as"
	srcman_check as "$SRC/as" || { fail=$((fail + 1)); return; }
	objs=""
	for f in $(srcman_list as "$SRC/as"); do
		b=$(basename "$f" .c); f="$SRC/as/$f"
		if ! "$CCZ" -c -o "$W/as/$b.o" -I"$SRC/as" -I"$SRC/as/z8001" "$f" \
			>"$W/as/$b.log" 2>&1
		then
			echo "   FAIL $b: $(grep -v Warning "$W/as/$b.log" | tail -3 | tr '\n' ' ')"
			fail=$((fail + 1)); return
		fi
		objs="$objs $W/as/$b.o"
	done
	"$CCZ" $LFLAGS -o "$OUT/as" $objs
}

build_ld() {
	echo "== ld"
	rm -f "$OUT/ld"
	rm -rf "$W/ld"; mkdir -p "$W/ld"
	srcman_check ld "$SRC/ld" || { fail=$((fail + 1)); return; }
	# BREADBOX is the in-memory output buffer (src/ld/run sets 16384): it
	# pokes Coherent stdio internals, which on the target are Coherent's own.
	if ! "$CCZ" -c -o "$W/ld/all.o" -DBREADBOX=16384 -I"$SRC/ld" "$SRC/ld/all.c" \
		>"$W/ld/all.log" 2>&1
	then
		echo "   FAIL all.c: $(grep -v Warning "$W/ld/all.log" | tail -3 | tr '\n' ' ')"
		fail=$((fail + 1)); return
	fi
	"$CCZ" $LFLAGS -o "$OUT/ld" "$W/ld/all.o"
}

build_cc() {
	echo "== cc"
	rm -f "$OUT/cc"
	rm -rf "$W/cc"; mkdir -p "$W/cc"
	sed 's/\bgetpass\b/ccgetpass/g' "$SRC/cc/coh/cc.c" > "$W/cc/cc.c"
	# -DVERSMWC must contain no space: ccz passes -D arguments through an
	# unquoted shell expansion, so a value with a blank in it is split into
	# two arguments and cc0 stops reading options at the fragment.
	D="-DCOHERENT=1 -DX_OK=AEXEC -DR_OK=AREAD -DVERSMWC=\"4.2-z8001\""
	D="$D -DV8087=VMBASE+13 -DVNDP=VMBASE+13 -DVOMF=VMBASE+13"
	D="$D -DV80186=VMBASE+13 -DV80287=VMBASE+13 -DVEMU87=VMBASE+13"
	I="-I$SRC/cc/h -I$SRC/cc/h/z8001 -I$SRC/cc/generated"
	for f in "$W/cc/cc.c" "$SRC/cc/common/makvar.c"; do
		b=$(basename "$f" .c)
		if ! "$CCZ" -c -o "$W/cc/$b.o" $D $I "$f" >"$W/cc/$b.log" 2>&1; then
			echo "   FAIL $b: $(grep -v Warning "$W/cc/$b.log" | tail -3 | tr '\n' ' ')"
			fail=$((fail + 1)); return
		fi
	done
	"$CCZ" $LFLAGS -o "$OUT/cc" "$W/cc/cc.o" "$W/cc/makvar.o"
}

for t in $what; do
	case "$t" in
	as)	build_as;;
	ld)	build_ld;;
	cc)	build_cc;;
	*)	echo "build-native.sh: don't know how to build \`$t'" >&2; exit 2;;
	esac
done

[ "$fail" = 0 ] || { echo "build-native.sh: $fail target(s) failed" >&2; exit 1; }

# Every published artifact must exist AND be a Z8001 program.  ccz reports a
# byte count on success, but the count comes from the file it just wrote and
# says nothing about which machine it is for -- and this script's whole risk is
# a host binary reaching a tree the guest will execute.
for t in $what; do
	[ -f "$OUT/$t" ] || { echo "build-native.sh: $t was not produced" >&2; exit 1; }
done
python3 "$HERE/loutid.py" -m z8001 $(for t in $what; do echo "$OUT/$t"; done)

publish_dir native
trap - EXIT INT TERM			# $OUT is published now
# end of build-native.sh
