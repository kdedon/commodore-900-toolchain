/*
 * Standard I/O library vsprintf/vsnprintf.
 * Formatted print into a string from an argument list already walked by the
 * caller.
 *
 * vsprintf writes without a bound, exactly as sprintf() does.  vsnprintf takes
 * one: _stropen() with a negative length arms the string FILE with a character
 * count, so putc() stops storing when the count runs out, and _doprnt() still
 * returns the length the whole conversion would have had.  A caller that must
 * fit a record into a fixed record size wants the second one.
 */

#include <stdio.h>
#include <stdarg.h>
#include <mdata.h>

int
vsprintf(sp, fmt, args)
char *sp;
char *fmt;
va_list args;
{
	FILE	file;
	int	count;

	_stropen(sp, -MAXINT-1, &file);
	count = _doprnt(&file, fmt, (int *)args);
	putc('\0', &file);
	return (count);
}

int
vsnprintf(sp, size, fmt, args)
char *sp;
int size;
char *fmt;
va_list args;
{
	FILE	file;
	int	count;

	if (size <= 0)
		return (0);
	_stropen(sp, -(size-1), &file);
	count = _doprnt(&file, fmt, (int *)args);
	if (count > size-1)
		count = size-1;
	sp[count] = '\0';
	return (count);
}
