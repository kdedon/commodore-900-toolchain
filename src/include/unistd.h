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
 * /usr/include/unistd.h
 * Cf. Intel iBSC2, pp. 6-82, 6-83.
 */

#ifndef	_UNISTD_H
#define	_UNISTD_H

/* Access modes. */
#define	F_OK	0
#define	X_OK	1
#define	W_OK	2
#define	R_OK	4

/* lockf() commands. */
#define	F_ULOCK	0		/* unlock region			*/
#define	F_LOCK	1		/* sleep until available and lock	*/
#define	F_TLOCK	2		/* lock if available, EAGAIN if not	*/
#define	F_TEST	3		/* return 0 if available, EAGAIN if not	*/

/* Seek positions. */
#define	SEEK_SET	0	/* from beginning			*/
#define	SEEK_CUR	1	/* from current position		*/
#define	SEEK_END	2	/* from end				*/

/* File descriptors for standard FILEs. */
#define	STDIN_FILENO	0
#define	STDOUT_FILENO	1
#define	STDERR_FILENO	2

/*
 * Prototypes.  sbrk()/brk() MUST be declared: they return a far (char *),
 * and callers that omit the declaration (e.g. the MBLOCK malloc, which
 * includes <unistd.h> but not <stdio.h>) would otherwise default them to
 * int, truncating the 32-bit far pointer to 16 bits and losing the segment
 * -- yielding a wild seg-0 pointer whose first dereference faults.
 */
extern	char	*sbrk();
extern	char	*brk();

/*
 * ttyname() for the same reason, and it is not hypothetical: hunt(6) called it
 * undeclared and died in the strcpy of its result with nothing but
 * "Segmentation violation" to show for it.  cmd/tty.c happens to carry its own
 * `char *ttyname();' and therefore works, which is precisely how this stays
 * hidden -- one caller declares it, the next does not, and only the second
 * crashes.  Anything here that returns a pointer belongs in this list.
 */
extern	char	*ttyname();
extern	char	*getlogin();
extern	char	*getcwd();
extern	char	*getwd();
extern	int	isatty();

/*
 * getopt(3) and its four globals (libc/gen/getopt.c).  optarg is the one that
 * matters for the same reason as the pointers above; the three ints are here
 * because a caller that declares them itself and a caller that does not have to
 * agree on where they live.
 */
extern	int	getopt();
extern	char	*optarg;
extern	int	optind;
extern	int	opterr;
extern	int	optopt;

/*
 * Calls whose result is 32 bits wide.  lseek(), unique() and alarm2() are
 * LONG entries in the system-call table (z8001/src/tab.c), so the kernel
 * hands the value back in R0:R1 rather than R1 alone; ulimit() is libc's
 * long-valued stub for a call this kernel does not implement.
 */
extern	long	lseek();
extern	long	ulimit();
extern	long	unique();
extern	long	alarm2();

/* General functions returning a far (char *). */
extern	char	*crypt();
extern	char	*getpass();
extern	char	*mktemp();

#endif

/* end of unistd.h */
