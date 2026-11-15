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
B="${C900_TC_BUILD:-$H/host/build}"
AS="$B/as-z8001"
DIS="$B/tools/loutdis"
[ -x "$AS" ] || { echo "asbytes: as-z8001 not built"; exit 2; }
[ -x "$DIS" ] || { echo "asbytes: loutdis not built"; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0

chk() { # <source line> <expected text bytes, hex, space separated> [<loutdis text>]
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
	[ -n "$3" ] || return
	got=$("$DIS" "$T/a.o" -v | sed -n 's/^  0000: *//p' | tr -s ' ' | sed 's/ $//')
	if [ "$got" = "$3" ]; then pass=$((pass+1));
	else echo "  FAIL(dis) [$1]: got [$got] want [$3]"; fail=$((fail+1)); fi
}

chkerr() { # <source line> that must be rejected, leaving no object
	printf '\t.globl\tSS\n\t.globl\tf\nf:\n\t%s\n' "$1" > "$T/a.s"
	rm -f "$T/a.o"
	if "$AS" -o "$T/a.o" "$T/a.s" >/dev/null 2>&1; then
		echo "  FAIL(accepted) [$1]"; fail=$((fail+1))
	elif [ -e "$T/a.o" ]; then
		echo "  FAIL(object left) [$1]"; fail=$((fail+1))
	else pass=$((pass+1)); fi
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

# JP cc,@RRd and CALL @RRd carry the register in bits 7-4 and cc in bits 3-0
# (manual: 0001 1110 RRd cc, 0001 1111 RRd 0000), and read back the same way.
chk 'jp	@rr2'		'1e 28'	'JP T,@RR2'
chk 'jp	le,@rr8'	'1e 82'	'JP LE,@RR8'
chk 'jp	nov,@rr6'	'1e 6c'	'JP NOV,@RR6'
chk 'jp	ugt,@rr14'	'1e eb'	'JP UGT,@RR14'
chk 'call	@rr2'		'1f 20'	'CALL @RR2'
chk 'call	@rr12'		'1f c0'	'CALL @RR12'

# MREQ Rd is 0111 1011 Rd 1101, R0 included (CPU Reference Manual 1982 p.138).  The
# generic register path ORed in 0x8000 and made it FBnD, a JR.
chk 'mreq	r0'		'7b 0d'	'MREQ'
chk 'mreq	r5'		'7b 5d'	'MREQ'

# 9Cxy runs as TESTL RRx whatever the low nibble.
chk '.word	0x9C20'		'9c 20'	'TESTL RR2'
chk '.word	0x9C23'		'9c 23'	'TESTL RR2'

# STATIC SHIFTS: the second word is the count, negated for a right shift; byte forms
# keep it in the low byte over 00 (CPU Reference Manual 1982 pp.182-189).  Left
# shifts take 0..8/16/32 by width, right shifts 1..8/16/32.
chk 'srab	rh1,$2'		'b2 19 00 fe'
chk 'srlb	rh1,$8'		'b2 11 00 f8'
chk 'slab	rl1,$8'		'b2 99 00 08'
chk 'sllb	rh1,$0'		'b2 11 00 00'
chk 'sra	r1,$2'		'b3 19 ff fe'
chk 'sra	r1'		'b3 19 ff ff'
chk 'srl	r1,$16'		'b3 11 ff f0'
chk 'sla	r1,$16'		'b3 19 00 10'
chk 'sral	rr2,$3'		'b3 2d ff fd'
chk 'srll	rr2,$32'	'b3 25 ff e0'
chk 'slll	rr2,$32'	'b3 25 00 20'
chkerr 'srab	rh1,$9'
chkerr 'srab	rh1,$0'
chkerr 'sllb	rh1,$9'
chkerr 'sra	r1,$0'
chkerr 'sll	r1,$17'
chkerr 'sla	r1,$-1'
chkerr 'srll	rr2,$33'
chkerr 'slal	rr2,$33'

# REGISTER 0 AS AN ADDRESS REGISTER.  A 0 in the address-register field is not R0: in IR,
# X and BX index it selects another mode, and in BA (0011 00xx 0000 Rd) it is relative
# addressing, so `ld r9,rr0(16)' would assemble as `ldr r9,.+20'.  Every such form is an
# error; register 0 stays legal as the data register and as a plain operand.
chkerr 'ld	r9,rr0(16)'
chkerr 'ld	r9,r0(16)'
chkerr 'ldl	rr2,rr0(4)'
chkerr 'ldb	rl1,rr0(2)'
chkerr 'ld	rr0(16),r9'
chkerr 'ldl	rr0(4),rr2'
chkerr 'ldb	rr0(2),rl1'
chkerr 'lda	rr2,rr0(16)'
chkerr 'ld	r9,rr0(r4)'
chkerr 'ldl	rr2,rr0(r4)'
chkerr 'ld	rr0(r4),r9'
chkerr 'ldl	rr0(r4),rr2'
chkerr 'ldb	rr0(r4),rl1'
chkerr 'lda	rr2,rr0(r4)'
chkerr 'ld	r9,rr2(r0)'
chkerr 'ld	r9,16(r0)'
chkerr 'lda	rr2,16(r0)'
chkerr 'jp	16(r0)'
chkerr 'ldm	r1,16(r0),$2'
chkerr 'ld	r9,@rr0'
chkerr 'ldl	rr2,(rr0)'
chkerr 'ld	@rr0,$5'
chkerr 'call	@rr0'
chkerr 'push	@rr0,r1'
chkerr 'ldir	@rr0,@rr2,r4'
chkerr 'ldir	@rr2,@rr0,r4'
chkerr 'cpsir	@rr2,@rr0,r4,eq'
chkerr 'trtirb	@rr2,@rr0,r4'
chkerr 'in	r1,@r0'
chk 'ld	r0,rr2(16)'	'31 20 00 10'
chk 'ldl	rr0,rr2(r4)'	'75 20 04 00'
chk 'lda	rr0,rr2(16)'	'34 20 00 10'
chk 'ld	rr2(16),r0'	'33 20 00 10'
chk 'ld	r9,rr2(16)'	'31 29 00 10'
chk 'ldir	@rr2,@rr4,r0'	'bb 41 00 20'

echo "=== asbytes: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
