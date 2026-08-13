/*
 * syslog(3) -- hand one record to syslogd.
 *
 * The record goes down the FIFO /dev/log as a single write, formatted
 *
 *	<pri>Mmm dd hh:mm:ss tag[pid]: message\n
 *
 * and is never longer than LOG_RECMAX.  Both properties are what make a log
 * with several writers readable: the kernel guarantees a write of less than
 * PIPSIZE (5120) bytes to a pipe is atomic, so a record under that size
 * cannot interleave with another process's record, and a record that is one
 * write is also one line.
 *
 * Three ways this can cost the caller something, and what is done about each:
 *
 *   The FIFO fills because syslogd is not draining it.  The descriptor is
 *   opened O_NDELAY, so the kernel returns a short write instead of putting
 *   the caller to sleep in psleep() until a reader appears -- which, with no
 *   reader coming, is forever.  The record is dropped.
 *
 *   Nothing has the FIFO open for reading.  O_NDELAY makes that failure
 *   happen at open(2), with ENXIO, rather than as a SIGPIPE at write time.
 *
 *   syslogd exits between the open and the write.  That is a genuine SIGPIPE
 *   and would kill a daemon because the LOGGER died, so it is ignored across
 *   the write and the disposition restored afterwards; the write then fails
 *   with EPIPE, the descriptor is closed, and one reopen is attempted.
 *
 * errno is preserved across every entry point here: %m formats it, and a
 * caller that logs an error and then reports it must see the same value.
 */

#include <sys/types.h>
#include <stdio.h>
#include <stdarg.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <errno.h>
#include <syslog.h>

extern	int	errno;
extern	char	*ctime();
extern	char	*strerror();
extern	long	time();
extern	int	getpid();

#define	TAGMAX	32		/* longest tag kept from openlog() */

static	int	LogFile = -1;		/* the FIFO, or -1 */
static	int	LogStat = 0;		/* openlog() options */
static	int	LogFac = LOG_USER;	/* openlog() default facility */
static	int	LogMask = 0xff;		/* setlogmask(): all levels */
static	char	LogTag[TAGMAX+1];	/* openlog() tag, "" for none */

/*
 * Decimal conversion into a caller's buffer, returning a pointer past the
 * digits.  printf is not used for the record's fixed part because syslog()
 * may be called from a signal handler, where a shared FILE is not safe.
 */
static char *
putnum(cp, n)
register char *cp;
register int n;
{
	char	buf[8];
	register char *ep;

	ep = &buf[sizeof(buf)];
	*--ep = '\0';
	if (n < 0) {
		*cp++ = '-';
		n = -n;
	}
	do
		*--ep = '0' + n % 10;
	while ((n /= 10) != 0);
	while (*ep != '\0')
		*cp++ = *ep++;
	return (cp);
}

/*
 * Open the FIFO if it is not open.  Returns the descriptor or -1.
 */
static
logopen()
{
	if (LogFile >= 0)
		return (LogFile);
	if ((LogFile = open(_PATH_LOG, O_WRONLY|O_NDELAY)) >= 0)
		fcntl(LogFile, F_SETFD, FD_CLOEXEC);
	return (LogFile);
}

/*
 * Copy the caller's format into `to', expanding %m to the text of `err'.
 * Done before the conversion rather than inside it so the formatter stays
 * the standard one.
 */
static
expandm(to, size, fmt, err)
char *to;
int size;
register char *fmt;
int err;
{
	register char *p;
	register char *e;
	char	*end;

	p = to;
	end = to + size - 1;
	while (*fmt != '\0' && p < end) {
		if (fmt[0] == '%' && fmt[1] == 'm') {
			fmt += 2;
			for (e = strerror(err); *e != '\0' && p < end; )
				*p++ = *e++;
		} else
			*p++ = *fmt++;
	}
	*p = '\0';
}

