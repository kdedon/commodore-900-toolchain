/*
 * libc/gen/mkfifo.c
 * mkfifo()
 * POSIX function.
 */

#include <sys/types.h>
#include <sys/stat.h>

#ifdef USE_PROTO
int mkfifo(const char *path, mode_t mode)
#else
int
mkfifo(path, mode)
char * path;
mode_t mode;
#endif
{
	return mknod(path, mode | S_IFPIP, 0);
}

/* end of libc/gen/mkfifo.c */
