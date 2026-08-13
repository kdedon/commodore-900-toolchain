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
 * System status structure
 */

struct ustat {
	daddr_t	f_tfree;	/* Total free bloks */
	ino_t	f_tinode;	/* Number of free inodes */
	char	f_fname[6];	/* File system name (label) */
	char	f_fpack[6];	/* File system pack name */
};
