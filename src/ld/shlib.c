/*
 * Copyright (c) 2026 Michal Pleban.
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * Client side of dynamic shared libraries; see <shlib.h>.
 *
 * A shared library acts like an archive, satisfying references outstanding
 * when it is read.  For each symbol it satisfies, ld builds a stub in shared
 * text and a 4-byte slot in private data that exec fills with a far pointer:
 *
 *	foo_:	ldl  rr2,_imp_foo_	54 02  8S 00  oo oo
 *		jp   (rr2)		1E 28
 *
 * The stub's address has 0x80|segment (SL form); the slot has bit 7 clear.
 * Stubs go at the end of L_SHRI and slots at the end of L_PRVD, so no module's
 * offsets move.  LI_LIB/LI_IMP records in L_SYM tell exec what to fill, so
 * `ld -s' cannot strip a client with imports.
 */

#include <shlib.h>

#define	SL_STUBLEN	8		/* ldl rr2,slot / jp (rr2)	*/
#define	SL_SLOTLEN	4		/* one far pointer		*/
#define	SL_MAXMAJOR	9		/* -lfoo probes libfoo.9 .. .0	*/
#define	SL_PATHLEN	1024

int	isbuiltin();			/* main.c: etext_/edata_/end_ */

typedef	struct	sldsl	{	/* one slot a DATA import is bound through */
	struct	sldsl	*next;
	uaddr_t		va;		/* its virtual address in L_PRVD */
} sldsl_t;

typedef	struct	slimp	{	/* one imported symbol */
	struct	slimp	*next;
	sym_t		*sym;		/* the client's reference to it */
	int		data;		/* SE_DATA: an object, not a function */
	uaddr_t		stub;		/* offset within the output L_SHRI */
	uaddr_t		slot;		/* offset within the output L_PRVD */
	uaddr_t		stubva;		/* ... and the same two as virtual */
	uaddr_t		slotva;		/* addresses, once bases are set */
	sldsl_t		*dsl, *dsltail;	/* data: the slots pass 2 found */
} slimp_t;

typedef	struct	sllib	{	/* one library, in command-line order */
	struct	sllib	*next;
	char		lname[NCPLN];	/* BASE file name, as exec looks it up */
	slimp_t		*imp, *imptail;
} sllib_t;

static	sllib_t	*slhead, *sltail;
static	int	slnimp;			/* imports over all libraries */
static	int	slnlib;			/* libraries that supplied one */
static	FILE	*slrelf;		/* L_REL, diverted (sldivert below) */
static	char	slrelnm[SL_PATHLEN];

static void	slfixslot();

char	*malloc(), *realloc(), *getenv();

/*
 * A short in target memory order: the library tables are memory images, not
 * canonical l.out fields.
 */
static unsigned int
slgw(fp)
FILE	*fp;
{
	register int	a, b;

	a = getc(fp);
	b = getc(fp);
	return (((a&0377)<<8) | (b&0377));
}

/*
 * Last path component: the client records the name exec searches for.
 */
static char *
slbase(p)
char	*p;
{
	register char	*s, *b = p;

	for (s = p; *s; s++)
		if (*s=='/' || *s=='\\')
			b = s+1;
	return (b);
}

/*
 * `ld -F': a fixed-address library's addresses are known at link time, so its
 * symbols are read as absolutes, as `-k' reads a kernel's.  No stubs or slots;
 * LF_SLREF alone tells exec the library must be resident.  Only outstanding
 * references are taken, as from an archive.
 */
