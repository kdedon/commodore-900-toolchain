/*
 * z8kdump -- dump this decoder's answer for every first word, under whatever
 * contexts are fed to it.  It exists for the gate that compares this C decoder
 * against the one the table was generated from: a mis-derived field then shows
 * up as a differing line rather than as a wrong answer nobody looks at.
 *
 *	z8kdump < CONTEXTS
 *
 * A context is one line `NW W1 W2 W3 PC', all hex: NW is how many instruction
 * words are available, W1..W3 the words following the first, PC the byte
 * address.  For each context every first word 0000..FFFF is printed as
 * `W0 <tab> WORDS <tab> MNEMONIC <tab> OPERANDS'.
 */
#include <stdio.h>

#include "z8kdis.h"

int
main(argc, argv)
int argc;
char **argv;
{
	unsigned long w[4], pc;
	char ops[ZOPSMAX], *mnem;
	int nw, wc;
	long i;

	while (scanf("%d %lx %lx %lx %lx", &nw, &w[1], &w[2], &w[3], &pc) == 5) {
		for (i = 0; i <= 0xFFFFL; i++) {
			w[0] = (unsigned long)i;
			wc = z8kdis(w, nw, pc, &mnem, ops);
			printf("%04lX\t%d\t%s\t%s\n", (unsigned long)i, wc, mnem, ops);
		}
	}
	return 0;
}
