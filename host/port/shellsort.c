/*
 * shellsort.c - host-provided Coherent libc routine. cc1 (n1/cc1.c) calls
 * shellsort() to order switch cases; it lives in the target's libc
 * (libc/gen/shellsort.c), which the modern host lacks. This is the donor source
 * verbatim except the element-size parameter, which the donor declared
 * `register char n` (the exchange byte count) -- fine for the tiny CASES struct
 * on the 16-bit target but a latent truncation if a struct ever exceeds 255
 * bytes. Widened to size_t here; behaviour is identical for the sizes cc1 uses.
 * Calling sequence matches qsort(base, nel, width, compar).
 *
 * K&R-style definitions: this file is compiled BOTH by the host cc (gcc
 * -std=gnu89) for the bootstrap cc1 AND by the MWC compiler itself for the
 * self-hosted cc1, and the MWC compiler is K&R-only (no ANSI prototype defs).
 */
#include <stddef.h>

#define A(v,i)  ((v)+((i)*size))

static void
qexch(p1, p2, n)
char *p1;
char *p2;
size_t n;
{
	int t;

	while (n--) {
		t = *p1;
		*p1++ = *p2;
		*p2++ = t;
	}
}

void
shellsort(v, n, size, compar)
char *v;
int n;
size_t size;
int (*compar)();
{
	int gap, i, j;

	for (gap = n/2; gap > 0; gap /= 2)
		for (i = gap; i < n; i++)
			for (j = i-gap; j >= 0; j -= gap) {
				if ((*compar)(A(v,j), A(v,j+gap)) <= 0)
					break;
				qexch(A(v,j), A(v,j+gap), size);
			}
}

/* end of shellsort.c (host-provided libc) */
