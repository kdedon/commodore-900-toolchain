/*
 * Copyright (c) 1977-1995 Robert Swartz.
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * Standard I/O Library
 * Write out any unwritten data in buffer
 */

#include <stdio.h>
#include <errno.h>

int
fflush(fp)
register FILE	*fp;
{
	register int	cc, n, oerrno;

	oerrno = errno;
	n = errno = fp->_cc = 0;
	if (fp->_ff&_FERR) {
		n = EOF;
	} else if ((cc = fp->_cp - fp->_dp) <= 0
	 || write(fileno(fp), fp->_dp, cc) == cc
	 || errno == EINTR) {
		if (cc < 0)
			;
		else if (fp->_cp == _ep(fp))
			fp->_dp = fp->_cp = fp->_bp;
		else
			fp->_dp = fp->_cp;
	} else {
		fp->_ff |= _FERR;
		n = EOF;
	}
	/*
	 * errno belongs to the caller: a call that reported no failure leaves
	 * behind the value it found.
	 */
	if (errno == 0)
		errno = oerrno;
	return (n);
}
