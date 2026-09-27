/*
 * Copyright (c) 1977-1995 Robert Swartz.
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * Pass 2
 */

/*
 * Names of segments
 */
char	*sname[] = {
	"SHRI", "PRVI", "BSSI", "SHRD", "PRVD", "BSSD", "DEBUG", "SYM", "REL"
};

/*
 * Read, relocate and output segments of module
 */
void
loadmod(mp)
mod_t	*mp;
{
	seg_t	*isgp, *irsp, *osgp, *orsp;
	sym_t	*sp;
	int	opcode, relseg;
	int	segn;
	int	symadd;
	int	dimp;
	uaddr_t	addr, bias, field;
	unsigned int	symno;
	FILE	*ifp, *irfp, *ofp, *orfp;
	static	FILE	*inputf[NLSEG];
	static	char	*fname = NULL;
	int	rlx, kind;
	unsigned int	si, callop;
	uaddr_t	ibase[NXSEG];
	site_t	*sitep;

	if (mp->fname == NULL) {
		lfixup2(mp);
		return;
	}
	if (watch)
		mpmsg(mp, "loading");
	/*
	 * A relaxed module's text no longer moves in step with its input, so
	 * its segment-relative bias comes from the layout, not from vbase.
	 */
	rlx = relaxed && mp->relax;
	si = 0;
	for (segn=0; segn<NXSEG; segn++)
		ibase[segn] = mp->seg[segn].vbase;
	if (relaxed && outputf[L_SHRI]!=NULL)
		for (; mp->pad!=0; mp->pad--)
			putbyte(0, outputf[L_SHRI], &oseg[L_SHRI]);
	for (segn=0; segn<NLSEG; segn++) {
		if (segn!=L_REL&&outputf[segn]==NULL)
			continue;
		if (fname!=mp->fname) {
			if (fname!=NULL)
				fclose(inputf[segn]);
			if ((inputf[segn]=fopen(mp->fname, ORMODE))==NULL) {
				filerr(mp->fname, "can't open (pass 2)");
				exit(1);
			}
		}
		fseek(inputf[segn], mp->seg[segn].daddr, 0);
		if (watch && mp->seg[segn].size!=0)
			message("relocating seg#%d[%06lo]@%06lo to %06lo",
				segn, (long)mp->seg[segn].size,
				(long)mp->seg[segn].vbase,
				(long)oseg[segn].vbase);
	}
	fname = mp->fname;
	irfp = inputf[L_REL];
	irsp = &mp->seg[L_REL];
	orfp = outputf[L_REL];
	orsp = &oseg[L_REL];
	while ((opcode=getbyte(irfp, irsp))!=EOF) {
		addr = getaddr(irfp, irsp);
		/* find segment in which it address lies */
		for (segn=0, isgp=&mp->seg[0]; segn<L_SYM; segn++, isgp++) {
			if (addr>=isgp->vbase && addr<isgp->vbase+isgp->size)
				break;
		}
		if (segn==L_BSSI
		 || segn==L_BSSD
		 || segn==L_SYM) {
			mperr(mp, "bad relocation address %06lo", (long)addr);
			continue;
		}
		ifp = inputf[segn];
		ofp = outputf[segn];
		osgp = &oseg[segn];
		/* put unrelocated stuff */
		while (isgp->vbase < addr)
			putbyte(getbyte(ifp, isgp), ofp, osgp);
		/*
		 * Unless relaxing, a branch record needs nothing and an
		 * LR_SHORT or LR_CALL is an LR_LONG; relocation output keeps
		 * only the LR_LONG.
		 */
		kind = opcode&LR_OP;
		if (kind == LR_BRANCH) {
			if ((opcode&LR_SEG) == L_SYM)
				getsymno(irfp, irsp);
			if (rlx && segn == L_SHRI)
				rlxbranch(mp, ibase[L_SHRI], opcode&LR_PCR,
					ifp, isgp, ofp, osgp);
			else if (orfp != NULL)
				orsp->size -= (opcode&LR_SEG) == L_SYM ? 7 : 5;
			continue;
		}
		sitep = NULL;
		if (kind == LR_SHORT || kind == LR_CALL) {
			if (rlx && segn == L_SHRI)
				sitep = rlxsite(mp, addr - ibase[L_SHRI], &si);
			if (kind == LR_CALL) {
				if (sitep != NULL)
					callop = getword(ifp, isgp);
				else {
					putbyte(getbyte(ifp, isgp), ofp, osgp);
					putbyte(getbyte(ifp, isgp), ofp, osgp);
				}
			}
			opcode = opcode&~LR_OP | LR_LONG;
		}
		bias = 0;
		symadd = 0;
		dimp = 0;
		sp = NULL;
		switch (relseg = opcode&LR_SEG) {
		case L_SYM:
			symno = getsymno(irfp, irsp);
			if (symno>=mp->nsym) {
				mperr(mp, "bad reloc. sym. no. %d", symno);
			} else if ((sp=mp->sym[symno])==NULL) {
				mperr(mp, "symbol %d not kept", symno);
			} else if (sp->s.ls_type==(L_GLOBAL|L_REF)) {
				if (orfp!=NULL) {
					putbyte(opcode, orfp, orsp);
					putaddr(osgp->vbase, orfp, orsp);
					putsymno(sp->symno, orfp, orsp);
				}
			} else {
				bias = sp->s.ls_addr;
				symadd = 1;
				dimp = sp->sldata;
				if (orfp!=NULL) {
					putbyte(sp->s.ls_type&LR_SEG
						|opcode&~LR_SEG,
						orfp, orsp);
					putaddr(osgp->vbase, orfp, orsp);
					/* keep segment size correct */
					orsp->size -= sizeof(short);
				}
			}
			break;
		case L_SHRI:
		case L_PRVI:
		case L_BSSI:
		case L_SHRD:
		case L_PRVD:
		case L_BSSD:
			if (rlx)
				bias = rbase[relseg] - ibase[relseg]
				     + (relseg==L_SHRI ? mp->noff
						       : mp->ooff[relseg]);
			else
				bias	= oseg[relseg].vbase
					- mp->seg[relseg].vbase;
		case L_ABS:
			if (orfp!=NULL) {
				putbyte(opcode, orfp, orsp);
				putaddr(osgp->vbase, orfp, orsp);
			}
			break;
		default:
			goto BadCode;
		}
		/*
		 * A library's DATA export has no address until exec, so only a
		 * 4-byte far pointer in private data can name one; shared text
		 * cannot be patched per client.
		 */
		if (dimp && ((opcode&LR_OP) != LR_LONG || (opcode&LR_PCR) != 0
			  || segn != L_PRVD)) {
			mperr(mp, "%.*s: a shared library's data can only be reached through a far pointer in private data (compile with -VPIC)",
				NCPLN, sp->s.ls_id);
			dimp = 0;
		}
		if (opcode&LR_PCR)
			bias += isgp->vbase - osgp->vbase;
		switch (opcode&LR_OP) {
		default:
		BadCode:
			mperr(mp, "bad relocation opcode %03o", opcode);
			break;
		case LR_BYTE:
			bias += getbyte(ifp, isgp);
			putbyte((int)bias, ofp, osgp);
			break;
		case LR_WORD:
			field = getword(ifp, isgp);
			if (rlx && relseg == L_SHRI)
				bias -= cutat(mp, (field-ibase[L_SHRI])&0xFFFFL);
			bias += field;
			putword((short)bias, ofp, osgp);
			break;
		case LR_LONG:
			field = vtop(getlong(ifp, isgp));
			if (rlx && relseg == L_SHRI)
				bias -= cutat(mp, (field-ibase[L_SHRI])&0xFFFFL);
			/*
			 * A SEGMENTED long operand relocated against a SYMBOL
			 * carries no address of its own: the field is the
			 * present bit (0x80 in the segment byte) plus a 16-bit
			 * offset ADDEND, and the address is the symbol's.  Both
			 * producers write it that way -- as/z8001 outrl() lays
			 * down 0x80000000+value, cc2's patchaddr() the same sum
			 * in 24 bits -- so a NEGATIVE addend borrows out of the
			 * segment byte and leaves 0x7F there.
			 *
			 * Add the halves separately: a virtual address is not a
			 * number, and the offset must wrap inside the segment
			 * rather than carry into it.  No single object may
			 * exceed 64K, so an addend on a symbol cannot leave the
			 * symbol's own segment -- which is what makes the wrap
			 * right and the carry wrong.  `Word[strlen(Word) - 1]'
			 * on an extern array is the form that produced it: the
			 * -1 reaches ld as an addend of 0xFFFF and the carry out
			 * of the offset made the store segment 5 for a symbol in
			 * segment 4.  Taking the low 16 bits of the sum absorbs
			 * the borrow of the negative form and the wrap of the
			 * unsigned one alike, so both spellings of -1 land on
			 * the same byte.
			 *
			 * The SEGMENT-relative kinds are NOT this case and
			 * are left alone: there the field IS an address inside
			 * the module's own segment and `bias' is a linear base
			 * delta, so an offset that runs past 64K belongs in the
			 * next segment and the carry is what puts it there.  A
			 * relocation still to be written out (an unresolved
			 * L_REF, bias untouched) is left alone too: its addend
			 * has to reach the next link in the bytes it arrived in.
			 *
			 * MWC left a disabled attempt at this symptom here: it
			 * tested the finished sum for a 0xFF segment byte, and
			 * compensated with +0x01000000, which ptov() discards --
			 * so enabling it would only have forced such a
			 * relocation into segment 0.  Neither producer above
			 * leaves 0xFF in the segment byte anyway.
			 */
			if (segoff && symadd && (opcode&LR_PCR)==0
			 && ((field&0x00FF0000L)==0x00800000L
			  || (field&0x00FF0000L)==0x007F0000L))
				bias = (bias&0x00FF0000L) | 0x00800000L
					| ((bias+field)&0xFFFFL);
			else
				bias += field;
			/*
			 * A DATA import's slot keeps the addend (`a[1]') in its
			 * low word; exec adds the export's offset.  Segment 0
			 * until bound, so an unbound slot traps.
			 */
			if (dimp) {
				sldslot(sp, ptov(osgp->vbase));
				bias = field & 0xFFFFL;
			}
			if (sitep != NULL)
				rlxput(mp, sitep, callop, bias, ofp, osgp);
			else
				putlong((long)ptov(bias), ofp, osgp);
			break;
		}
	}
	/* copy remainder of segments */
	for (segn=0; segn<L_SYM; segn++) {
		register int	b;

		if ((ofp=outputf[segn])==NULL)
			continue;
		ifp = inputf[segn];
		isgp = &mp->seg[segn];
		osgp = &oseg[segn];
		while ((b=getbyte(ifp, isgp))!=EOF)
			putbyte(b, ofp, osgp);
	}
#ifdef LADDR
#endif
	/* adjust bss bases (others done by putbyte) */
	oseg[L_BSSD].vbase += mp->seg[L_BSSD].size;
	oseg[L_BSSI].vbase += mp->seg[L_BSSI].size;
}

