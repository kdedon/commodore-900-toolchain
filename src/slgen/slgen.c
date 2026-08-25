/*
 * Copyright (c) 1977-1995 Robert Swartz.
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * A generator for shared libraries.
 * It is run as two passes.
 * Pass1:
 * 	A list of objects is scanned for entry
 *	points and a jump table object is produced.
 * The jump table and all these objects are loaded
 * into one object.
 * Pass2:
 *	Fixup is done on this one shared library
 *	object (on the jump table).
 */

#include <stdio.h>
#include <n.out.h>
#include <canon.h>


static	char	dflag;			/* Tell about data entry points */
static	char	pflag;			/* Print objects with private */
static	char	vflag;			/* Verbose */
static	char	*jmpf;			/* Jump table file */
static	FILE	*jmpfp;			/* Jump table file pointer */
static	FILE	*symfp;			/* Symbol table file pointer */
static	struct	ldheader oldh;		/* Jump table l.out header */
static	struct	ldheader ildh;		/* Object file l.out header */
static	int	ncentry;		/* Number of code entries */
static	int	ndentry;		/* Number of data entries */
static	int	ncommon;		/* Number of common entries */
static	int	nsymref;		/* Symbol reference */
static	int	nabs;			/* Number of absolute entries */
static	int	npobj;			/* Number of private objects */
static	int	machtype;		/* Machine type */

static	int	(*pass)();		/* Pass-specific code pointer */
int	pass1();
int	pass2();

/*
 * The jump instruction is created into this
 * union by a machine-dependent routine.
 */
union	ins {
	char	c[32];
	short	s[16];
	long	l[8];
}	ins;

static	char	werr[] = "write error on jump table file `%s'";
static	char	jmperr[] = "write error on jump table file `%s', symbol %.*s";
static	char	lfmt[] = "bad l.out format in `%s'";
static	char	badmch[] = "module `%s' of machine type `%s` discarded";
static	char	badseg[] = "unexpected segment type %d in object `%s'";
static	char	notset[] = "machine type not yet set";
static	char	support[] = "machine type %d, not supported";
static	char	noreloc[] = "no relocation bits in `%s'";
static	char	symread[] = "read error on symbol table in `%s'";
static	char	jovfl[] = "jump table overflow at symbol %.*s (pass 1 sized it for %d entries)";

char	*mtype();
long	symoff();
long	jumpbase();

/*
 * The linker defines these at the end of the segments of whatever
 * program it is linking (ld main.c endbind).  They describe THAT link
 * and no other, so a shared library must not export them: a client
 * resolving `end_' from the library would take the library's break for
 * its own.  Pass 2 drops them from the exported symbol table.
 */
static	char	*perprog[] = {
	"etext_",
	"edata_",
	"end_",
	NULL
};

main(argc, argv)
int argc;
char *argv[];
{
	register char *ap;
	register int es = 0;
	register int i;

	while (argc>1 && *argv[1]=='-') {
		for (ap = &argv[1][1]; *ap!='\0'; ap++)
			switch (*ap) {
			case '1':
				pass = pass1;
				break;

			case '2':
				pass = pass2;
				break;

			case 'd':
				dflag++;
				break;

			case 'p':
				pflag++;
				break;
	
			case 'v':
				vflag++;
				break;
	
			default:
				usage();
			}
		argv++;
		argc--;
	}
	if (pass == NULL) {
		slmsg("must specify `-1' or `-2' pass option");
		usage();
	}
	if (argc < 2)
		usage();
	argc--;
	argv++;
	es = (*pass)(argc, argv);
	exit(es);
}

/*
 * Build the library jump table object in
 * this pass.
 */
pass1(ac, av)
register int ac;
register char *av[];
{
	register int i;
	register int es;

	if (s1init(av[0]))
		return (1);
	if (ac < 2)
		usage();
	es = 0;
	for (i=1; i<ac; i++)
		es |= s1add(av[i]);
	es |= s1term();
	report();
	return (es);
}

/*
 * Pass 2 -- write the actual addresses into
 * the jump table of the linked object. This
 * assumption is that the jump table is
 * first in L_SHRI segment.
 */
pass2(ac, av)
register int ac;
register char *av[];
{
	if (ac != 1)
		usage();
	if (s2init(av[0]))
		return (1);
	if (s2fudge() || s2term())
		return (1);
	report();
	return (0);
}

/*
 * Initialise the jump table file.
 * This is an l.out containing
 * the header for the shared library.
 */
s1init(fn)
char *fn;
{
	jmpf = fn;
	if ((jmpfp = fopen(jmpf, "w")) == NULL) {
		slmsg("cannot open jump table file `%s'", jmpf);
		return (1);
	}
	oldh.l_magic = L_MAGIC;
	oldh.l_flag = LF_32;
	oldh.l_tbase = sizeof(oldh);
	return (0);
}

