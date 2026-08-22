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
 * Structure of the login records in `/etc/utmp'
 * as well as the cummulative records in
 * `/usr/adm/wtmp'.
 */

#ifndef	UTMP_H
#define	UTMP_H	UTMP_H

#ifndef DIRSIZ
#define	DIRSIZ	14
#endif

#include <sys/types.h>

/*
 * No `#pragma align 1' around this structure.  It would not change the layout
 * -- ut_time follows 22 bytes of char, already even, so member alignment 1 and
 * alignment 2 both put it at offset 22 and both make the record 26 bytes --
 * and the June 1985 preprocessor diagnoses `#pragma' as an illegal control
 * line wherever it appears, including inside a conditional it is skipping,
 * so there is no spelling of it that all three preprocessors read.
 */
struct	utmp {
	char	ut_line[8];		/* tty name */
	char	ut_name[DIRSIZ];	/* User name */
	time_t	ut_time;		/* time signed on */
};

#endif
