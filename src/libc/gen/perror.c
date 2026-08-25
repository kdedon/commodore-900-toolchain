/*
 * Copyright (c) 1977-1995 Robert Swartz.
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * Print error messages based on value in `errno'.
 */

#include <stdio.h>

extern	int	errno;
extern	char	*sys_errlist[];
extern	int	sys_nerr;

perror(s)
register char *s;
{
	register char *es;

	/* The lower bound matters as much as the upper one: errno is an ordinary
	 * int that any library can assign, and a negative value indexed
	 * sys_errlist[] backwards and printed whatever lay in front of it. */
	if (errno >= 0 && errno < sys_nerr)
		es = sys_errlist[errno]; else
		es = "Bad error number";
	if (s != NULL) {
		fputs(s, stderr);
		fputs(": ", stderr);
	}
	fputs(es, stderr);
	fputs("\n", stderr);
}