/*
 * Add an object to the list in
 * the jump table.
 */
s1add(fn)
char *fn;
{
	register FILE *lfp;
	register long ss;
	static struct ldsym lds;

	if ((lfp = fopen(fn, "r")) == NULL) {
		slmsg("cannot open object file `%s'", fn);
		return (1);
	}
	if (fread((char*)&ildh, sizeof ildh, 1, lfp) != 1) {
		slmsg(lfmt, fn);
		fclose(lfp);
		return (1);
	}
	canldh(&ildh);
	if (ildh.l_magic!=L_MAGIC || (ildh.l_flag&LF_32)==0) {
		slmsg(lfmt, fn);
		fclose(lfp);
		return (1);
	}
	if (oldh.l_machine == 0) {
		oldh.l_machine = ildh.l_machine;
		machtype = ildh.l_machine;
	}
	if (ildh.l_machine != oldh.l_machine) {
		slmsg(badmch, fn, mtype(ildh.l_machine));
		fclose(lfp);
		return (0);
	}
	if ((ildh.l_flag&LF_NRB) != 0) {
		slmsg(noreloc, fn);
		fclose(lfp);
		return (1);
	}
	if (ildh.l_ssize[L_PRVD] != 0
	 || ildh.l_ssize[L_BSSD] != 0
	 || ildh.l_ssize[L_PRVI] != 0) {
		if (pflag) {
			if (npobj == 0)
				printf("Objects with private text:\n");
			printf("%s\n", fn);
		}
		npobj++;
	}
	fseek(lfp, symoff(&ildh), 0);
	for (ss = ildh.l_ssize[L_SYM]; ss > 0; ss -= sizeof lds) {
		if (fread((char*)&lds, sizeof lds, 1, lfp) != 1) {
			slmsg(symread, fn);
			fclose(lfp);
			return (1);
		}
		cansym(&lds);
		if ((lds.ls_type & L_GLOBAL) == 0)
			continue;
		switch (lds.ls_type & ~L_GLOBAL) {
		case L_REF:
			if (lds.ls_addr != 0)
				ncommon++; else
				nsymref++;
			break;

		case L_ABS:
			nabs++;
			break;

		case L_SHRI:
		case L_PRVI:
		case L_BSSI:
			ncentry++;
			break;

		case L_SHRD:
		case L_PRVD:
		case L_BSSD:
			if (dflag) {
				if (ndentry == 0)
					printf("Data entry points:\n");
				printf("%14s  %.*s", fn, NCPLN, lds.ls_id);
				if ((lds.ls_type & ~L_GLOBAL) == L_SHRD)
					printf(" (shared)\n"); else
					printf("\n");
			}
			ndentry++;
			break;

		default:
			slmsg(badseg, lds.ls_type, fn);
		}
	}
	fclose(lfp);
	return (0);
}

/*
 * Write the jump table
 */
s1term()
{
	register unsigned short i;
	register short l;

	if ((l = jumpsize(0L)) == 0)
		return (1);
	l *= ncentry;
	i = l + sizeof(short);
	oldh.l_ssize[L_SHRI] = i;
	canldh(&oldh);
	if (fwrite((char*)&oldh, sizeof oldh, 1, jmpfp) != 1) {
		slmsg(werr, jmpf);
		fclose(jmpfp);
		return (1);
	}
	fputc(i>>8, jmpfp);
	fputc(i, jmpfp);
	for (i=0; i<l; i++)
		fputc(0, jmpfp);
	fflush(jmpfp);
	if (ferror(jmpfp)) {
		slmsg(werr, jmpf);
		fclose(jmpfp);
		return (1);
	}
	fclose(jmpfp);
	return (0);
}

/*
 * Size of an entry in the jump table.
 * This routine is dependent upon the
 * possible machine types.
 * The value returned is the number of bytes
 * in a jump instruction; it is the same for
 * every entry, since pass 1 sizes the table
 * before any address is known.
 * Also, writes the jump instruction into the
 * `union ins' which can be written out by the
 * caller.
 * This data must be stored to be in the
 * correct byte order for the target machine.
 */
