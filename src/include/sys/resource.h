/* SPDX-License-Identifier: MIT */
/*
 * Resource limits.  The C900 kernel enforces RLIMIT_STACK only: exec gives a
 * program a stack of the soft limit, and the arguments and environment may
 * fill all of it but 4 KB.  The other resources are named for portability;
 * getrlimit() and setrlimit() refuse them with EINVAL.
 */
#ifndef	RESOURCE_H
#define	RESOURCE_H

#define	RLIMIT_CPU	0		/* CPU time, seconds */
#define	RLIMIT_FSIZE	1		/* File size, bytes */
#define	RLIMIT_DATA	2		/* Data segment, bytes */
#define	RLIMIT_STACK	3		/* Stack segment, bytes */
#define	RLIMIT_CORE	4		/* Core file, bytes */
#define	RLIM_NLIMITS	5

typedef	long	rlim_t;

#define	RLIM_INFINITY	0x7FFFFFFFL	/* As much as the system can give */

struct	rlimit {
	rlim_t	rlim_cur;		/* Soft limit */
	rlim_t	rlim_max;		/* Hard limit */
};

#endif
