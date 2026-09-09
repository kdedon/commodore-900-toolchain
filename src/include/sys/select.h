/*
 * sys/select.h -- BSD select() emulated over poll() (cf. the Coherent 4.2
 * header of the same name: "an emulation of the BSD select() call via
 * poll()"; this is the 16-bit twin).  fd_set is a plain long bit mask:
 * FD_SETSIZE 32 covers NUFILE (24) with room.
 */
#ifndef	SYS_SELECT_H
#define	SYS_SELECT_H

#include <sys/types.h>

#ifndef	FD_SETSIZE
#define	FD_SETSIZE	32
#endif

typedef	struct fd_set {
	long	fds_bits;
} fd_set;

#define	FD_SET(n, p)	((p)->fds_bits |= (1L << (n)))
#define	FD_CLR(n, p)	((p)->fds_bits &= ~(1L << (n)))
#define	FD_ISSET(n, p)	(((p)->fds_bits & (1L << (n))) != 0)
#define	FD_ZERO(p)	((p)->fds_bits = 0L)

struct timeval {
	long	tv_sec;		/* seconds		*/
	long	tv_usec;	/* microseconds		*/
};

extern int select();

#endif
