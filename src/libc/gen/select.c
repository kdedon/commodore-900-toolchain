/*
 * select() -- the BSD call emulated over the kernel poll() (syscall 67),
 * as Coherent 4.2 did: its select is "an emulation of the BSD select()
 * call via poll()".
 *
 * Semantics covered: read/write/except sets, blocking (tvp == NULL),
 * timed and zero-timeout polls.  A timeout of any length a struct timeval
 * can express is waited in full, whatever poll(2)'s own int of milliseconds
 * reaches, by making as many poll(2) calls as it takes.  On return the sets
 * are replaced by the ready subsets and the total ready-fd count is returned;
 * -1 on error.  POLLHUP/POLLERR report as readable (BSD practice: the read
 * wakes and fails); POLLNVAL sets errno EBADF.  A negative timeval is EINVAL.
 */
#include <sys/select.h>
#include <sys/poll.h>
#include <errno.h>

/*
 * The most poll(2) can be asked to wait, and the same span in whole seconds.
 * poll(2)'s timeout is an int of milliseconds -- the SVR4 contract, and what
 * the syscall table budgets for entry 67 -- so 32.767 s is all a single call
 * reaches.  The kernel's upoll() then adds (1000/HZ)-1 to it before dividing
 * into ticks, which overflows above 32758, so the usable ceiling is below even
 * that.  32000 is that ceiling rounded down to a whole number of seconds,
 * which is what lets a longer wait be split without carrying a millisecond
 * remainder between the pieces.
 *
 * Nothing about this limits select(): a wait longer than one poll(2) is served
 * as several, so any timeout a struct timeval can hold is waited in full.
 */
#define	MSECMAX	32000
#define	SECMAX	(MSECMAX / 1000)

extern int errno;

int
select(nfds, rfds, wfds, efds, tvp)
int nfds;
fd_set *rfds, *wfds, *efds;
struct timeval *tvp;
{
	struct pollfd pfd[FD_SETSIZE];
	register int fd, n;
	register struct pollfd *pp;
	int msec, ready, r, rms;
	long rsec, rbits, wbits, ebits;

	if (nfds < 0 || nfds > FD_SETSIZE) {
		errno = EINVAL;
		return (-1);
	}
	rbits = rfds != (fd_set *)0 ? rfds->fds_bits : 0L;
	wbits = wfds != (fd_set *)0 ? wfds->fds_bits : 0L;
	ebits = efds != (fd_set *)0 ? efds->fds_bits : 0L;

	n = 0;
	for (fd = 0; fd < nfds; fd++) {
		register long m;

		m = 1L << fd;
		if (((rbits|wbits|ebits) & m) == 0)
			continue;
		pp = &pfd[n++];
		pp->fd = fd;
		pp->events = 0;
		pp->revents = 0;
		if (rbits & m)
			pp->events |= POLLIN;
		if (wbits & m)
			pp->events |= POLLOUT;
		if (ebits & m)
			pp->events |= POLLPRI;
	}

	/*
	 * The wait is carried as whole seconds plus a sub-second remainder in
	 * milliseconds, NOT as a single millisecond count: a long of
	 * milliseconds runs out after 24 days, and a timeval holds 68 years.
	 * Split this way every timeval is representable, so there is no
	 * timeout this call has to refuse.  rsec < 0 means block.
	 *
	 * tv_usec is not assumed to be under a second -- callers do pass whole
	 * seconds in it -- so the carry is taken here rather than trusted, and
	 * the rounding is upwards: a wait must never be shorter than asked.
	 */
	rms = 0;
	if (tvp == (struct timeval *)0)
		rsec = -1L;
	else {
		/*
		 * A negative timeval is not a short wait, and it is not a
		 * blocking one either -- it is not a length at all.  Refused,
		 * because the alternative is to serve some other wait and
		 * report it as the one asked for.
		 */
		if (tvp->tv_sec < 0L || tvp->tv_usec < 0L) {
			errno = EINVAL;
			return (-1);
		}
		rsec = tvp->tv_sec + tvp->tv_usec / 1000000L;
		rms = (int)((tvp->tv_usec % 1000000L + 999L) / 1000L);
		if (rms >= 1000) {
			rsec++;
			rms -= 1000;
		}
	}

	/*
	 * One poll(2) per MSECMAX of the wait, until something is ready or the
	 * whole term has run.  A chunk that is not the last is exactly MSECMAX
	 * long, and no final chunk can reach that value (31 s + 999 ms is the
	 * largest), so the length of the chunk that expired says which it was.
	 */
	for (;;) {
		if (rsec < 0L)
			msec = -1;		/* block */
		else if (rsec >= (long)SECMAX)
			msec = MSECMAX;
		else
			msec = (int)rsec * 1000 + rms;

		/*
		 * Cleared before every call, not once: poll(2) writes revents
		 * only for the descriptors it has something to say about, so a
		 * report left over from an earlier chunk would be read back as
		 * this chunk's answer.
		 */
		for (pp = &pfd[0]; pp < &pfd[n]; pp++)
			pp->revents = 0;

		/*
		 * (unsigned long) is REQUIRED, not cosmetic: poll(2)'s second
		 * argument is an unsigned long in the COHERENT ABI (kernel
		 * upoll() declares it so, and the 3.2 i8086 syscall table
		 * budgets 2+4+2 = 8 argument bytes for it).  K&R has no
		 * prototype to widen `n' for us, so passing an int pushes two
		 * bytes where the kernel reads four -- it then takes msec's
		 * bytes as npoll's high half, sees a huge count, and fails
		 * EINVAL on every call.
		 */
		if ((r = poll(pfd, (unsigned long)n, msec)) < 0)
			return (-1);
		if (r > 0)
			break;			/* something is ready */
		if (msec < 0)
			continue;		/* only an event ends a block */
		if (msec < MSECMAX)
			break;			/* the last chunk expired */
		rsec -= (long)SECMAX;
		if (rsec == 0L && rms == 0)
			break;
	}

	if (rfds != (fd_set *)0)
		rfds->fds_bits = 0L;
	if (wfds != (fd_set *)0)
		wfds->fds_bits = 0L;
	if (efds != (fd_set *)0)
		efds->fds_bits = 0L;
	ready = 0;
	for (pp = &pfd[0]; pp < &pfd[n]; pp++) {
		register long m;
		register int hit;

		if (pp->revents & POLLNVAL) {
			errno = EBADF;
			return (-1);
		}
		m = 1L << pp->fd;
		hit = 0;
		if ((rbits & m) && (pp->revents & (POLLIN|POLLHUP|POLLERR))) {
			rfds->fds_bits |= m;
			hit++;
		}
		if ((wbits & m) && (pp->revents & (POLLOUT|POLLERR))) {
			wfds->fds_bits |= m;
			hit++;
		}
		if ((ebits & m) && (pp->revents & POLLPRI)) {
			efds->fds_bits |= m;
			hit++;
		}
		ready += hit;
	}
	return (ready);
}
