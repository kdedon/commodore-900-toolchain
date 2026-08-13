/*
 * syslog.h
 * System logging: the priorities, the facilities and the client interface.
 *
 * A priority argument is a facility ORed with a level.  The level occupies the
 * low three bits, the facility the next seven, so the whole code fits in an
 * int on this machine (LOG_LOCAL7|LOG_DEBUG is 191).
 *
 * The transport is the FIFO named below, not a socket: this system has no
 * Unix-domain sockets, and the kernel makes a write of less than PIPSIZE
 * (5120) bytes to a pipe atomic, which is the property a log needs.
 */

#ifndef	SYSLOG_H
#define	SYSLOG_H

/* The rendezvous.  /etc/rc creates it with `mknod /dev/log p'. */
#define	_PATH_LOG	"/dev/log"

/* The longest record syslog() will send, newline included.  Far below
 * PIPSIZE, so one record is always one atomic write. */
#define	LOG_RECMAX	256

/* Priority levels, in descending order of urgency. */
#define	LOG_EMERG	0	/* system is unusable */
#define	LOG_ALERT	1	/* action must be taken immediately */
#define	LOG_CRIT	2	/* critical conditions */
#define	LOG_ERR		3	/* error conditions */
#define	LOG_WARNING	4	/* warning conditions */
#define	LOG_NOTICE	5	/* normal but significant condition */
#define	LOG_INFO	6	/* informational */
#define	LOG_DEBUG	7	/* debug-level messages */

#define	LOG_PRIMASK	0x07
#define	LOG_PRI(p)	((p) & LOG_PRIMASK)

/* Facilities: who is speaking. */
#define	LOG_KERN	(0<<3)	/* the kernel */
#define	LOG_USER	(1<<3)	/* random user-level messages */
#define	LOG_MAIL	(2<<3)	/* the mail system */
#define	LOG_DAEMON	(3<<3)	/* system daemons */
#define	LOG_AUTH	(4<<3)	/* authorisation: login, su, sudo */
#define	LOG_SYSLOG	(5<<3)	/* syslogd's own messages */
#define	LOG_LPR		(6<<3)	/* the line printer spooler */
#define	LOG_NEWS	(7<<3)	/* network news */
#define	LOG_UUCP	(8<<3)	/* UUCP */
#define	LOG_CRON	(9<<3)	/* cron and at */
#define	LOG_LOCAL0	(16<<3)	/* reserved for local use */
#define	LOG_LOCAL1	(17<<3)
#define	LOG_LOCAL2	(18<<3)
#define	LOG_LOCAL3	(19<<3)
#define	LOG_LOCAL4	(20<<3)
#define	LOG_LOCAL5	(21<<3)
#define	LOG_LOCAL6	(22<<3)
#define	LOG_LOCAL7	(23<<3)

#define	LOG_NFACILITIES	24
#define	LOG_FACMASK	0x03f8
#define	LOG_FAC(p)	(((p) & LOG_FACMASK) >> 3)
#define	LOG_MAKEPRI(fac, pri)	(((fac) << 3) | (pri))

/* openlog() option bits. */
#define	LOG_PID		0x01	/* put the pid in every message */
#define	LOG_CONS	0x02	/* write to the console when the FIFO fails */
#define	LOG_NDELAY	0x08	/* open the FIFO now, not at the first message */
#define	LOG_NOWAIT	0x10	/* accepted and ignored: nothing here forks */

/* setlogmask() arguments. */
#define	LOG_MASK(pri)	(1 << (pri))
#define	LOG_UPTO(pri)	((1 << ((pri)+1)) - 1)

void	openlog();
void	closelog();
void	syslog();
void	vsyslog();
int	setlogmask();

#endif

/* end of syslog.h */
