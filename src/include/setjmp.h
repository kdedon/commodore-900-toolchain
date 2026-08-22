/* SPDX-License-Identifier: BSD-3-Clause
 * Added alongside, not in place of, the Mark Williams notice below: the same
 * rights holder released COHERENT under BSD 3-Clause in 2015 (root LICENSE).
 */
/* (-lgl
 * 	COHERENT Version 4.0
 * 	Copyright (c) 1982, 1992 by Mark Williams Company.
 * 	All rights reserved. May not be copied without permission.
 -lgl) */
/*
 * setjmp.h
 * Structure for a setjmp environment.
 * i8086 SMALL model:	saves 3 words (SP, BP, return PC).
 * i8086 LARGE model:	saves 4 words (SP, BP, return PC segment:offset).
 * i386:		saves 6 dwords (EBP, ESP, return PC, ESI, EDI, EBX).
 * Z8001 (segmented):	saves 12 words -- the return PC pair + r6..r15
 *			(libc/gen/setjmp.s: `ldm (rr2),r4,$12').
 */

#ifndef	SETJMP_H
#define	SETJMP_H	SETJMP_H

#if	_I386
typedef	int	jmp_buf[6];
#else
#ifdef	Z8001
typedef	int	jmp_buf[12];
#else
typedef	int	jmp_buf[4];
#endif
#endif

#endif

/* end of setjmp.h */
