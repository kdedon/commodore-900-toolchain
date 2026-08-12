#!/bin/sh
# asbytes.sh -- assembler ENCODING assertions: one source line in, the exact text bytes
# out.  as-z8001 is the only path by which hand-written assembly (crt0, the libc and
# kernel .s files, a boot loader) reaches the machine, and nothing else in the suite reads
# its bytes: the compiler gates all run cc2's own encoder, which never calls this code.
#
# Each expected string is the encoding the Z8000 CPU Technical Manual gives for the form,
# and every one of them is also what the PRISTINE MWC as-mch/z8001/machine.c assembles.
# The l.out header is 48 bytes (n.out.h), so the text starts there.
H="$(cd "$(dirname "$0")/.." && pwd)"
B="${C900_BUILD:-$H/host/build}"
AS="$B/as-z8001"
[ -x "$AS" ] || { echo "asbytes: as-z8001 not built"; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0

chk() { # <source line> <expected text bytes, hex, space separated>
	printf '\t.globl\tSS\n\t.globl\tf\nf:\n\t%s\n' "$1" > "$T/a.s"
	if ! "$AS" -o "$T/a.o" "$T/a.s" 2>"$T/err"; then
		echo "  FAIL(as) [$1]: $(cat "$T/err")"; fail=$((fail+1)); return
	fi
	got=$(od -A n -t x1 -j 48 "$T/a.o" | tr -s ' \n' '  ' | sed 's/^ //; s/ $//')
	want=$(printf '%s' "$2")
	# compare only as many bytes as the expectation names
	got=$(printf '%s' "$got" | cut -d' ' -f1-$(printf '%s' "$want" | wc -w))
	if [ "$got" = "$want" ]; then pass=$((pass+1));
	else echo "  FAIL [$1]"; echo "       got  $got"; echo "       want $want"; fail=$((fail+1)); fi
}

# BASE INDEX (BX), LD/LDL/LDA and the store direction.  The first word carries the BASE
# register in its source nibble and the SECOND word carries the INDEX in bits 11..8
# (CPU Technical Manual 5.6.8: `LD Rd,RRs(Rx)' = 0011 0001 w Rs Rd / 0000 Rx 0000 0000).
# Getting the two the other way round assembles and links, and addresses with the index
# as the base.
chk 'ld	r1,rr2(r4)'	'71 21 04 00'
chk 'ld	r1,rr6(r8)'	'71 61 08 00'
chk 'ldl	rr2,rr4(r6)'	'75 42 06 00'
chk 'ld	rr2(r4),r1'	'73 21 04 00'
chk 'lda	rr2,rr4(r6)'	'74 42 06 00'

# SEGMENTED DIRECT ADDRESS with a RELOCATABLE segment (`SS|offset').  An offset over 255
# needs the LONG form: bit 15 of the first word says so, and the segment byte itself is a
# relocation, so the word the assembler emits must already carry 0x8000.  Without it the
# CPU reads the one-word short form and executes the offset word as an instruction.
chk 'ld	r1,SS|0x0300'	'61 01 80 00 03 00'
chk 'ldl	rr2,SS|0x1234'	'54 02 80 00 12 34'
chk 'ld	r1,SS|0x0020'	'61 01 00 20'

# LDM, whose second word holds the first register and the count less one, over both
# lengths of segmented address (manual 6.99: 0101 1100 0001 / 0000 Rd 0000 n-1 / address).
chk 'ldm	r1,SS|0x0020,$2'	'5c 01 01 01 00 20'
chk 'ldm	r1,SS|0x0300,$2'	'5c 01 01 01 80 00 03 00'

echo "=== asbytes: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
