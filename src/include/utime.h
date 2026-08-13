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
 * Access and modification times, for utime().
 */

#ifndef	 UTIME_H
#define	 UTIME_H	UTIME_H

#include <sys/types.h>

struct utimbuf {
	time_t	actime;			/* Access time */
	time_t	modtime;		/* Modification time */
};

extern int utime();

#endif
