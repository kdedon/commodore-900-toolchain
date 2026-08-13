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
 * Structure for the /etc/group file.
 */

#ifndef	GRP_H
#define	GRP_H	GRP_H

struct group {
	char	*gr_name;
	char	*gr_passwd;
	int	gr_gid;
	char	**gr_mem;
};

struct	group	*getgrent();
struct	group	*getgrgid();
struct	group	*getgrnam();

#endif
