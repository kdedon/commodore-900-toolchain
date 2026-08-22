/* SPDX-License-Identifier: BSD-3-Clause
 * Added alongside, not in place of, the Mark Williams notice below: the same
 * rights holder released COHERENT under BSD 3-Clause in 2015 (root LICENSE).
 */
/* (-lgl
 * 	COHERENT Version 3.2
 * 	Copyright (c) 1982, 1991 by Mark Williams Company.
 * 	All rights reserved. May not be copied without permission.
 -lgl) */
/*
 * assert.h
 * C diagnostics header.
 * Draft Proposed ANSI C Standard, Section 4.2, 12/7/88 draft.
 */

#ifndef	ASSERT_H
#define	ASSERT_H	ASSERT_H

#if	NDEBUG
#define	assert(p)
#else
#include <stdio.h>
/*
 * Two spellings of one macro.  _MWC1985 is defined by the flavour that runs
 * the June 1985 /lib/cpp, and that preprocessor differs here twice over.
 *
 * It has no # operator: it copies `#p' through as text and the compiler then
 * reports "illegal # construct" at the assert.  Its own way of quoting an
 * argument is to expand a parameter inside a string literal, so "p" carries
 * the argument's text there -- and only there, since a preprocessor that
 * implements # does not expand inside a literal and would print the letter p
 * for every assertion.
 *
 * And its expansion buffer holds about 200 characters for one macro call, of
 * which the expanded condition is already most: quoting the argument as well
 * puts its text in twice and leaves room for a condition of some 50
 * characters, which several in this system exceed ("macro expansion
 * overflow", and the compile stops).  So that spelling reports the file and
 * the line and not the condition.  The test itself is the same one.
 */
#ifdef	_MWC1985
#define	assert(p)	if (!(p)) {\
				fprintf(stderr, "%s: %d: assertion failed.\n",\
					__FILE__, __LINE__);\
				exit(1);\
			}
#else
#define	assert(p)	if (!(p)) {\
				fprintf(stderr, "%s: %d: assert(%s) failed.\n",\
					__FILE__, __LINE__, #p);\
				exit(1);\
			}
#endif
#endif
#endif

/* end of assert.h */