#ifdef LADDR
/*
 * Pad out with the fake module.
 * Deal with BSS and `real' segments as well.
 */
void
lfixup2(mp)
register mod_t *mp;
{
	extern char *sname[];
	register int i;
	register FILE *ofp;
	register seg_t *osgp;
	long p;

	for (i=0; i<NXSEG; i++)
		if ((p = mp->seg[i].size) != 0)
			break;
	if (watch)
		message("paddding %s for %D bytes", sname[i], p);
	if ((ofp = outputf[i]) == NULL)
		return;
	osgp = &oseg[i];
	while (p-- > 0)
		putbyte(0, ofp, osgp);
}
#endif

/*
 * I/O routines
 */
void
putstruc(p, s, fp, sgp)
register char	*p;
register unsigned int	s;
register FILE	*fp;
register seg_t	*sgp;
{
	while (s--)
		putbyte(*p++, fp, sgp);
}

unsigned short
getword(fp, sgp)
FILE	*fp;
seg_t	*sgp;
{
	return (worder==LOHI ? getlohi(fp, sgp) : gethilo(fp, sgp));
}

unsigned long
getlong(fp, sgp)
FILE *fp;
seg_t *sgp;
{
	register unsigned short w1, w2;
	register unsigned long l;

	w1 = getword(fp, sgp);
	w2 = getword(fp, sgp);
	if (lorder == LOHI)
		l = ((long)w2<<16) + w1; else
		l = ((long)w1<<16) + w2;
	return (l);
}

