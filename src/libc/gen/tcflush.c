/*
 * Tcflush -- discard queued terminal input and/or output.
 *
 * A compatibility shim, not a termios implementation.  This port's tty is sgtty
 * (KTTY=sgtty; the 4.x termio discipline exists in the kernel tree but is over
 * the one-segment text budget and is not linked), while programs ported from BSD
 * and 4.x sources call tcflush().
 *
 * IT ALWAYS FLUSHES BOTH QUEUES.  sgtty's TIOCFLUSH takes no argument -- the
 * kernel's ttioctl() sets both its flush and drain flags for that ioctl and never
 * looks at the caller's value (sys/drv/tty-sgtty.c) -- so the queue selector can
 * only be validated, not honoured.  Every caller in this tree asks for
 * TCIFLUSH (input), which is satisfied; a caller asking for TCOFLUSH also loses
 * pending input, which is why this says so rather than pretending otherwise.
 * Selective flushing needs the termio discipline, and that needs WS2's text.
 *
 * The selectors are termio's TCFLSH arguments: 0 = input, 1 = output, 2 = both.
 */

#include <sgtty.h>
#include <errno.h>

tcflush(fd, queue)
int fd;
int queue;
{
	if (queue < 0 || queue > 2) {
		errno = EINVAL;
		return (-1);
	}
	return (ioctl(fd, TIOCFLUSH, (char *)0));
}