jumpsize(addr)
long addr;
{
	register int i;

	for (i=0; i<sizeof ins.c; i++)
		ins.c[i] = 0;
	switch (machtype) {
	case 0:
		slmsg(notset);
		return (0);

	case M_Z8001:
		ins.c[0] = 0x5E;		/* jp un, DA */
		ins.c[1] = 0x08;
		ins.c[2] = 0x80 | ((addr>>24) & 0x7F);	/* long DA: seg */
		ins.c[3] = 0x00;
		ins.c[4] = addr>>8;			/* offset */
		ins.c[5] = addr;
		return (6);

	case M_Z8002:
		ins.s[0] = 0x5E08;		/* jp un, DA */
		ins.s[1] = addr;
		return (4);

	case M_8086:		/* Large model */
		/* To do */
		return (6);

	case M_PDP11:
		ins.s[0] = 0167;		/* jmp *$DA */
		ins.s[1] = addr;
		return (4);

	default:
		slmsg(support, machtype);
		return (0);
	}
	/* NOTREACHED */
}

/*
 * Return the base of the jump table.
 * The value is machine-dependent.
 */
long
jumpbase()
{
	switch (machtype) {
	case 0:
		slmsg(notset);
		return (0L);

	case M_Z8001:
		return (0x01000000L);		/* Base of SHRI */

	case M_PDP11:
		return (0L);

	default:
		slmsg(support, machtype);
		return (0L);
	}
	/* NOTREACHED */
}

/*
 * Open the shared library (file name is in `jmpf')
 * one for reading, one for writing.
 */
s2init(fn)
char *fn;
{
	jmpf = fn;
	if ((jmpfp = fopen(jmpf, "r+w")) == NULL
	 || (symfp = fopen(jmpf, "r+w")) == NULL) {
		slmsg("cannot open shared library file  `%s'", jmpf);
		return (1);
	}
	return (0);
}

/*
 * Fixup the jump entries into
 * the output file.
 */
s2fudge()
{
	static struct ldsym lds;
	unsigned char c1, c2;
	register int s;
	register long ss;
	register long jaddr;
	long jfoff;
	long soff;
	short int jsize;
	int jroom;

	if (fread((char*)&ildh, sizeof ildh, 1, jmpfp) != 1) {
		slmsg(lfmt, jmpf);
		return (1);
	}
	canldh(&ildh);
	if (ildh.l_magic!=L_MAGIC || (ildh.l_flag&LF_32)==0) {
		slmsg(lfmt, jmpf);
		return (1);
	}
	if (ildh.l_flag & LF_SLIB) {
		slmsg("don't re-run pass 2 on `%s'", jmpf);
		return (1);
	}
	machtype = ildh.l_machine;
	if (ildh.l_ssize[L_PRVD] != 0
	 || ildh.l_ssize[L_BSSD] != 0
	 || ildh.l_ssize[L_PRVI] != 0) {
		if (pflag)
			printf("Library `%s' has private text\n", jmpf);
		npobj++;
	}
	ildh.l_flag |= LF_SLIB;
	c1 = fgetc(jmpfp);
	c2 = fgetc(jmpfp);
	jsize = (c1<<8) + c2;
	/*
	 * The jump table is first in the L_SHRI segment, which is first
	 * on disk at `l_tbase'; its own size word occupies the first
	 * two bytes.  Entries are written at an explicit file offset --
	 * `jmpfp' has just been read from, and a read followed by a
	 * write with no intervening seek is not defined for an update
	 * stream.
	 */
	jfoff = (long)ildh.l_tbase + sizeof(jsize);
	jaddr = jumpbase() + sizeof(jsize);
	jsize -= sizeof(jsize);
	jroom = jsize;
	soff = symoff(&ildh);
	for (ss = ildh.l_ssize[L_SYM]; ss > 0; ss -= sizeof lds, soff += sizeof lds) {
		fseek(symfp, soff, 0);
		if (fread((char*)&lds, sizeof lds, 1, symfp) != 1) {
			slmsg(symread, jmpf);
			return (1);
		}
		cansym(&lds);
		if ((lds.ls_type & L_GLOBAL) == 0)
			continue;
		if (isperprog(lds.ls_id)) {
			lds.ls_type &= ~L_GLOBAL;
			cansym(&lds);
			fseek(symfp, soff, 0);
			if (fwrite((char *)&lds, sizeof lds, 1, symfp) != 1) {
				slmsg(jmperr, jmpf, NCPLN, lds.ls_id);
				return (1);
			}
			continue;
		}
		switch (lds.ls_type & ~L_GLOBAL) {
		case L_REF:
			if (lds.ls_addr != 0)
				ncommon++; else
				nsymref++;
			break;

		case L_ABS:
			nabs++;
			break;

		case L_SHRI:
		case L_PRVI:
		case L_BSSI:
			ncentry++;
			s = jumpsize(lds.ls_addr);
			if ((jsize -= s) < 0) {
				slmsg(jovfl, NCPLN, lds.ls_id, jroom/s);
				return (1);
			}
			fseek(jmpfp, jfoff, 0);
			if (fwrite((char *)&ins, s, 1, jmpfp) != 1) {
				slmsg(jmperr, jmpf, NCPLN, lds.ls_id);
				return (1);
			}
			jfoff += s;
			lds.ls_type = L_SHRI|L_GLOBAL;
			lds.ls_addr = jaddr;
			cansym(&lds);
			fseek(symfp, soff, 0);
			if (fwrite((char *)&lds, sizeof lds, 1, symfp) != 1) {
				slmsg(jmperr, jmpf, NCPLN, lds.ls_id);
				return (1);
			}
			jaddr += s;
			break;

		case L_SHRD:
		case L_PRVD:
		case L_BSSD:
			if (dflag) {
				if (ndentry == 0)
					printf("Data entry points:\n");
				printf("%14s  %.*s", jmpf, NCPLN, lds.ls_id);
				if ((lds.ls_type & ~L_GLOBAL) == L_SHRD)
					printf(" (shared)\n"); else
					printf("\n");
			}
			ndentry++;
			break;

		default:
			slmsg(badseg, lds.ls_type, jmpf);
			break;
		}
	}
	if (jsize != 0)
		slmsg("warning: jump table sizes disagree between passes");
	canldh(&ildh);
	fseek(jmpfp, 0L, 0);
	if (fwrite((char*)&ildh, sizeof ildh, 1, jmpfp) != 1) {
		slmsg(werr, jmpf);
		return (1);
	}
	return (0);
}

