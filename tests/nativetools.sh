#!/bin/sh
# nativetools.sh - RUN the native assembler and linker.
#
# `make native' builds cc, as and ld for the Z8001 and the release archive ships
# all three, but the self-host fixpoint runs cc0/cc1/cc2 only: as and ld were
# compiled, published and never once executed.  A defect in either reached a
# consumer's hands with nothing between it and them.
#
# Three assertions, all under the emulator:
#
#	as	assemble a fixed source; the object must be BYTE-IDENTICAL to
#		the host assembler's from the same input
#	ld	link that object; the image must be byte-identical to the host
#		linker's
#	ld	a structurally corrupt object must make it exit NONZERO
#
# The third is the one with history.  ld reported `bad symbol segment' and
# fourteen relocation errors on stdout and returned 0, so a corrupt link scored
# as a successful one; on Windows, where every object was being mangled by the C
# runtime's text mode, that is what turned a plain failure into a scattered mess
# of wrong answers.  Byte-identity alone cannot see it -- the two linkers would
# agree about failing -- so the status is asserted on its own.
#
#	sh tests/nativetools.sh
#
# Needs `make native' (hence $COHERENT_OS) and the emulator.  Missing either is
# a REFUSAL, not a skip: this is a gate, and a gate that returns 0 having
# checked nothing is worse than no gate at all.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HERE="$ROOT/host"				# publish.sh reads $HERE for $BUILD
. "$HERE/publish.sh"				# $BUILD

NAT="$BUILD/native"
# -f, not -x: these are l.out binaries for the machine and the emulator READS
# them.  ld chmods its output +x, so -x happens to hold on a POSIX host, but
# MSYS derives the bit from content and would call an l.out file unexecutable --
# a refusal having nothing to do with what this gate tests.
for t in as ld; do
	[ -f "$NAT/$t" ] || {
		echo "nativetools.sh: no target $t in $NAT." >&2
		echo "  Run \`make native' first; it needs \$COHERENT_OS for libc." >&2
		exit 2
	}
done
for t in as-z8001 ld-z8001; do
	[ -x "$BUILD/$t" ] || { echo "nativetools.sh: no host $t in $BUILD; run \`make'." >&2; exit 2; }
done
N2="${N2:-$(sh "$HERE/runner.sh")}"
[ -n "$N2" ] && [ -x "$N2" ] || { echo "nativetools.sh: no emulator; see host/deps.sh." >&2; exit 2; }

W="$BUILD/nativetools"
rm -rf "$W"; mkdir -p "$W/work"
cd "$W"

# The guest runs with $W as its root and every argument relative to it, exactly
# as build-selfhost2.sh drives the compiler passes.
run() { # <program> <args...>  -- echoes the GUEST's exit status, or `norun'
	prog="$1"; shift
	rc=0
	N2ROOT="$W" timeout 600 "$N2" -runexec "$NAT/$prog" "$@" >"work/$prog.log" 2>&1 || rc=$?
	# The banner carries the guest's status; the runner's own status does not
	# distinguish "the program exited 3" from "it never reached an exit".  A
	# run with no banner has delivered no verdict and must not be read as one.
	sed -n 's/^\[exit \([0-9]*\)\]$/\1/p' "work/$prog.log" | tail -1 | grep -q . \
		|| { echo norun; return; }
	sed -n 's/^\[exit \([0-9]*\)\]$/\1/p' "work/$prog.log" | tail -1
}

pass=0; fail=0
ok()   { echo "  PASS $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL $1"; fail=$((fail+1)); }

# ---- the input.  Written here rather than kept as a fixture: an assembler
# source is the thing under test, and it belongs where it can be read.
cat > work/t.s <<'EOF'
/ nativetools: a fixed input for the native-vs-host assembler comparison.
	.globl	SS
	.globl	f_

SS = 0

f_:
	ldl	rr0, rr14(6)
	sub	r13, r13
	dec	r1
	inc	r1
	ret

	.prvd
	.word	0x1A0A
	.word	0x0D0A
	.long	0x1A0D0A1A
EOF
# The data words are 0x1A/0x0A/0x0D on purpose.  Those are the three bytes a
# Windows C runtime rewrites or stops reading at when a stream is not opened
# binary, so this object carries in its own contents the thing that broke every
# object last week -- and any host whose as or ld reverts to text mode fails the
# byte-comparison below rather than failing somewhere later and unrecognisably.

# ---- 1. the assembler
"$BUILD/as-z8001" -o work/h.o work/t.s
st=$(run as -o work/t.o work/t.s)
if [ "$st" != 0 ]; then
	bad "as exited $st: $(tail -2 work/as.log | tr '\n' ' ')"
elif cmp -s work/t.o work/h.o; then
	ok "as: object byte-identical to the host's ($(wc -c < work/t.o) B)"
else
	bad "as: object DIFFERS from the host's"
	cmp -l work/t.o work/h.o 2>&1 | head -5 | sed 's/^/       /'
fi

# ---- 2. the linker.  Uses the HOST's object for both links, so a difference
# here is the linker's and not an assembler difference arriving second-hand.
"$BUILD/ld-z8001" -R 0x200 -e f_ -o work/h.out work/h.o
st=$(run ld -R 0x200 -e f_ -o work/t.out work/h.o)
if [ "$st" != 0 ]; then
	bad "ld exited $st: $(tail -2 work/ld.log | tr '\n' ' ')"
elif cmp -s work/t.out work/h.out; then
	ok "ld: image byte-identical to the host's ($(wc -c < work/t.out) B)"
else
	bad "ld: image DIFFERS from the host's"
	cmp -l work/t.out work/h.out 2>&1 | head -5 | sed 's/^/       /'
fi

# ---- 3. corruption must be a nonzero status.
# Truncated inside the symbol table: the header still describes segments the
# file no longer contains, which is exactly the shape a text-mode read produced.
full=$(wc -c < work/h.o)
dd if=work/h.o of=work/bad.o bs=1 count=$((full * 2 / 3)) 2>/dev/null
st=$(run ld -R 0x200 -e f_ -o work/bad.out work/bad.o)
case "$st" in
0)	bad "ld: a truncated object linked and exited 0 -- corruption is being reported as success"
	sed 's/^/       /' work/ld.log | head -4 ;;
norun)	bad "ld: no exit status on the truncated object (fault or timeout, not a refusal)"
	sed 's/^/       /' work/ld.log | head -4 ;;
*)	# Not merely nonzero: it has to have READ the file and objected to it.
	# `no such file' would also be nonzero and would prove nothing.
	if grep -q 'bad.o' work/ld.log; then
		ok "ld: truncated object refused, exit $st"
	else
		bad "ld: exit $st but nothing said about bad.o -- wrong reason"
		sed 's/^/       /' work/ld.log | head -4
	fi ;;
esac

echo "=== nativetools: $pass passed, $fail failed ==="
[ "$fail" = 0 ]