void
openlog(ident, logstat, logfac)
char *ident;
int logstat;
int logfac;
{
	int	saved;

	saved = errno;
	LogTag[0] = '\0';
	if (ident != (char *)0) {
		strncpy(LogTag, ident, TAGMAX);
		LogTag[TAGMAX] = '\0';
	}
	LogStat = logstat;
	if (logfac != 0 && (logfac & ~LOG_FACMASK) == 0)
		LogFac = logfac;
	if (LogStat & LOG_NDELAY)
		logopen();
	errno = saved;
}

void
closelog()
{
	int	saved;

	saved = errno;
	if (LogFile >= 0)
		close(LogFile);
	LogFile = -1;
	LogStat = 0;
	LogTag[0] = '\0';
	errno = saved;
}

/*
 * Set the mask of levels that will be sent; returns the previous mask.
 * A zero argument only asks, it does not silence the log.
 */
setlogmask(mask)
int mask;
{
	int	old;

	old = LogMask;
	if (mask != 0)
		LogMask = mask;
	return (old);
}

void
vsyslog(pri, fmt, ap)
int pri;
char *fmt;
va_list ap;
{
	char	rec[LOG_RECMAX];
	char	efmt[LOG_RECMAX];
	register char *p;
	char	*ts;
	long	now;
	int	saved, len, room, tries;
	void	(*oldpipe)();

	saved = errno;
	if ((LOG_MASK(LOG_PRI(pri)) & LogMask) == 0)
		return;
	if ((pri & LOG_FACMASK) == 0)
		pri |= LogFac;

	/* The fixed part: priority, timestamp, tag, pid. */
	p = rec;
	*p++ = '<';
	p = putnum(p, pri);
	*p++ = '>';
	time(&now);
	ts = ctime(&now);		/* "Mmm dd hh:mm:ss yyyy\n", offset 4 */
	if (ts != (char *)0) {
		strncpy(p, ts + 4, 15);
		p += 15;
	}
	*p++ = ' ';
	if (LogTag[0] != '\0') {
		strcpy(p, LogTag);
		p += strlen(p);
		if (LogStat & LOG_PID) {
			*p++ = '[';
			p = putnum(p, getpid());
			*p++ = ']';
		}
		*p++ = ':';
		*p++ = ' ';
	}

	/* The caller's message, clipped to what is left after the newline. */
	expandm(efmt, sizeof(efmt), fmt, saved);
	room = LOG_RECMAX - (p - rec) - 1;
	p += vsnprintf(p, room, efmt, ap);
	*p++ = '\n';
	len = p - rec;

	/*
	 * Send it.  One reopen, because the common failure is syslogd having
	 * been restarted since this process last logged; a second failure is
	 * a syslogd that is not running, and the record is dropped.
	 */
	oldpipe = signal(SIGPIPE, SIG_IGN);
	for (tries = 0; tries < 2; tries++) {
		if (logopen() < 0)
			break;
		if (write(LogFile, rec, len) == len) {
			signal(SIGPIPE, oldpipe);
			errno = saved;
			return;
		}
		close(LogFile);
		LogFile = -1;
	}
	signal(SIGPIPE, oldpipe);

	/*
	 * Nothing took it.  LOG_CONS asks for the console rather than
	 * silence -- the message the machine cannot afford to lose is the one
	 * saying the logging is broken.  The priority prefix is dropped: a
	 * person is reading this one.
	 */
	if (LogStat & LOG_CONS) {
		int	fd;

		if ((fd = open("/dev/console", O_WRONLY|O_NDELAY)) >= 0) {
			for (p = rec; *p != '>' && *p != '\0'; p++)
				;
			if (*p == '>')
				p++;
			else
				p = rec;
			write(fd, p, len - (p - rec));
			close(fd);
		}
	}
	errno = saved;
}

void
syslog(pri, fmt)
int pri;
char *fmt;
{
	va_list	ap;

	va_start(ap, fmt);
	vsyslog(pri, fmt, ap);
	va_end(ap);
}
