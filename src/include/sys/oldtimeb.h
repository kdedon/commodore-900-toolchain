/* SPDX-License-Identifier: BSD-3-Clause
 * Added alongside, not in place of, the Mark Williams notice below: the same
 * rights holder released COHERENT under BSD 3-Clause in 2015 (root LICENSE).
 */
/* (-lgl
 * 	COHERENT Version 3.0
 * 	Copyright (c) 1982, 1990 by Mark Williams Company.
 * 	All rights reserved. May not be copied without permission.
 -lgl) */
/*
 * Time buffer.
 */

#ifndef	 TIMEB_H
#define	 TIMEB_H	TIMEB_H

/*
 * No `#pragma align 2' in this header.  Two is the alignment this machine
 * gives every scalar already -- a long sits on an even boundary, not on a
 * multiple of four -- so the pragma would name the alignment in force and
 * change no offset and no size.  The June 1985 preprocessor, which reads
 * these headers when the 1985 compiler is the flavour building, diagnoses
 * `#pragma' as an illegal control line wherever it stands, including inside
 * a conditional it is skipping, so there is no spelling of it that all three
 * preprocessors read.
 */

#include <sys/types.h>

struct timeb {
	long	time;			/* Time since 1970 */
	unsigned short millitm;		/* Milliseconds */
	short	timezone;		/* Time zone */
	short	dstflag;		/* Daylight saving time applies */
};

#endif
