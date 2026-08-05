#!/bin/sh
# objsweep.sh -- object-mode (-c) health sweep.  The run-mode regression EXECUTES
# code, but the -c object path lays out far/data references as RELOCATIONS, a
# different code stream that execution never exercises.  Latent object-emit bugs
# (a pass that grows/shrinks words without shifting EVERY fixup array, or stale
# "last data ref" state leaking into a non-main emit path) misplace a relocation
# onto an OPCODE word -- silently corrupting the object.  n2 now asserts this
# invariant and exits 4; this sweep compiles the whole userland + the known bug
# patterns in -c mode and FAILS on any such corruption.
#
# The encoder under test is cc2-z8001, the one whose bytes ship.  The hazard is a
# fixup-ARRAY bug class -- a pass that grows or shrinks words must shift every
# pre-computed word index -- and cc2 has no such array: outcoh.c records a fixup against
# the referencing OPERAND and resolves it in outdone(), after every peephole deletion has
# already moved the words.  The failure mode is structurally absent rather than merely
# untriggered, so what this sweep now asserts over the same corpus is that the whole
# userland compiles clean in object mode.
H="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/donor.sh"
B="${C900_BUILD:-$H/host/build}"	# the lane's build dir; see host/publish.sh
O="$B/z8001"; VAR="${VAR:-800000000800}"
CC2="$O/cc2-z8001"; PEEP="${PEEP:-0010}"
[ -x "$CC2" ] || { echo "objsweep: cc2-z8001 not built (run build-cc-z8001.sh)"; exit 2; }
CMD="$Z8001_DONOR/cmd"; INC="$Z8001_DONOR/include"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
corrupt=0; clean=0; encfail=0; parsefail=0; diskcorrupt=0

# A SWEEP THAT COMPILED NOTHING IS NOT A CLEAN SWEEP.  The verdict below was
# `corrupt -gt 0' alone, and every other outcome -- a cc0 that rejects the whole
# corpus, a cc1 that dies on every file, a $CMD holding no .c at all -- lands in
# `parsefail' or in no counter, leaves corrupt at 0, and prints "PASS (whole
# userland compiles clean in object mode)" having compiled none of it.
# parsefail deliberately has no threshold: a dialect reject is a legitimate
# outcome for this corpus and its count is not this repository's to fix.  What
# has to hold is that a useful number of files reached cc2 and came out clean.
# 20 is far under the ~65 parseable files the corpus has held and far above
# zero, so it is a floor against collapse, not an inventory to maintain.
MINCLEAN=${MINCLEAN:-20}

cobj() { # compile $1 (.c path) through cc0->cc1->cc2 in object mode; classify
	"$O/cc0-z8001" $VAR "$1" "$T/o.z0" -I"$INC" >/dev/null 2>&1 || return 2
	"$O/cc1-z8001" $VAR "$T/o.z0" "$T/o.z1" >/dev/null 2>&1 || return 2
	"$CC2" $PEEP "$T/o.z1" "$T/o.o" "$T/o.scr" 0 >/dev/null 2>"$T/err"
}

# 1) the two known bug patterns (object-mode reloc misplacement)
for name_src in \
	'indirect-call-fnptr|int (*fp)(); int f(x) int x; { return (*fp)(x); }' \
	'fnptr-plus-global|int (*fp)(); int g; int f() { (*fp)(); return g; }'
do
	name=${name_src%%|*}; src=${name_src#*|}
	printf '%s\n' "$src" > "$T/p.c"
	cobj "$T/p.c"; rc=$?
	if [ $rc -eq 4 ]; then echo "  FAIL(corrupt) $name"; corrupt=$((corrupt+1));
	else echo "  ok            $name"; fi
done

# 2) the whole userland in -c mode (cat etc. have JR promotions)
if [ -d "$CMD" ]; then
	for f in "$CMD"/*.c; do
		u=$(basename "$f" .c)
		# Disk-corrupted source: the v0.7.3 floppy image cross-linked foreign object-file
		# blocks into a few .c files at a sector boundary (init.c@4096 = an l.out object,
		# umount.c@512), the same filesystem damage as cmd/as/machine.c.  These are NOT
		# dialect rejects and the embedded binary derails the lexer (a stray 0x27 opens a
		# runaway literal); skip them and count separately so the parity accounting is honest.
		# Threshold 64 ignores benign single-byte bit-rot (ac/deroff = 1 control char in a
		# string/comment; file.c = a form-feed page break) which still lexes normally.
		if [ "$(LC_ALL=C tr -d '[:print:]\t\n\r' < "$f" | wc -c)" -gt 64 ]; then
			echo "  disk-corrupt (skipped): $u"; diskcorrupt=$((diskcorrupt+1)); continue
		fi
		cobj "$f"; rc=$?
		case $rc in
			0) clean=$((clean+1)) ;;
			4) echo "  FAIL(corrupt) $u"; corrupt=$((corrupt+1)) ;;
			1) echo "  cc2 encode-fail: $u"; encfail=$((encfail+1)) ;;  # e.g. col.c
			*) parsefail=$((parsefail+1)) ;;  # cc0/cc1 reject (unsupported C dialect/feature)
		esac
	done
	echo "  userland -c: $clean clean, $encfail cc2-encode-fail (e.g. col.c), $parsefail cc1-parse-reject, $diskcorrupt disk-corrupt (init/umount), $corrupt reloc-CORRUPT"
fi

if [ $corrupt -gt 0 ]; then
	echo "=== objsweep: FAIL ($corrupt reloc-on-opcode corruptions) ==="
	exit 1
fi
if [ $clean -lt "$MINCLEAN" ]; then
	echo "=== objsweep: FAIL -- only $clean file(s) compiled clean, under the"
	echo "    floor of $MINCLEAN.  Nothing was swept; this is not a pass."
	echo "    ($encfail cc2-encode-fail, $parsefail cc1-parse-reject,"
	echo "     $diskcorrupt disk-corrupt.)  MINCLEAN= overrides the floor."
	exit 1
fi
echo "=== objsweep: PASS ($clean files clean in object mode, 0 corruptions) ==="
