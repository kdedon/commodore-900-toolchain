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
 * This is the format of the header at the start of every archive member.
 * This is not the same as V7.
 * To prevent confusion the magic number is different.
 */

#ifndef	AR_H
#define	AR_H

#ifndef DIRSIZ
#include <sys/dir.h>
#endif

#define ARMAG	0177535			/* Magic number */

struct	ar_hdr {
	char	ar_name[DIRSIZ];	/* Member name */
	time_t	ar_date;		/* Time inserted */
	short	ar_gid;			/* Group id */
	short	ar_uid;			/* User id */
	short	ar_mode;		/* Mode */
	fsize_t	ar_size;		/* File size */
};
/*
 * Name of header module for ranlib
 */
#ifndef	HDRNAME
#define	HDRNAME "__.SYMDEF"
#endif
/*
 * Header module is list of all global defined symbols
 * in all load modules
 */
#ifndef	L_OUT_H
#include <n.out.h>
#endif
typedef	struct	ar_sym {
	char	ar_id[NCPLN];		/* symbol name */
	fsize_t	ar_off;			/* offset of load module */
} ar_sym;				/* ...from end of header module */

/*
 * An index naming a symbol longer than NCPLN characters starts with a
 * marker entry: ar_id[0] 0, ar_id[1] 1, the rest 0, and ar_off the offset
 * of a string table from the start of the header module.  The table is
 * laid out as an LF_LNAME object's (n.out.h) and ends the module.  A long
 * entry's ar_id is zero but for ar_id[4..7], as an ldsym's ls_id.
 */
#define	ARS_ISMARK(id)	((id)[0] == 0 && (id)[1] == 1)

#endif
