/*
 * Copyright (c) 1977-1995 Robert Swartz.
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * Standard I/O Library Internals
 * Buffered Input; read a bufferfull
 */

#include <stdio.h>
#include <errno.h>

int
_fgetb(fp)
register FILE	*fp;
{
	extern	int	_fputt();
	register int	oerrno;

	if (fflush(fp))
		return (EOF);
	if (stdout->_pt==&_fputt)	/* special kludge */
		fflush(stdout);
	oerrno = errno;
	errno = 0;
	fp->_cc = -read(fileno(fp), fp->_dp, _ep(fp) - fp->_dp);
	/*
	 * errno belongs to the caller: a read that succeeded leaves behind the
	 * value it found.
	 */
	if (errno == 0)
		errno = oerrno;
	if (fp->_cc == 1) {
		if (errno != EINTR)
			fp->_ff |= _FERR;
		fp->_cc = 0;
		return (EOF);
	} else if (fp->_cc == 0) {
		fp->_ff |= _FEOF;
		return (EOF);
	} else {
		fp->_dp -= fp->_cc++;
		return (*fp->_cp++);
	}
}
