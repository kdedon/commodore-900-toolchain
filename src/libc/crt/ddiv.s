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
	.globl	SS

	.globl	drdiv, dldiv
/
/ divide a/b  result in rq0
/
/ drdiv( da, db)
/ dldiv( da, &db)
/
/ With fractions a, b in [2^52, 2^53) and a doubled when a < b, two signed
/ 64/32 divides by the top of B = b*2^9 give q1 and q2, and a/b * 2^58 is
/ q1*2^29 + q2 + R2/B with |R2/B| < 2.0000003, R2 the exact remainder.
/ The rounded fraction is floor((q1*2^29 + q2 + 32 + R2/B) / 64), so R2 is
/ needed only when the low six bits of q2 + 32 are within 3 of a multiple
/ of 64.  A quotient of two 53-bit fractions is never a tie.
/ B is split as Bh*2^32 - nBl with nBl a signed long, so Bh is at most 2^30.

drdiv:
	lda	rr2, SS|12(r15)
	jr	un, 0f
dldiv:
	ldl	rr2, SS|12(r15)
0:
	sub	r15, $16
	ldm	(rr14), r6, $8

	ldl	rr4, SS|20(r15)		/ a
	ldl	rr6, SS|24(r15)
	ldl	rr8, (rr2)		/ b
	ldl	rr10, rr2(4)
	ld	r13, r4			/ result sign
	xor	r13, r8
	and	r13, $32768
	ldl	rr0, $0x7ff07ff0	/ exponents
	and	r0, r4
	jr	z, retz
	and	r1, r8
	jr	z, retinf
	cp	r0, $2047*16
	jr	eq, retinf
	cp	r1, $2047*16
	jr	eq, retz
	sub	r0, r1			/ (exp - 1)*16 when a >= b
	add	r0, $1022*16
	ld	r12, r0
	cp	r0, $2047*16
	jr	ult, 0f
	cp	r0, $0xc000		/ above 2047 or below 1
	jr	ult, retinf
	jr	un, retz
0:
	and	r4, $15			/ fractions with the implicit bit
	set	r4, $4
	and	r8, $15
	set	r8, $4

	cpl	rr4, rr8
	jr	ugt, 1f
	jr	ult, 0f
	cpl	rr6, rr10
	jr	uge, 1f
0:
	slll	rr6			/ a < b: double it
	rlc	r5
	rlc	r4
	sub	r12, $16
	jr	mi, retz
1:
	slll	rr4, $6			/ X = a*2^6 in rq4
	ldl	rr2, rr6
	srll	rr2, $26
	or	r5, r3
	slll	rr6, $6

	slll	rr8, $9			/ B = b*2^9
	ldl	rr2, rr10
	srll	rr2, $23
	or	r9, r3
	slll	rr10, $9
	subl	rr2, rr2		/ nBl = -low; Bh is one more when
	subl	rr2, rr10		/ that is positive
	ldl	rr10, rr2
	jr	mi, 0f
	jr	z, 0f
	addl	rr8, $1
0:
	divl	rq4, rr8		/ q1 in rr6, r1 in rr4
	ldl	rr2, rr6
	multl	rq0, rr10
	addl	rr0, rr4		/ R1 = r1*2^32 + q1*nBl, a multiple of 2^9
	ldl	rr4, rr0		/ Y = R1 / 8
	slll	rr4, $29
	srll	rr2, $3
	or	r2, r4
	sral	rr0, $3
	divl	rq0, rr8		/ q2 in rr2, its remainder in rr0
	addl	rr2, $32
	ld	r5, r3
	and	r5, $63
	sub	r5, $3
	cp	r5, $58
	jr	ugt, 5f
4:
	sral	rr2, $6			/ fraction = q1*2^23 + (q2 + 32) / 64
	ldl	rr4, rr6
	srll	rr4, $9
	slll	rr6, $23
	ld	r1, r2
	sra	r1, $15
	addl	rr6, rr2
	adc	r5, r1
	adc	r4, r1

	add	r12, r4			/ a carry out of the fraction is the
	cp	r12, $2047*16		/ exponent's, as IEEE packs them
	jr	uge, retinf
	ld	r0, r12
	or	r0, r13
	ld	r1, r5
	ldl	rr2, rr6
9:
	ldm	r6, (rr14), $8
	inc	r15, $16
	ret
5:
	pushl	(rr14), rr6		/ near a rounding boundary:
	ldl	rr6, rr2		/ R2 = rem*2^32 + q2*nBl
	subl	rr6, $32
	multl	rq4, rr10
	addl	rr4, rr0
	testl	rr10			/ B back in rr8, rr10
	jr	mi, 0f
	jr	z, 0f
	subl	rr8, $1
0:
	subl	rr0, rr0
	subl	rr0, rr10
	ldl	rr10, rr0
1:
	test	r4			/ step q2 until 0 <= R2 < B
	jr	pl, 2f
	subl	rr2, $1
	addl	rr6, rr10
	adc	r5, r9
	adc	r4, r8
	jr	un, 1b
2:
	subl	rr6, rr10
	sbc	r5, r9
	sbc	r4, r8
	jr	mi, 3f
	addl	rr2, $1
	jr	un, 2b
3:
	popl	rr6, (rr14)
	jr	un, 4b
retz:
	subl	rr0, rr0
	subl	rr2, rr2
	jr	un, 9b
retinf:
	ld	r0, $2047*16
	or	r0, r13
	sub	r1, r1
	subl	rr2, rr2
	jr	un, 9b
