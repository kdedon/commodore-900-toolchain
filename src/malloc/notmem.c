/*
 * libc/stdlib/malloc/notmem.c
 * C general utilities library.
 * Memory allocation routines.
 * notmem()
 * Not ANSI by a long shot.
 * Test if pointer is in malloc arena.
 */

#include <stdio.h>
#include <sys/malloc.h>

/*
 * Return 1 if cp is not in the malloc arena,
 * 0 if cp is in the malloc arena, or
 * -1 if trouble is detected in the arena.
 * A block that has been freed is not in use, so this returns 1 for it.
 */
notmem(cp) char *cp;
{
	register unsigned len, counter;
	register MBLOCK *mp, *ap;

	if (cp == NULL
	   || (mp = __a_scanp) == NULL
	   || (len = ((ap = mblockp(cp))->blksize)) == 0
	   || isfree(len))
		return 1;			/* not a block in use */

	for (counter = __a_count; counter--; ) {
		if (mp == ap)
			return 0;		/* obviously good */
		len = mp->blksize;
		mp = (len) ? bumpp(mp, realsize(len)) : mp->uval.next;
	}
	if (mp != __a_scanp)
		return -1;			/* trouble in arena */
	return 1;				/* not found */
}

/* end of libc/gen/stdlib/notmem.c */
