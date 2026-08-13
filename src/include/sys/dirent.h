/* SPDX-License-Identifier: BSD-3-Clause
 * Added alongside, not in place of, the Mark Williams notice below: the same
 * rights holder released COHERENT under BSD 3-Clause in 2015 (root LICENSE).
 */
/* (-lgl
 * 	COHERENT Version 4.0
 * 	Copyright (c) 1982, 1992 by Mark Williams Company.
 * 	All rights reserved. May not be copied without permission.
 -lgl) */
struct dirent {
	long		d_ino;		/* i-node number */
	daddr_t		d_off;		/* offset in actual directory */
	unsigned short	d_reclen;  	/* record length */
	char		d_name[1];
};
