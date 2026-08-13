/*
 * Tcflow -- suspend and restart terminal output.
 *
 * TCOOFF raises T_STOP on the line and TCOON drops it and restarts the
 * transmitter (sys/drv/tty.c, case TCXONC).  This is the out-of-band form of
 * ^S/^Q: it reaches a line whose input side belongs to somebody else, which is
 * what a window system needs -- the server holds the pty master and the client
 * never sees a ^S typed at it.
 *
 * TCIOFF and TCION ask for the input-side pair.  The discipline has no
 * queue-side stop to give, so they are refused; the kernel answers EINVAL and
 * that is what comes back here, rather than a 0 that did nothing.
 *
 * The argument goes to ioctl BY VALUE, as TCFLSH's does: the kernel reads it
 * with `switch ((int)vec)'.  ioctl's third parameter is a pointer, so the
 * value is widened to one here -- an int pushed into a pointer-sized argument
 * slot leaves the kernel reading two bytes of the caller's stack past it.
 */

#include <termios.h>

tcflow(fd, action)
int fd;
int action;
{
	return (ioctl(fd, TCXONC, (char *)action));
}