int
slfixread(fp, offs, fname, mname, ldhp)
FILE	*fp;
fsize_t	offs;
char	*fname, mname[];
ldh_t	*ldhp;
{
	sym_t	*sp;
	lds_t	lds;
	unsigned int	i;
	int	got = 0;

	if (mname[0] != '\0')
		fatal("%s: module %.*s: a shared library cannot be linked out of an archive",
			fname, DIRSIZ, mname);
	if (machine == 0)
		fatal("%s: a shared library must follow the objects that reference it",
			fname);
	if (ldhp->l_machine != machine)
		fatal("%s: inconsistent machine", fname);
	/*
	 * A dynamic library bound as fixed would resolve every name to its
	 * link address: a silently wrong program.
	 */
	if (fseek(fp, offs+(fsize_t)ldhp->l_tbase, 0) == 0
	 && slgw(fp) == SL_MAGIC)
		fatal("%s: this is a dynamic shared library (export table magic 0x%x); link it without -F",
			fname, SL_MAGIC);

	if (fseek(fp, offs+(fsize_t)sizeof(ldh_t)+symoff(ldhp), 0) != 0)
		fatal("%s: cannot seek to the symbol table", fname);
	for (i = ldhp->l_ssize[L_SYM]/sizeof lds; i; i--) {
		if (fread((char *)&lds, sizeof lds, 1, fp) != 1)
			fatal("%s: bad symbol segment", fname);
		canshort(lds.ls_type);
		canlong(lds.ls_addr);
		if ((lds.ls_type&L_GLOBAL) == 0
		 || lds.ls_type == (L_GLOBAL|L_REF)
		 || (sp=symref(&lds)) == NULL)
			continue;
		sp->s.ls_type = L_GLOBAL|L_ABS;
		sp->s.ls_addr = vtop(lds.ls_addr);
		nundef--;
		got++;
		if (watch)
			modmsg(fname, mname, "fixed import %.*s at 0x%lx",
				NCPLN, lds.ls_id, (long)lds.ls_addr);
	}
	if (got != 0) {
		oldh.l_flag |= LF_SLREF;
		slfixslot(fname, ldhp);
	}
	return (got != 0);
}

/*
 * Set the LF_SLREF0 bit for the library's slot; exec attaches its private
 * half on that bit.  The slot is l_entry's segment less L_SLSEG0.
 */
static void
slfixslot(fname, ldhp)
char	*fname;
ldh_t	*ldhp;
{
	uaddr_t	entry;
	int	slot;

	entry = (uaddr_t)ldhp->l_entry;	/* canldh() leaves this one alone */
	canlong(entry);
	slot = (int)(entry >> 24) - L_SLSEG0;
	if (slot >= 0 && slot < NSLREF) {
		oldh.l_flag |= LF_SLREF0 << slot;
		if (watch)
			modmsg(fname, "", "fixed library slot %d", slot);
		return;
	}
	/*
	 * Outside the slot window there is no bit; a loader using the bits
	 * refuses such a library anyway.
	 */
	if (watch)
		filemsg(fname, "linked at segment 0x%x, outside the %d slots at 0x%x: no slot bit",
			(int)(entry >> 24), NSLREF, L_SLSEG0);
}

/*
 * Is `name' one of the `n' NCPLN-byte names in `tab'?
 */
static int
slisimp(tab, n, name)
char	*tab;
char	*name;
{
	register int	i, j;

	for (i = 0; i < n; i++) {
		for (j = 0; j < NCPLN; j++)
			if (tab[i*NCPLN+j] != name[j])
				break;
		if (j == NCPLN)
			return (1);
	}
	return (0);
}

/*
 * Take every referenced symbol from a library's export table.  Returns nonzero
 * if it satisfied anything.
 */
