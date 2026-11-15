/*
 * Given a pointer to an argv entry, parse the variants into
 * the array of characters.
 */
#ifdef	vax
#include	"INC$LIB:var.h"
#else
#include "var.h"
#endif


makvariant(p)
register char *p;
{
	register int i, j, n;
	unsigned int u;
	static char digit[] = "0123456789ABCDEF";

	for (n = VMAXIM/VGRANU; n > VMWRIT/VGRANU && variant[n-1] == 0; --n)
		;
	for (i = 0; i < n; i += 1) {
		for (j = 4; j >= 0; j -= 4) {
			u = (variant[i] >> j) & 0xF;
			*p++ = digit[u];
		}
	}
	*p = 0;
}
