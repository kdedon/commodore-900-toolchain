/*
 * diag.c - host-ported (stdarg) compiler diagnostics. Replaces common/diag.c.
 *
 * The original cerror/cwarn/cstrict/cfatal/cbotch/cnomem were K&R `f(fp, args)`
 * and called `cmsg(fp, &args, ...)` -- passing the ADDRESS of the second parameter
 * so cmsg could walk the stack argument list. That is UB and CRASHES on x86-64
 * (the variadic args are in registers, so `&args` + walking reads garbage -- the
 * first error message segfaults). Rewritten with <stdarg.h>: the diagnostic
 * functions are variadic and hand a va_list to cmsg(), which consumes the
 * format's %d/%s/%X arguments via va_arg(). cmsg is a custom mini-vfprintf (%X =
 * long-hex), so it can't be delegated to the libc vfprintf.
 *
 * Dual-build: identical correctness on the 16-bit Z8001 self-host (va_arg reads
 * the promoted-int / pointer just as the old stack walk did, but portably).
 */
#include <stdio.h>
#include <stdarg.h>
#include <setjmp.h>
#include "mch.h"
#include "host.h"
#include "stream.h"
#include "var.h"

int nerr = 0;             /* Error counter */
char *passname = NULL;    /* Pass identifier string */

extern int line;
extern char file[];
extern FILE *ifp;
extern long ftell();
#if OVERLAID
extern jmp_buf death;
#endif

static void cmsg(char *fp, va_list ap, char *bp, int flag);

/* user program error; bumps the error count */
void cerror(char *fp, ...)
{
	va_list ap;
	va_start(ap, fp);
	cmsg(fp, ap, NULL, 0);
	va_end(ap);
	++nerr;
}

void cwarn(char *fp, ...)
{
	if (notvariant(VNOWARN)) {
		va_list ap;
		va_start(ap, fp);
		cmsg(fp, ap, "Warning", 0);
		va_end(ap);
	}
}

void cstrict(char *fp, ...)
{
	if (notvariant(VNOWARN)) {
		va_list ap;
		va_start(ap, fp);
		cmsg(fp, ap, "Strict", 0);
		va_end(ap);
	}
}

void cfatal(char *fp, ...)
{
	va_list ap;
	va_start(ap, fp);
	cmsg(fp, ap, "Fatal error", 1);
	va_end(ap);
#if !OVERLAID
	exit(ABORT);
#else
	longjmp(death, 1);
#endif
}

#if TINY
/* Sanitize a botch message for external consumption. (unchanged) */
char *botch_message(msg) char *msg;
{
	static char newmsg[32];
	static char digit[] = "0123456789ABCDEF";
	char *p, *q, c, sw;
	unsigned crypt;

	crypt = 0x3141;
	sw = 0;
	q = newmsg + 4;
	for (p = msg; c = *p++;) {
		if (crypt & 0x8000)
			crypt ^= 0xE178;
		crypt = c ^ (crypt << 1);
		if ('%' == c)
			sw = 1;
		if (sw && (' ' == (*q++ = c)))
			sw = 0;
	}
	*q = '\0';
	newmsg[3] = digit[crypt & 0xF];
	crypt >>= 4; newmsg[2] = digit[crypt & 0xF];
	crypt >>= 4; newmsg[1] = digit[crypt & 0xF];
	crypt >>= 4; newmsg[0] = digit[crypt & 0xF];
	return newmsg;
}
#endif

void cbotch(char *fp, ...)
{
	va_list ap;
	va_start(ap, fp);
#if TINY
	fp = botch_message(fp);
#endif
	cmsg(fp, ap, "Internal compiler error: ", 1);
	va_end(ap);
#if !OVERLAID
	exit(ABORT);
#else
	longjmp(death, 1);
#endif
}

void cnomem(char *fp, ...)
{
	va_list ap;
	va_start(ap, fp);
#if !TINY
	cmsg(fp, ap, "Out of space", 1);
#endif
	va_end(ap);
	cfatal("out of space");
}

/* Put out a message, tagged with line number + file name. */
static void cmsg(char *fp, va_list ap, char *bp, int flag)
{
	register int c;

	if (isvariant(VQUIET))
		return;
	if (line != 0)
		fprintf(stderr, "%d: ", line);
	if (file[0])
		fprintf(stderr, "%s: ", file);
#if !TINY
	if (flag != 0) {
		if (ifp != NULL)
			fprintf(stderr, "At %ld: ", ftell(ifp));
#if TEMPBUF
		else if (inbuf != NULL)
			fprintf(stderr, "At %d: ", inbufp - inbuf);
#endif
	}
#endif
	if (flag != 0 && passname != NULL)
		fprintf(stderr, "In %s: ", passname);
	if (bp != NULL)
		fprintf(stderr, "%s: ", bp);
	while ((c = *fp++) != '\0') {
		if (c != '%')
			fputc(c, stderr);
		else {
			c = *fp++;
			switch (c) {
			case 'd':
				fprintf(stderr, "%d", va_arg(ap, int));
				break;
			case 's':
				fprintf(stderr, "%s", va_arg(ap, char *));
				break;
			case 'X':
				fprintf(stderr, "%lx", va_arg(ap, long));
				break;
			default:
				fputc(c, stderr);
			}
		}
	}
	fputc('\n', stderr);
}

/* end of diag.c (host-ported) */