int
slread(fp, offs, fname, mname, ldhp)
FILE	*fp;
fsize_t	offs;
char	*fname, mname[];
ldh_t	*ldhp;
{
	sllib_t	*lp;
	slimp_t	*ip;
	sym_t	*sp;
	lds_t	lds;
	char	*bn;
	fsize_t	tb;
	unsigned int	magic, vers, nexp, expoff, eoff, eflg;
	unsigned int	i;
	char	*simp;			/* names the library imports itself */
	int	nsimp, j;
	int	got = 0, unexp = 0;

	/*
	 * A library importing from another is built with `ld -n -r -d -S'.  -S
	 * marks the -r output as final, so its stubs and slots stay put; an -r
	 * output linked again would move them.
	 */
	if (reloc && !slreloc)
		fatal("%s: cannot link a shared library into a relocatable link (-r) unless -S says the output is a library; format version %d binds imports for a final image only",
			fname, SL_VERSION);
	if (mname[0] != '\0')
		fatal("%s: module %.*s: a shared library cannot be linked out of an archive",
			fname, DIRSIZ, mname);
	if (machine == 0)
		fatal("%s: a shared library must follow the objects that reference it",
			fname);
	if (ldhp->l_machine != machine)
		fatal("%s: inconsistent machine", fname);
	bn = slbase(fname);
	if (strlen(bn) > NCPLN)
		fatal("%s: library name is longer than %d characters", bn, NCPLN);

	tb = offs + (fsize_t)ldhp->l_tbase;	/* shared segment, offset 0 */
	if (fseek(fp, tb, 0) != 0)
		fatal("%s: cannot seek to the shared segment", fname);
	magic = slgw(fp);
	vers = slgw(fp);
	nexp = slgw(fp);
	expoff = slgw(fp);
	if (magic != SL_MAGIC)
		fatal("%s: not a dynamic shared library: export table magic is 0x%x, expected 0x%x (a fixed-address library links with -F)",
			fname, magic, SL_MAGIC);
	if (vers != SL_VERSION)
		fatal("%s: export table version %d, this ld writes clients of version %d",
			fname, vers, SL_VERSION);
	if (expoff < SL_HDRLEN
	 || (fsize_t)expoff + (fsize_t)nexp*SL_EXPLEN > ldhp->l_ssize[L_SHRI])
		fatal("%s: export table of %d entries at offset %d does not fit the shared segment",
			fname, nexp, expoff);

	if ((lp=(sllib_t *)malloc(sizeof(sllib_t))) == NULL)
		fatal(nospace);
	lp->next = NULL;
	lp->imp = lp->imptail = NULL;
	for (i = 0; i < NCPLN; i++)
		lp->lname[i] = i < strlen(bn) ? bn[i] : '\0';

	for (i = 0; i < nexp; i++) {
		if (fseek(fp, tb+(fsize_t)expoff+(fsize_t)i*SL_EXPLEN, 0) != 0
		 || fread(lds.ls_id, NCPLN, 1, fp) != 1)
			fatal("%s: short export table", fname);
		eflg = slgw(fp);
		eoff = slgw(fp);
		/*
		 * Sanity check only; exec does the lookup.  Functions and
		 * SE_DATA|SE_SHRD offset into the shared image, plain data
		 * into the private image (PRVI+PRVD+BSSI+BSSD).
		 */
		if (eflg == SE_DATA
		    ? (fsize_t)eoff >= ldhp->l_ssize[L_PRVI]
				     + ldhp->l_ssize[L_PRVD]
				     + ldhp->l_ssize[L_BSSI]
				     + ldhp->l_ssize[L_BSSD]
		    : (fsize_t)eoff >= ldhp->l_ssize[L_SHRI]
				     + ((eflg & SE_SHRD) != 0
					? ldhp->l_ssize[L_SHRD] : 0))
			fatal("%s: export %.*s lies outside the %s image",
				fname, NCPLN, lds.ls_id,
				eflg == SE_DATA ? "private" : "shared");
		if ((sp=symref(&lds)) == NULL)
			continue;		/* not referenced: skip it */
		if ((ip=(slimp_t *)malloc(sizeof(slimp_t))) == NULL)
			fatal(nospace);
		ip->next = NULL;
		ip->sym = sp;
		ip->data = (eflg & SE_DATA) != 0;
		ip->stub = ip->slot = ip->stubva = ip->slotva = 0;
		ip->dsl = ip->dsltail = NULL;
		sp->sldata = ip->data;
		if (lp->imp == NULL)
			lp->imp = ip;
		else
			lp->imptail->next = ip;
		lp->imptail = ip;
		/*
		 * Absolute 0 until slalloc(), so no later archive claims it and
		 * a later definition is reported as a redefinition.
		 */
		sp->s.ls_type = L_GLOBAL|L_ABS;
		sp->s.ls_addr = 0;
		nundef--;
		slnimp++;
		got++;
		if (watch)
			modmsg(fname, mname, "import %.*s", NCPLN, lds.ls_id);
	}
	if (got != 0) {
		if (slhead == NULL)
			slhead = lp;
		else
			sltail->next = lp;
		sltail = lp;
		slnlib++;
		oldh.l_flag |= LF_SLREF;
	}
	/*
	 * Name each wanted symbol the library defines but does not export;
	 * "undefined" would blame the client.  Skip etext_/edata_/end_, which
	 * every link defines, and the library's own imports (LI_IMP), which a
	 * later library supplies.
	 */
	nsimp = 0;
	simp = NULL;
	if (fseek(fp, offs+(fsize_t)sizeof(ldh_t)+symoff(ldhp), 0) != 0)
		fatal("%s: cannot seek to the symbol table", fname);
	for (i = ldhp->l_ssize[L_SYM]/sizeof lds; i; i--) {
		if (fread((char *)&lds, sizeof lds, 1, fp) != 1)
			fatal("%s: bad symbol segment", fname);
		canshort(lds.ls_type);
		if (lds.ls_type != LI_IMP)
			continue;
		simp = simp == NULL
			? malloc((unsigned)NCPLN)
			: realloc(simp, (unsigned)(nsimp+1)*NCPLN);
		if (simp == NULL)
			fatal(nospace);
		for (j = 0; j < NCPLN; j++)
			simp[nsimp*NCPLN+j] = lds.ls_id[j];
		nsimp++;
	}
	if (fseek(fp, offs+(fsize_t)sizeof(ldh_t)+symoff(ldhp), 0) != 0)
		fatal("%s: cannot seek to the symbol table", fname);
	for (i = ldhp->l_ssize[L_SYM]/sizeof lds; i; i--) {
		if (fread((char *)&lds, sizeof lds, 1, fp) != 1)
			fatal("%s: bad symbol segment", fname);
		canshort(lds.ls_type);
		if ((lds.ls_type&L_GLOBAL) == 0
		 || lds.ls_type == (L_GLOBAL|L_REF)
		 || slisimp(simp, nsimp, lds.ls_id)
		 || (sp=symref(&lds)) == NULL
		 || isbuiltin(sp))
			continue;
		filemsg(fname, "%.*s: referenced, but the library does not export it",
			NCPLN, lds.ls_id);
		unexp++;
	}
	if (unexp != 0)
		fatal("%s: %d referenced symbol%s missing from the export table",
			fname, unexp, unexp==1 ? "" : "s");
	return (got != 0);
}