/*
 * Close output file and
 * check for write errors.
 */
s2term()
{
	fflush(jmpfp);
	if (ferror(jmpfp)) {
		slmsg(werr, jmpf);
		fclose(jmpfp);
		return (1);
	}
	fclose(jmpfp);
	fclose(symfp);
	return (0);
}

/*
 * True if the symbol is one the linker generates for the program it is
 * linking, and which a shared library therefore must not export.
 */
isperprog(id)
char id[];
{
	register char **pp;
	register char *s;
	register int i;

	for (pp = &perprog[0]; *pp != NULL; pp++) {
		s = *pp;
		for (i=0; i<NCPLN; i++) {
			if (id[i] != *s)
				break;
			if (*s == '\0')
				return (1);
			s++;
		}
		if (i >= NCPLN)
			return (1);
	}
	return (0);
}

/*
 * Canonicalise the l.out (n.out)
 * header (can be used on input or output)
 */
canldh(ldhp)
register struct ldheader *ldhp;
{
	register int i;

	canshort(ldhp->l_magic);
	canshort(ldhp->l_flag);
	canshort(ldhp->l_machine);
	canshort(ldhp->l_tbase);
	for (i=0; i<NLSEG; i++)
		canlong(ldhp->l_ssize[i]);
	canlong(ldhp->l_entry);
}

/*
 * Canonicalise a symbol table
 * entry.
 */
cansym(ldsp)
register struct ldsym *ldsp;
{
	canshort(ldsp->ls_type);
	canlong(ldsp->ls_addr);
}

/*
 * Offset into the file for a the symbol
 * table.
 */
long
symoff(ldhp)
register struct ldheader *ldhp;
{
	register long base;
	register int i;

	base = ldhp->l_tbase;
	for (i=0; i<L_SYM; i++)
		if (i!=L_BSSI && i!=L_BSSD)
			base += ldhp->l_ssize[i];
	return (base);
}

/*
 * Name of a machine type, for the discard message.
 */
char *
mtype(m)
register int m;
{
	static char *mchname[] = {
		"Turing Machine",
		"PDP-11",
		"VAX-11",
		"3sickly",
		"Z8001",
		"Z8002",
		"iAPX 86",
		"i8080",
		"6800",
		"6809",
		"68000",
		"NS16000"
	};

	if (m < 0 || m >= sizeof(mchname)/sizeof(mchname[0]))
		return ("unknown");
	return (mchname[m]);
}

/*
 * produce a report of the types of symbols
 * found in the library.
 */
report()
{
	if (!vflag)
		return;
	printf("Number of code entries: %3d\n", ncentry);
	printf("Number of data entries: %3d\n", ndentry);
	printf("Number of absolutes:    %3d\n", nabs);
	printf("Number of common refs:  %3d\n", ncommon);
	printf("Number of symbol refs:  %3d\n", nsymref);
	printf("Number of objects with private text: %3d\n", npobj);
}

/* VARARGS 1 */
slmsg(x)
{
	fprintf(stderr, "slgen: %r\n", &x);
}


usage()
{
	fprintf(stderr, "Usage:	slgen -1 [-dpv] jmpfile obj ... \n");
	fprintf(stderr, "       slgen -2 slibrary\n");
	exit(1);
}
