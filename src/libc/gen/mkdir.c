/*
 * mkdir.c
 * C library.
 * mkdir() and rmdir() -- over /bin/mkdir and /bin/rmdir.
 *
 * This kernel has no mkdir(2) or rmdir(2): its system-call table ends at 73 and
 * is full (sys/z8001/src/tab.c).  A directory is made the V7 way, with
 * mknod(IFDIR) and two link()s for `.' and `..', and mknod for anything but a
 * FIFO is root only (sys2.c umknod) -- so a library routine cannot do the work
 * itself for an ordinary caller.  It runs the command instead, which is what
 * carries whatever privilege the system gives the operation.
 *
 * The mode argument is accepted and ignored: mkdir(1) creates with 0777 and
 * leaves the umask to apply, and there is no way to pass a mode through it.
 * A caller that needs an exact mode has to chmod() afterwards.
 */

#include <stdio.h>
#include <errno.h>
#include <signal.h>

static int spawn();

int mkdir(path, mode) char *path; int mode;
{
	return spawn("/bin/mkdir", path);
}

int rmdir(path) char *path;
{
	return spawn("/bin/rmdir", path);
}

/*
 * Run `cmd path' and report whether it succeeded.  Returns 0 on an exit status
 * of zero, else -1 -- and since the command has already printed its own
 * diagnostic, errno is only a summary: EACCES when it refused, EIO when it did
 * not run at all.
 */
static int spawn(cmd, path) char *cmd, *path;
{
	int pid, w, status;

	if ((pid = fork()) == 0) {
		execl(cmd, cmd, path, (char *)0);
		_exit(127);
	}
	if (pid < 0)
		return (-1);
	/*
	 * Wait for THIS child.  A caller may have others outstanding, and
	 * swallowing one of those would lose its status for good.
	 */
	while ((w = wait(&status)) != pid) {
		if (w < 0)
			return (-1);
	}
	if ((status & 0xFF) != 0 || (status >> 8) == 127) {
		errno = ((status >> 8) == 127) ? EIO : EACCES;
		return (-1);
	}
	return ((status >> 8) == 0 ? 0 : (errno = EACCES, -1));
}
