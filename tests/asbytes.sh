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
chk 'mreq	r0'		'7b 0d'	'MREQ R0'
chk 'mreq	r5'		'7b 5d'	'MREQ R5'

# 9Cxy runs as TESTL RRx whatever the low nibble.
chk '.word	0x9C20'		'9c 20'	'TESTL RR2'
chk '.word	0x9C23'		'9c 23'	'TESTL RR2'

# STATIC SHIFTS: the second word is the count, negated for a right shift; byte forms
# keep it in the low byte over 00 (CPU Reference Manual 1982 pp.182-189).  Left
# shifts take 0..8/16/32 by width, right shifts 1..8/16/32.
# loutdis prints a negative count as the right shift, as the assembler spells it; for a
# byte form the sign is bit 7 of the low byte, not bit 15.
chk 'srab	rh1,$2'		'b2 19 00 fe'	'SRAB RH1,#2'
chk 'srlb	rh1,$8'		'b2 11 00 f8'	'SRLB RH1,#8'
chk 'slab	rl1,$8'		'b2 99 00 08'	'SLAB RL1,#8'
chk 'sllb	rh1,$0'		'b2 11 00 00'	'SLLB RH1,#0'
chk 'srlb	rl0,$1'		'b2 81 00 ff'	'SRLB RL0,#1'
chk 'sllb	rl0,$1'		'b2 81 00 01'	'SLLB RL0,#1'
chk 'srab	rl7,$8'		'b2 f9 00 f8'	'SRAB RL7,#8'
chk 'sra	r1,$2'		'b3 19 ff fe'	'SRA R1,#2'
chk 'sra	r1'		'b3 19 ff ff'
chk 'srl	r1,$16'		'b3 11 ff f0'
chk 'sla	r1,$16'		'b3 19 00 10'
chk 'sral	rr2,$3'		'b3 2d ff fd'
chk 'srll	rr2,$32'	'b3 25 ff e0'	'SRLL RR2,#32'
chk 'slll	rr2,$32'	'b3 25 00 20'
chkerr 'srab	rh1,$9'
chkerr 'srab	rh1,$0'
chkerr 'sllb	rh1,$9'
chkerr 'sra	r1,$0'
chkerr 'sll	r1,$17'
chkerr 'sla	r1,$-1'
chkerr 'srll	rr2,$33'
chkerr 'slal	rr2,$33'

# MULTL/MULT/DIVL/DIV ADDRESS.  As for every DA/X form, bits 7..4 hold the index (0 for
# DA) and bits 3..0 the register (5.6: `MULT RRd,addr(Rs)' = 0101 1001 Rs RRd / address).
chk 'mult	rr0,12(r13)'	'59 d0 80 00 00 0c'	'MULT RR0,0x00:0x000C(R13)'
chk 'multl	rq0,12(r13)'	'58 d0 80 00 00 0c'	'MULTL RQ0,0x00:0x000C(R13)'
chk 'div	rr0,12(r13)'	'5b d0 80 00 00 0c'	'DIV RR0,0x00:0x000C(R13)'
chk 'divl	rq0,12(r13)'	'5a d0 80 00 00 0c'	'DIVL RQ0,0x00:0x000C(R13)'
chk 'mult	rr12,12'		'59 0c 80 00 00 0c'	'MULT RR12,0x00:0x000C'
chk 'multl	rq4,12(r2)'	'58 24 80 00 00 0c'	'MULTL RQ4,0x00:0x000C(R2)'
chk 'div	rr6,12(r1)'	'5b 16 80 00 00 0c'	'DIV RR6,0x00:0x000C(R1)'
chk 'divl	rq8,12'		'5a 08 80 00 00 0c'	'DIVL RQ8,0x00:0x000C'
# the neighbours that were always right, so the correction stays confined to 58..5B
chk 'ld	r0,12(r13)'	'61 d0 80 00 00 0c'	'LD R0,0x00:0x000C(R13)'
chk 'cpl	rr0,12(r13)'	'50 d0 80 00 00 0c'	'CPL RR0,0x00:0x000C(R13)'
chk 'ldl	12(r13),rr0'	'5d d0 80 00 00 0c'	'LDL 0x00:0x000C(R13),RR0'

