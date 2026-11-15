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
	.globl	drmul, dlmul
	.globl	SS

/ double multiply   product returned in rq0
/
/ drmul( da, db)
/ dlmul( da, &db)
/
/ Each fraction is split as h*2^32 + l with l a signed long, h one more
/ when l's top bit is set, so the four signed multiplies are exact.  With
/ L = al*bl, M = ah*bl + al*bh + (L >> 32) and T = ah*bh + (M >> 32), the
/ product is T*2^64 + (M mod 2^32)*2^32 + (L mod 2^32).  With a*512 and
/ b*4, T is the fraction.

drmul:
	lda	rr2, SS|12(r15)
	jr	un, 0f
dlmul:
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
	and	r1, r8
	jr	z, retz
	cp	r1, $2047*16
	jr	eq, retinf
	and	r0, r4
	jr	z, retz
	cp	r0, $2047*16
	jr	eq, retinf
	add	r0, r1			/ (exp - 1)*16 for a product of 2 or more
	sub	r0, $1023*16
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
	ldb	rh4, rl4		/ a*512 and b*4 put the product's
	ldb	rl4, rh5		/ fraction in T
	ldb	rh5, rl5
	ldb	rl5, rh6
	ldb	rh6, rl6
	ldb	rl6, rh7
	ldb	rh7, rl7
	subb	rl7, rl7
	slll	rr6
	rlc	r5
	rlc	r4
	slll	rr10
	rlc	r9
	rlc	r8
	slll	rr10
	rlc	r9
	rlc	r8
	bit	r6, $15
	jr	z, 0f
	addl	rr4, $1
0:
	bit	r10, $15
	jr	z, 0f
	addl	rr8, $1
0:
	pushl	(rr14), rr12
	pushl	(rr14), rr8		/ bh
	ldl	rr2, rr6
	multl	rq0, rr10		/ L = al*bl
	ldl	rr12, rr4
	multl	rq4, (rr14)		/ al*bh
	multl	rq8, rr12		/ ah*bl
	addl	rr10, rr6
	adc	r9, r5
	adc	r8, r4
	ldl	rr6, rr12
	multl	rq4, (rr14)		/ ah*bh
	popl	rr12, (rr14)
	ld	r12, r0
	sra	r12, $15
	addl	rr10, rr0		/ M
	adc	r9, r12
	adc	r8, r12
	ld	r12, r8
	sra	r12, $15
	addl	rr6, rr8		/ T
	adc	r5, r12
	adc	r4, r12
	popl	rr12, (rr14)

	bit	r4, $4			/ the fraction in rq4, the rounding bit
	jr	nz, 0f			/ at bit 15 of r10
	slll	rr10
	rlc	r7
	rlc	r6
	rlc	r5
	rlc	r4
	dec	r12, $16
	jr	mi, retz
0:
	cp	r12, $2046*16
	jr	uge, retinf
	bit	r10, $15		/ round to nearest, ties to even
	jr	z, 7f
	res	r10, $15
	or	r10, r11
	or	r10, r2
	or	r10, r3
	jr	nz, 6f
	bit	r7, $0
	jr	z, 7f
6:
	inc	r7, $1
	jr	nz, 7f
	inc	r6, $1
	jr	nz, 7f
	inc	r5, $1
	jr	nz, 7f
	inc	r4, $1
7:
	add	r12, r4			/ a carry out of the fraction is the
	ld	r0, r12			/ exponent's, as IEEE packs them
	or	r0, r13
	ld	r1, r5
	ldl	rr2, rr6
9:
	ldm	r6, (rr14), $8
	inc	r15, $16
	ret
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
