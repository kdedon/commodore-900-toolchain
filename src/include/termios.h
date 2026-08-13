/*
 * termios.h -- POSIX names for the terminal calls provided.
 *
 * Not a termios implementation.  The kernel's line discipline is termio
 * (<termio.h>, struct termio, the TC* ioctls), and the functions declared
 * here are the thin shims in libc/gen that reach it, so the header pulls
 * <termio.h> in rather than redefining anything.  Only the calls that
 * exist are declared.
 *
 * Argument names for tcflow(): TCOOFF and TCOON are honoured; TCIOFF and
 * TCION ask the discipline to send stop/start characters on the input
 * side, which it has no queue for, so they fail with EINVAL.
 */
#ifndef	TERMIOS_H
#define	TERMIOS_H	TERMIOS_H

#include <termio.h>

#define	TCOOFF	0		/* Suspend output */
#define	TCOON	1		/* Restart output */
#define	TCIOFF	2		/* Transmit a STOP character */
#define	TCION	3		/* Transmit a START character */

int	tcflow();
int	tcflush();

#endif	/* TERMIOS_H */