unsigned short
getlohi(fp, sgp)
FILE	*fp;
seg_t	*sgp;
{
	register unsigned char	b;

	b = getbyte(fp, sgp);
	return((getbyte(fp, sgp)<<8)|b);
}

unsigned short
gethilo(fp, sgp)
FILE	*fp;
seg_t	*sgp;
{
	register unsigned char	b;

	b = getbyte(fp, sgp);
	return((b<<8)|getbyte(fp, sgp));
}

int
getbyte(fp, sgp)
FILE	*fp;
seg_t	*sgp;
{
	if (sgp->size==0)
		return (EOF);
	else {
		sgp->size--;
		sgp->vbase++;
		return (getc(fp));
	}
}

void
putword(w, fp, sgp)
unsigned short	w;
FILE	*fp;
seg_t	*sgp;
{
	if (worder==LOHI)
		putlohi(w, fp, sgp);
	else
		puthilo(w, fp, sgp);
}

/*
 * Put out a long integer.
 */
void
putlong(l, fp, sgp)
register unsigned long l;
FILE *fp;
seg_t *sgp;
{
	register unsigned short w1, w2;

	w1 = l>>16;
	w2 = l&0xFFFF;
	if (lorder == LOHI) {
		putword(w2, fp, sgp);
		putword(w1, fp, sgp);
	} else {
		putword(w1, fp, sgp);
		putword(w2, fp, sgp);
	}
}

void
putlohi(w, fp, sgp)
unsigned short	w;
FILE	*fp;
seg_t	*sgp;
{
	putbyte(w&0377, fp, sgp);
	putbyte(w>>8, fp, sgp);
}

void
puthilo(w, fp, sgp)
unsigned short	w;
FILE	*fp;
seg_t	*sgp;
{
	putbyte(w>>8, fp, sgp);
	putbyte(w&0377, fp, sgp);
}

void
putbyte(b, fp, sgp)
unsigned char	b;
FILE	*fp;
seg_t	*sgp;
{
	sgp->vbase++;
	putc(b, fp);
}

/*
 * Get a relocation address.  There has to
 * be a more efficient thing than a shift to
 * do this!!
 */
unsigned long
getaddr(fp, sgp)
FILE *fp;
seg_t *sgp;
{
	register unsigned w1, w2;

	w1 = getlohi(fp, sgp);
	w2 = getlohi(fp, sgp);
	return (((long)w1<<16) + w2);
}
