/*
 * Standard I/O Library
 * Rewind (position at beginning) file
 * The error and end-of-file indicators are cleared whatever the seek did, so a
 * stream that has reported either can be used again.  ANSI has rewind() return
 * nothing; this one returns the seek's status.
 */

#include <stdio.h>

int
rewind(fp)
register FILE	*fp;
{
	register int	status;

	status = fseek(fp, 0L, SEEK_SET);
	clearerr(fp);
	return (status);
}