/*
 * For -S -r with imports, send L_REL to a scratch file.  L_SYM, just before
 * it, grows in pass 2 by one LI_IMP per DATA import cell, so L_REL's offset is
 * unknown until slrelout().
 */
void
sldivert()
{
	if (!reloc || !slreloc || slnimp == 0 || outputf[L_REL] == NULL)
		return;
	/*
	 * Beside the output: writable, and unique to this link.
	 */
	if (strlen(ofname) + 5 > sizeof(slrelnm))
		fatal("%s: name too long for a scratch relocation file", ofname);
	strcpy(slrelnm, ofname);
	strcat(slrelnm, ".rel");
	if ((slrelf = fopen(slrelnm, OWMODE)) == NULL)
		fatal("cannot create %s for the relocation stream", slrelnm);
	fclose(outputf[L_REL]);
	outputf[L_REL] = slrelf;
}

/*
 * Copy L_REL back once L_SYM's size is final.
 */
void
slrelout()
{
	FILE	*in, *out;
	int	c;

	if (slrelf == NULL)
		return;
	fclose(slrelf);
	outputf[L_REL] = slrelf = NULL;
	oseg[L_REL].daddr = oseg[L_SYM].daddr + oseg[L_SYM].size;
	if ((in = fopen(slrelnm, ORMODE)) == NULL
	 || (out = fopen(ofname, OUMODE)) == NULL)
		fatal("cannot rejoin the relocation stream");
	fseek(out, oseg[L_REL].daddr, 0);
	while ((c = getc(in)) != EOF)
		putc(c, out);
	fclose(in);
	fclose(out);
	unlink(slrelnm);
}

/*
 * Lay out stubs and slots, while the segments they extend are still sizes.
 */
