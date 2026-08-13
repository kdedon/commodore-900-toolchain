/*
 * getcwd.c
 * C library.
 * getcwd() -- POSIX 5.2.2, over COHERENT's getwd().
 *
 * getwd() takes no buffer and answers with a static string; getcwd() fills the
 * caller's.  Copying is all that separates them, and a port that wants the POSIX
 * name should not have to know which one this system shipped.
 *
 * getcwd(NULL, size) -- the GNU extension that allocates -- is not provided:
 * nothing here relies on it, and a caller that gets a null buffer back cannot
 * tell it from a failure.
 */

#include <stdio.h>
#include <string.h>
#include <errno.h>

extern	char	*getwd();

char *getcwd(buf, size) char *buf; int size;
{
	register char *p;

	if (buf == NULL || size <= 0) {
		errno = EINVAL;
		return (NULL);
	}
	if ((p = getwd()) == NULL)
		return (NULL);
	if (strlen(p) >= size) {
		errno = ERANGE;
		return (NULL);
	}
	strcpy(buf, p);
	return (buf);
}
