/*
 * Standard I/O library vfprintf/vprintf.
 * Formatted print of an argument list already walked by the caller.
 *
 * The formatter is printf.c's _doprnt(); a va_list and the "pointer to the
 * arguments after the format" that _doprnt takes are the same object on this
 * machine, since <stdarg.h> makes va_list a plain char * into the frame.
 */

#include <stdio.h>
#include <stdarg.h>

int
vfprintf(fp, fmt, args)
FILE *fp;
char *fmt;
va_list args;
{
	return (_doprnt(fp, fmt, (int *)args));
}

int
vprintf(fmt, args)
char *fmt;
va_list args;
{
	return (_doprnt(stdout, fmt, (int *)args));
}