void
slalloc()
{
	sllib_t	*lp;
	slimp_t	*ip;

	if (slnimp == 0)
		return;
	if (nosym)
		fatal("cannot strip (-s) a program with %d shared-library import%s: the LI_LIB and LI_IMP records in the symbol table are what exec binds them with",
			slnimp, slnimp==1 ? "" : "s");
	for (lp = slhead; lp != NULL; lp = lp->next) {
		oseg[L_SYM].size += sizeof(lds_t);	/* the LI_LIB record */
		for (ip = lp->imp; ip != NULL; ip = ip->next) {
			/*
			 * A DATA import's slots are the far pointers -VPIC
			 * code already has in private data; pass 2 reports
			 * each to sldslot().  The symbol's absolute 0 zeroes
			 * them.
			 */
			if (ip->data)
				continue;
			ip->stub = oseg[L_SHRI].size;
			oseg[L_SHRI].size += SL_STUBLEN;
			ip->slot = oseg[L_PRVD].size;
			oseg[L_PRVD].size += SL_SLOTLEN;
			ip->sym->s.ls_type = L_GLOBAL|L_SHRI;
			ip->sym->s.ls_addr = ip->stub;
			oseg[L_SYM].size += sizeof(lds_t);  /* its LI_IMP */
			if (reloc)		/* slemit()'s own record */
				oseg[L_REL].size += 1 + 4;
		}
	}
}

/*
 * Offsets to virtual addresses, before pass 2 advances oseg[].vbase.
 */
void
slbind()
{
	sllib_t	*lp;
	slimp_t	*ip;

	for (lp = slhead; lp != NULL; lp = lp->next)
		for (ip = lp->imp; ip != NULL; ip = ip->next) {
			if (ip->data)
				continue;
			ip->stubva = ptov(oseg[L_SHRI].vbase + ip->stub);
			ip->slotva = ptov(oseg[L_PRVD].vbase + ip->slot);
		}
}

/*
 * Write the LI_LIB and LI_IMP records.
 */
void
slsyms()
{
	sllib_t	*lp;
	slimp_t	*ip;
	sldsl_t	*dp;
	lds_t	lds;
	int	i;

	for (lp = slhead; lp != NULL; lp = lp->next) {
		for (i = 0; i < NCPLN; i++)
			lds.ls_id[i] = lp->lname[i];
		lds.ls_type = LI_LIB;
		lds.ls_addr = 0;
		canshort(lds.ls_type);
		canlong(lds.ls_addr);
		putstruc(&lds, sizeof lds, outputf[L_SYM], &oseg[L_SYM]);
		for (ip = lp->imp; ip != NULL; ip = ip->next) {
			for (i = 0; i < NCPLN; i++)
				lds.ls_id[i] = ip->sym->s.ls_id[i];
			lds.ls_type = LI_IMP;
			if (!ip->data) {
				lds.ls_addr = ip->slotva;
				canshort(lds.ls_type);
				canlong(lds.ls_addr);
				putstruc(&lds, sizeof lds, outputf[L_SYM],
					&oseg[L_SYM]);
				continue;
			}
			/*
			 * One record per cell (one per object file); exec
			 * fills each with the same far pointer.
			 */
			for (dp = ip->dsl; dp != NULL; dp = dp->next) {
				lds.ls_type = LI_IMP;
				lds.ls_addr = dp->va;
				canshort(lds.ls_type);
				canlong(lds.ls_addr);
				putstruc(&lds, sizeof lds, outputf[L_SYM],
					&oseg[L_SYM]);
			}
		}
	}
}

/*
 * Write the stubs and slots, after every module's own bytes.
 */
