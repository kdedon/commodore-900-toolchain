/*
 * Copyright (c) 1977-1995 Robert Swartz.
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * Sbrk - grow memory in data segment by
 * a specified increment.
 * Special version that does Commodore Large model Z8001
 */
#include <stdio.h>
#include <types.h>

extern	int	errno;
extern	vaddr_t	__end;

char *
sbrk(incr)
unsigned int	incr;
{
	extern	char	*brk();
	register vaddr_t send,
			rend;
	vaddr_t		oend;

#if 1		/* On the z8001 (at least) reduce the waste */
	rend = __end;
#else
	rend = brk(NULL);
#endif
	if (incr == 0)
		return ((char *)rend);
	oend = rend;
#ifdef	Z8001
	/*
	 * A user address is seg:off with a SIXTEEN-bit offset and pointer
	 * arithmetic does not carry out of it, so no single object may straddle a
	 * segment boundary.  When this increment would carry, abandon the tail of
	 * the current segment and start the block at offset 0 of the next one.
	 * The tail is wasted deliberately: a block that wrapped would alias the
	 * low end of the segment it started in, which is silent corruption rather
	 * than a failed allocation.
	 *
	 * The segment number lives in bits 24..30 (machz8001.h ADDR), so the next
	 * segment is +0x01000000, not +0x10000.
	 */
	if (((unsigned)rend + incr) < (unsigned)rend)
		rend = rend - (unsigned)rend + 0x01000000L;
	send = rend + incr;
#else
	send = rend + incr;
	if (send < rend)
		return (NULL);
#endif
	errno = 0;
	brk(send);
	if (errno) {
		/*
		 * brk() commits __end before making the system call (brk.s) and
		 * has no way to undo that, so a REFUSED break leaves __end
		 * pointing at memory the process does not have.  Put it back, or
		 * the next sbrk() measures from an address the kernel rejected --
		 * which is exactly the state a process is in the moment it
		 * reaches the end of its data segment.
		 */
		__end = oend;
		return (NULL);
	}
	return ((char *)rend);
}
