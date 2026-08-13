/*
 * Usleep -- suspend execution for an interval given in microseconds.
 *
 * Built on alarm2(), which counts clock TICKS, so the real resolution is one
 * tick: HZ is 100, hence 10 ms.  A request shorter than that still waits one
 * tick rather than returning immediately, because callers use usleep() to yield
 * -- a busy return would spin the machine.  Requests are rounded UP for the same
 * reason: a delay loop that rounds down converges on no delay at all.
 *
 * Unlike sleep(), this does NOT try to compose with an alarm the caller already
 * had pending: it saves and restores the previous SIGALRM disposition and any
 * remaining alarm, but a caller whose alarm was due DURING the usleep gets it on
 * restore rather than on time.  That is the honest cost of one timer, and it is
 * what the games this exists for need (snake's delay(), robots, worms).
 */

#include "signal.h"

extern long alarm2();

static int woke;

static
catch(n)
int n;
{
	++woke;
}

usleep(usec)
unsigned long usec;
{
	long ticks, left;
	int (*ofunc)();

	/* HZ = 100, so a tick is 10000 microseconds.  Round up, floor at 1. */
	ticks = (long)((usec + 9999L) / 10000L);
	if (ticks <= 0)
		ticks = 1;

	woke = 0;
	ofunc = signal(SIGALRM, catch);
	left = alarm2(ticks);
	do
		pause();
	while (woke == 0);
	signal(SIGALRM, ofunc);
	if (left > 0)
		(void)alarm2(left);
	return (0);
}