void
slemit()
{
	sllib_t	*lp;
	slimp_t	*ip;
	unsigned int	seg, off;
	int	i;

	if (slnimp == 0)
		return;
	for (lp = slhead; lp != NULL; lp = lp->next)
		for (ip = lp->imp; ip != NULL; ip = ip->next) {
			if (ip->data)
				continue;
			seg = (unsigned int)((ip->slotva>>24) & 0x7F);
			off = (unsigned int)(ip->slotva & 0xFFFFL);
			/*
			 * In a library the loader moves the private segment,
			 * so the stub's operand (2 bytes in) needs its own
			 * relocation record.  Stubs come last, so L_REL stays
			 * sorted.
			 */
			if (reloc && outputf[L_REL] != NULL) {
				putbyte(L_PRVD|LR_LONG, outputf[L_REL],
					&oseg[L_REL]);
				putaddr(oseg[L_SHRI].vbase + 2,
					outputf[L_REL], &oseg[L_REL]);
			}
			putbyte(0x54, outputf[L_SHRI], &oseg[L_SHRI]);
			putbyte(0x02, outputf[L_SHRI], &oseg[L_SHRI]);
			putbyte(0x80|seg, outputf[L_SHRI], &oseg[L_SHRI]);
			putbyte(0x00, outputf[L_SHRI], &oseg[L_SHRI]);
			putbyte(off>>8, outputf[L_SHRI], &oseg[L_SHRI]);
			putbyte(off&0xFF, outputf[L_SHRI], &oseg[L_SHRI]);
			putbyte(0x1E, outputf[L_SHRI], &oseg[L_SHRI]);
			putbyte(0x28, outputf[L_SHRI], &oseg[L_SHRI]);
		}
	for (lp = slhead; lp != NULL; lp = lp->next)
		for (ip = lp->imp; ip != NULL; ip = ip->next)
			if (!ip->data)
				for (i = 0; i < SL_SLOTLEN; i++)
					putbyte(0, outputf[L_PRVD],
						&oseg[L_PRVD]);
}

/*
 * Record the far pointer at `va' as a slot for DATA import `sp', and count
 * its LI_IMP while L_SYM can still grow.
 */
void
sldslot(sp, va)
sym_t	*sp;
uaddr_t	va;
{
	sllib_t	*lp;
	slimp_t	*ip;
	sldsl_t	*dp;

	for (lp = slhead; lp != NULL; lp = lp->next) {
		for (ip = lp->imp; ip != NULL; ip = ip->next) {
			if (ip->sym != sp)
				continue;
			if ((dp=(sldsl_t *)malloc(sizeof(sldsl_t))) == NULL)
				fatal(nospace);
			dp->next = NULL;
			dp->va = va;
			if (ip->dsl == NULL)
				ip->dsl = dp;
			else
				ip->dsltail->next = dp;
			ip->dsltail = dp;
			oseg[L_SYM].size += sizeof(lds_t);
			return;
		}
	}
	fatal("%.*s: no import record for a data slot", NCPLN, sp->s.ls_id);
}

/*
 * -lNAME searches LIBPATH, /lib, /usr/lib, as exec does, preferring a shared
 * library to the archive.  A NAME with a `.' pins a major: `-ltoy.1'.
 */
static int
sltry(dir, file)
char	*dir, *file;
{
	char	*path;
	FILE	*fp;

	if ((path=malloc(strlen(dir)+strlen(file)+2)) == NULL)
		fatal(nospace);
	sprintf(path, "%s/%s", dir, file);
	if ((fp=fopen(path, ORMODE)) == NULL) {
		free(path);
		return (0);
	}
	fclose(fp);
	if (watch)
		filemsg(path, "library");
	return (rdfile(path));		/* not freed: modules keep it */
}

static int
sldir(dir, name)
char	*dir, *name;
{
	char	file[SL_PATHLEN];
	int	m;

	if (strlen(name)+8 > sizeof file)
		fatal("library name lib%s is too long", name);
	if (strchr(name, '.') != NULL) {
		sprintf(file, "lib%s", name);
		return (sltry(dir, file));
	}
	for (m = SL_MAXMAJOR; m >= 0; m--) {	/* newest major first */
		sprintf(file, "lib%s.%d", name, m);
		if (sltry(dir, file))
			return (1);
	}
	sprintf(file, "lib%s.a", name);
	return (sltry(dir, file));
}

void
slsearch(name)
char	*name;
{
	char	*env, *p, *q;
	int	found = 0;

	if ((env=getenv("LIBPATH")) != NULL) {
		if ((env=malloc(strlen(env)+1)) == NULL)
			fatal(nospace);
		strcpy(env, getenv("LIBPATH"));
		for (p = env; !found && p != NULL; p = q) {
			if ((q=strchr(p, ':')) != NULL)
				*q++ = '\0';
			if (*p != '\0')
				found = sldir(p, name);
		}
		free(env);
	}
	if (!found)
		found = sldir("/lib", name);
	if (!found)
		found = sldir("/usr/lib", name);
	if (!found)
		fatal("can't find library lib%s along LIBPATH:/lib:/usr/lib",
			name);
}
