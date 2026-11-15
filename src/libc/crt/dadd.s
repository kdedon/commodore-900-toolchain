/ Copyright (c) 1977-1995 Robert Swartz.
/ SPDX-License-Identifier: BSD-3-Clause
/ floating point package for segmented z-8001
/ timothy s. murphy  10/84
/ IEEE format
/ double:	63 62		52 51				0
/	      sign  bin exp +1022   fraction (missing hi bit)
/ float:	31 30		23 22				0
/	      sign  bin exp +126    fraction (missing hi bit)
/
	.globl	dradd, dladd, drsub, dlsub

/ add, subtract doubles   return result  a+b  or   a-b   in rq0
/
/ dradd( da, db)
/ dladd( da, &db)
/ drsub( da, db)
/ dlsub( da, &db)
	.globl	SS

dradd:
	sub	r1, r1
	lda	rr4, SS|12(r15)
	jr	un, 0f
drsub:
	ld	r1, $32768
	lda	rr4, SS|12(r15)
	jr	un, 0f
dlsub:
	ld	r1, $32768
	ldl	rr4, SS|12(r15)
	jr	un, 0f
dladd:
	sub	r1, r1
	ldl	rr4, SS|12(r15)
0:
	sub	r15, $16
	ldm	(rr14), r6, $8

	ldl	rr6, SS|20(r15)
	ldl	rr8, SS|24(r15)
	ldl	rr10, (rr4)
	xor	r10, r1
	ldl	rr12, rr4(4)

	ld	r0, r10			/ signs, in bit 7
	ldb	rh1, rh6
	ldb	rl1, rh0
	res	r6, $15
	res	r10, $15

	cpl	rr6, rr10
	jr	ugt, 0f
	jr	ult, 1f
	cpl	rr8, rr12
	jr	uge, 0f
1:
	exb	rh1, rl1
	ex	r6, r10
	ex	r7, r11
	ex	r8, r12
	ex	r9, r13
0:
	andb	rh1, $128
	ld	r2, $0x7ff0		/ extract exponents
	ld	r3, r2
	and	r2, r6
	ld	r0, r2			/ will be (result exp - 1)*16
	dec	r0, $16
	cp	r0, $2046*16
	jr	uge, 2f			/ the larger is 0 or inf
	xor	r6, r2
	set	r6, $4			/ implicit bits
	and	r3, r10
	jr	z, 8f
	xor	r10, r3
	set	r10, $4

	sub	r2, r3			/ r3 becomes the guard word below
	jr	z, 6f			/ the smaller; exps agree so no alignment
	cp	r2, $16
	jr	eq, 3f			/ one place
	testb	rh2
	jr	nz, 5f
	rrdb	rh2, rl2		/ n = r2 / 16, then right n places
	neg	r2
	ld	r4, r13			/ the guard: what leaves r13
	sub	r5, r5
	sdll	rr4, r2
	ld	r3, r5
	ld	r4, r11			/ what leaves r11 for r12
	sub	r5, r5
	sdll	rr4, r2
	sdll	rr12, r2
	or	r12, r5
	sdll	rr10, r2
	jr	un, 0f
2:
	test	r2
	jr	z, retz
	jr	un, retinf
6:
	ldk	r3, $0
	jr	un, 0f
5:
	ldk	r3, $0
	srl	r2, $4
	cp	r2, $55
	jr	ge, 8f			/ under a quarter ulp - ret larger operand
	clr	r5			/ what is shifted out of the guard
1:
	or	r5, r3			/ a word at a time while it can
	ld	r3, r13
	ld	r13, r12
	ld	r12, r11
	ld	r11, r10
	clr	r10
	sub	r2, $16
	cp	r2, $16
	jr	ge, 1b
	test	r2
	jr	z, 4f
	ld	r4, $16
	sub	r4, r2
	ld	r2, r13			/ the guard, and in r3 what leaves it
	sdll	rr2, r4
	or	r5, r3
	ld	r3, r2
	ld	r2, r11
	sdl	r2, r4
	sub	r4, $16
	sdll	rr12, r4
	or	r12, r2
	sdll	rr10, r4
4:
	test	r5
	jr	z, 0f
	set	r3, $0			/ sticks in the guard's lowest bit
	jr	un, 0f
3:
	ldk	r3, $0
	srll	rr10
	rrc	r12
	rrc	r13
	rrc	r3
0:
	xorb	rl1, rh1
	jr	pl, 0f			/ signs agree - do add

	neg	r3			/ else sub, guard first
	sbc	r9, r13
	sbc	r8, r12
	sbc	r7, r11
	sbc	r6, r10			/ any underflow is possible
	bit	r6, $4
	jr	nz, 8f
	test	r6
	jr	nz, 1f
	test	r7
	jr	nz, 1f
	testl	rr8
	jr	nz, 1f
	test	r3			/ only the guard: 2^-53 of the larger
	jr	nz, 1f
retz:
	subl	rr0, rr0
	subl	rr2, rr2
	jr	un, 9f
1:
	dec	r0, $16
	jr	mi, retz
	add	r3, r3
	rlc	r9
	rlc	r8
	rlc	r7
	rlc	r6
	bit	r6, $4
	jr	nz, 8f
2:					/ more only after a guard of one bit
	dec	r0, $16
	jr	mi, retz
	slll	rr8
	rlc	r7
	rlc	r6
	bit	r6, $4
	jr	z, 2b
	jr	un, 8f
0:
	addl	rr8, rr12
	adc	r7, r11
	adc	r6, r10
	bit	r6, $5
	jr	z, 8f
	inc	r0, $16
	cp	r0, $2046*16
	jr	lt, 0f
retinf:
	ld	r0, $2047*16
	orb	rh0, rh1
	sub	r1, r1
	subl	rr2, rr2
	jr	un, 9f
0:
	srll	rr6
	rrc	r8
	rrc	r9
	rrc	r3
	jr	nc, 8f
	set	r3, $0
8:					/ round to nearest, ties to even
	add	r3, r3
	jr	nc, 7f			/ below half
	jr	nz, 6f			/ above half
	bit	r9, $0
	jr	z, 7f			/ a tie, already even
6:
	inc	r9, $1
	jr	nz, 7f
	inc	r8, $1
	jr	nz, 7f
	inc	r7, $1
	jr	nz, 7f
	inc	r6, $1
7:
	add	r0, r6			/ a carry out of the fraction is the
	orb	rh0, rh1		/ exponent's, as IEEE packs them
	ld	r1, r7
	ldl	rr2, rr8
9:
	ldm	r6, (rr14), $8
	inc	r15, $16
	ret
