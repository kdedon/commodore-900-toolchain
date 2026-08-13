/*
 * ulimit - the C900 COHERENT 3.2 kernel has no ulimit(2) system call.
 * Return -1 ("unknown"): callers (e.g. malloc's arena-growth early-fail
 * check) treat -1 as "no limit info" and fall back to the sbrk() result.
 */
long
ulimit(cmd, newlimit)
long	newlimit;
{
	return (-1L);
}
