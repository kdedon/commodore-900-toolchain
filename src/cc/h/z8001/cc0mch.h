/*
 * Copyright (c) 2026 Kevin Dedon.
 * SPDX-License-Identifier: MIT
 */
/*
 * h/z8001/cc0mch.h
 * Machine-specific parser definitions (float input + bitfield align). Segmented
 * Z8001. Software-fp (DECVAX) constants are format-driven, identical to i386.
 */

/*
 * Some definitions for the portable floating point input code.
 * Used by the multiprecision integer package.
 * mch.h has set either IEEE or DECVAX to 1.
 * Both formats use 8 byte double constants with the sign bit in the same place.
 */

#define	NBIG	8			/* Loop limit, etc.		*/
typedef	unsigned char	BIG[NBIG];	/* Unsigned, holds 64 bits	*/
#define	t5ne(n)	((n[0]&0370)!=0)	/* Check if top 5 bits clear	*/
#define	cbit(n)	(((n)>>8)&0377)		/* Get 'carry' for addition	*/
#define	MSBBIG	0200			/* Top bit of each thing	*/

#if	IEEE
#define	IROUND	6			/* IEEE format			*/
#define	BROUND	010			/* 52 bits			*/
#define	EXPBIAS	1023			/* binary exponent bias		*/
#define	EXPMAX	2046			/* maximum biased binary exponent */
#else
#define	IROUND	6			/* DEC VAX-11 format		*/
#define	BROUND	01			/* 55 bits			*/
#define	EXPBIAS	129			/* binary exponent bias		*/
#define	EXPMAX	255			/* maximum biased binary exponent */
#endif

/* This macro determines which bit field base types are promoted. */
#define doalign(t)		0

/*
 * The macro expansion buffer.  An argument is held three times over while it
 * is substituted -- as collected, as expanded, and the expansion being built --
 * and an identifier in each copy carries a hide-set byte, so an argument may
 * be about a third of the buffer.  The donor's 1024 bytes stop at a condition
 * of a dozen clauses; 4096 takes about 1400 characters for 3 K of cc0's 64 K
 * data segment.
 */
#define	NDBUF	4096

/* end of h/i386/cc0mch.h */
