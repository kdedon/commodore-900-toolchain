/*
 * Copyright (c) 2026 Michal Pleban.
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * The client half of the dynamic shared-library format; see <shlib.h>.
 *
 * A shared library on the command line behaves like an archive: it comes after
 * the objects and satisfies references still outstanding when it is read.
 * Nothing of the library is loaded.  For each symbol it satisfies ld builds
 *
 *	a STUB in the client's shared text, named for the symbol, so the call
 *	sites the compiler already emitted keep working:
 *
 *		foo_:	ldl  rr2,_imp_foo_	54 02  8S 00  oo oo
 *			jp   (rr2)		1E 28
 *
 *	a 4-byte SLOT in the client's private data, zero in the file, which the
 *	kernel fills at exec with a far pointer to the library's own entry.
 *
 * The stub's address field is the SL (instruction long-address) form, so it
 * carries 0x80|segment; the slot it names holds the register/memory form, with
 * bit 7 of the segment byte clear.
 *
 * What the kernel needs to fill the slots goes into L_SYM as LI_LIB / LI_IMP
 * records, and LF_SLREF says they are there; `ld -s' therefore cannot strip a
 * client that has imports.
 *
 * Stubs and slots are appended after every input module's contribution to their
 * segment -- stubs at the end of L_SHRI, slots at the end of L_PRVD -- so no
 * module's symbol offsets or relocation biases move.  A slot's address thus
 * depends on how much private data the client itself has.
 */

/* Modes ORMODE and the l.out types come from data.h, which all.c includes. */
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

char	*malloc(), *realloc(), *getenv();

/*
 * A short from the file in target memory order: the shared-library tables are
 * memory images, not canonical l.out fields.
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
 * The last component of a path: the client records the name the run-time
 * loader searches for, never the path ld happened to find the library at.
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
 * Read a shared library's export table and take from it every symbol the
 * client has already referenced.  Called from addmod() in place of loading the
 * module.  Returns nonzero if it satisfied anything.
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
	 * A library that imports from another is a client too, and is built
	 * with `ld -n -r -d -S'.  That -r output is a final image -- its header
	 * is rewritten and the fixup list appended, and nothing links it again
	 * -- so its stubs and slots already sit at the addresses they will load
	 * at.  An -r link that will be linked again is not: the slot address
	 * would have to survive that second link.  -S says which of the two
	 * this is.
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
		fatal("%s: not a shared library: export table magic is 0x%x, expected 0x%x",
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
		 * A function's offset is into the shared segment, as is a
		 * `readonly' table's (SE_DATA|SE_SHRD), which sits past the
		 * text in L_SHRD; a plain data object's is into the private
		 * image, PRVI+PRVD and then the zeroed BSSI+BSSD.  ld never
		 * uses any of them -- the kernel looks the name up again at
		 * exec -- but one outside its own image says the table is not
		 * one this ld understands.
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
		 * Resolved, but with no address until the stubs are laid out:
		 * hold it as an absolute 0, so that no later archive claims it
		 * again and a later definition of the same name is reported as
		 * the redefinition it is.  slalloc() gives it its real value.
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
	 * Anything the client still wants that this library defines but does
	 * not export is a mistake worth naming: the export list is the
	 * library's contract, and "undefined symbol" would blame the client.
	 *
	 * Two exceptions.  etext_/edata_/end_ describe the link they appear in,
	 * so each link defines its own set.  And the names this library itself
	 * imports: its symbol table carries each of them -- a function as the
	 * stub in its shared text, a datum as the absolute zero the import was
	 * held as -- with an LI_IMP record beside it, and neither is a
	 * definition it could hand out.  The client gets those from the library
	 * that does export them, further along its own command line.
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
 * Divert the relocation stream, for a library link that imports (-S -r).
 *
 * L_REL is the last section on disk, and its offset was fixed from the sizes as
 * they stood before pass 2.  But a DATA import's LI_IMP records are one per
 * cell, and the cells are not known until pass 2 relocates them, so L_SYM --
 * the section before it -- grows past that offset and over the head of L_REL.
 * The records go to a scratch file here, and slrelout() copies them back at the
 * offset L_SYM's final size gives.
 */
void
sldivert()
{
	if (!reloc || !slreloc || slnimp == 0 || outputf[L_REL] == NULL)
		return;
	/*
	 * Beside the output: that directory is writable by definition, and a
	 * name derived from it cannot collide with another link.
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
 * ... and copy it back, once L_SYM's size is final.
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
 * Lay the stubs and slots out, once every input has been read and before any
 * base or disk offset is computed, so the two segments they extend are still
 * only sizes.
 */
void
slalloc()
{
	sllib_t	*lp;
	slimp_t	*ip;

	if (slnimp == 0)
		return;
	/*
	 * Without the L_SYM records nothing says which library the image needs
	 * or where its slots are.
	 */
	if (nosym)
		fatal("cannot strip (-s) a program with %d shared-library import%s: the LI_LIB and LI_IMP records in the symbol table are what exec binds them with",
			slnimp, slnimp==1 ? "" : "s");
	for (lp = slhead; lp != NULL; lp = lp->next) {
		oseg[L_SYM].size += sizeof(lds_t);	/* the LI_LIB record */
		for (ip = lp->imp; ip != NULL; ip = ip->next) {
			/*
			 * A DATA import gets no stub and no slot of ld's own.
			 * The compiler has already put a 4-byte far pointer in
			 * the private data for every extern datum it addresses
			 * (-VPIC), and that cell is the slot: pass 2 reports
			 * each one to sldslot(), which counts the record.  The
			 * symbol stays the absolute 0 slread() left it as,
			 * which is what zeroes the cell.
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
 * Turn the two offsets into virtual addresses, after baseall() and before pass
 * 2 walks oseg[].vbase forward as it writes.
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
 * The LI_LIB / LI_IMP records, written into L_SYM after the ordinary symbols so
 * that no relocation's symbol number moves.
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
			 * A data import has one record per cell that addresses
			 * it, and the compiler emits one cell per object file.
			 * exec writes the same far pointer into each, which is
			 * what makes every module see one object.
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
 * The stubs and the slots themselves, written after every module's own bytes.
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
			 * In a library the stub's operand names the private
			 * half and so carries a segment number the loader
			 * moves.  It needs a relocation record of its own: the
			 * fixup list is built out of the records, and ld emits
			 * none for bytes it lays down itself.  The address is
			 * the operand, two bytes into the stub; the stream
			 * stays sorted within L_SHRI because the stubs come
			 * after every module's contribution to it.
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
 * Pass 2 found a 4-byte far pointer naming an imported DATA object, at virtual
 * address `va' in the output's private data.  That cell is the slot: remember
 * it for slsyms() and count the record now, while L_SYM's size can still grow.
 *
 * The cell is left zeroed, so a client whose library lost the symbol
 * dereferences segment 0 offset 0, which user descriptors leave inhibited.
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
 * -l NAME: LIBPATH, then /lib, then /usr/lib -- the order the run-time loader
 * uses -- and inside each directory a shared library in preference to the
 * archive of the same name.  A NAME that already carries a `.' is taken
 * literally (`-ltoy.1' is libtoy.1), which is how a program pins a major.
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
	return (rdfile(path));		/* path outlives ld: modules keep it */
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