# LOUTDIS TEXT for forms its table once printed wrongly.  The bytes are the assembler's;
# the text names every field, so it assembles back to them (tests/disround.sh does that
# for every form).  MULTL @R and #imm had no operands; PUSH/POP @R lost the `@'; LDR,
# LDRB, LDRL and LDAR read as LD; LDA's destination is a pair in every mode; TCC has the
# register in bits 7..4 and cc in 3..0 (manual p.192); RLDB's operands are both byte
# registers (p.166); TRIB's destination is in the first word (p.198); a block compare
# names its register and condition; DI/EI name the bits that are 0 (p.88).
chk 'multl	rq4,@rr2'	'18 24'		'MULTL RQ4,@R2'
chk 'multl	rq8,$0x00012345'	'18 08 00 01 23 45'	'MULTL RQ8,#0x00012345'
chk 'push	@rr14,@rr2'	'13 e2'		'PUSH @R14,@R2'
chk 'pop	@rr4,@rr14'	'17 e4'		'POP @R4,@R14'
chk 'pushl	@rr14,@rr6'	'11 e6'		'PUSHL @R14,@R6'
chk 'popl	@rr6,@rr14'	'15 e6'		'POPL @R6,@R14'
chk 'ldr	r3,.+0x10'	'31 03 00 0c'	'LDR R3,0x0010'
chk 'ldrb	rl1,.+0x10'	'30 09 00 0c'	'LDRB RL1,0x0010'
chk 'ldrl	rr4,.-0x10'	'35 04 ff ec'	'LDRL RR4,0xFFF0'
chk 'ldar	rr2,.+0x10'	'34 02 00 0c'	'LDAR RR2,0x0010'
chk 'lda	rr2,12(r5)'	'76 52 80 00 00 0c'	'LDA RR2,0x00:0x000C(R5)'
chk 'lda	rr2,rr4(16)'	'34 42 00 10'	'LDA RR2,0x0010(R4)'
chk 'lda	rr2,rr4(r6)'	'74 42 06 00'	'LDA RR2,R4(R6)'
chk 'tcc	eq,r3'		'af 36'		'TCC EQ,R3'
chk 'tccb	ult,rl2'	'ae a7'		'TCCB ULT,RL2'
chk 'rldb	rh1,rl2'	'be a1'		'RLDB RH1,RL2'
chk 'trib	@rr2,@rr4,r6'	'b8 20 06 40'	'TRIB @RR2,@RR4,R6'
chk 'cpir	r1,@rr2,r3,eq'	'bb 24 03 16'	'CPIR R1,@RR2,R3,EQ'
chk 'cpsirb	@rr4,@rr2,r3,ne'	'ba 26 03 4e'	'CPSIRB @RR4,@RR2,R3,NE'
chk 'di	VI,NVI'		'7c 00'		'DI VI,NVI'
chk 'ei	VI'		'7c 05'		'EI VI'
chk 'extsb	r3'		'b1 30'		'EXTSB R3'
chk 'in	r3,@r4'		'3d 43'		'IN R3,@R4'
chk 'inirb	@rr2,@r4,r6'	'3a 40 06 20'	'INIRB @RR2,@R4,R6'
chk 'otdr	@r4,@rr2,r6'	'3b 2a 06 40'	'OTDR @R4,@RR2,R6'
chk 'ldctlb	rh2,FLAGS'	'8c 21'		'LDCTLB RH2,FLAGS'
chk 'ldctl	r2,PSAPOFF'	'7d 25'		'LDCTL R2,PSAPOFF'
chk 'setflg	C,Z'		'8d c1'		'SETFLG C,Z'
chk 'ldk	r1,$5'		'bd 15'		'LDK R1,#5'
chk 'ldb	rh5,$0x12'	'c5 12'		'LDB RH5,#0x12'
chk 'dbjnz	rl1,.-4'	'f9 03'		'DBJNZ RL1,0x00:0xFFFC'
chk 'rl	r1,$2'		'b3 12'		'RL R1,#2'
chk 'nop'		'8d 07'		'NOP'
# A short segmented offset (one word) prints two digits, a long one four.
chk 'ld	r1,0|0x20'	'61 01 00 20'	'LD R1,0x00:0x20'
chk 'ld	r1,0|0x0300'	'61 01 80 00 03 00'	'LD R1,0x00:0x0300'
# LDR's store form, which the assembler cannot write (manual p.135).
chk '.word	0x3305,0x0010'	'33 05 00 10'	'LDR 0x0014,R5'

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
