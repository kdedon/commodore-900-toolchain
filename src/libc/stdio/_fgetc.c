/*
 * Standard I/O Library Internals
 * Unbuffered input
 */

#include <stdio.h>
#include <errno.h>

int
_fgetc(fp)
register FILE	*fp;
{
	register unsigned char	s[1];
	extern	int	_fputt();
	register int	n, oerrno;

	if (stdout->_pt==&_fputt)		/* special kludge */
		fflush(stdout);
	fp->_cc = 0;
	oerrno = errno;
	errno = 0;
	n = EOF;
	switch (read(fileno(fp), s, 1)) {
	case -1:
		if (errno != EINTR)
			fp->_ff |= _FERR;
		break;
	case 0:
		fp->_ff |= _FEOF;
		break;
	default:
		n = s[0];
		break;
	}
	/*
	 * errno belongs to the caller: a read that succeeded leaves behind the
	 * value it found.
	 */
	if (errno == 0)
		errno = oerrno;
	return (n);
}
