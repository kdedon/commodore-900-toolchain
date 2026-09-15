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
 * Machine dependent signals.
 */

#ifndef	MSIG_H
#define	MSIG_H	MSIG_H

#define	SIGEPA	12			/* Extended processor trap (uni) */
#define	SIGPRV	13			/* Privileged instruction */
#define	SIGNVI	14			/* Non vectored interrupt */
#define	SIGNMI	15			/* Non-maskable interrupt (not passed) */
#define	SIGI16	16			/* Signal 16 */
#define NSIG	16			/* Number of signals */

/*
 * Special arguments to signal.
 */
#define	SIG_DFL	((int(*)())0)		/* Default */
#define	SIG_IGN	((int(*)())1)		/* Ignore */

#endif
