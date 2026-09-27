/*
 * Copyright (c) 2026 Kevin Dedon.
 * SPDX-License-Identifier: MIT
 */
/*
 * Link-time relaxation of LF_RELAX modules.
 *
 * An LR_SHORT operand whose target lands below offset 256 of its segment
 * becomes the one-word short form; an LR_CALL whose target is in the same
 * segment and within reach becomes CALR, else short where it can.  Each cut
 * moves the text after it down, so the layout is redone until no operand
 * changes form.  An operand that stops fitting is barred from that form for
 * good, which bounds the loop.
 *
 *	CALL long	5F00 8Sss oooo	6 bytes
 *	CALL short	5F00 0Sso	4 bytes
 *	CALR		Dddd		2 bytes
 */

#define	RF_LONG		0
#define	RF_SHORT	1
#define	RF_CALR		2

#define	NOSHORT		1
#define	NOCALR		2

static	int	fcut[] = { 0, 2, 4 };	/* bytes each form saves */

/*
 * What pass 2 writes into a long field, given the target's address `b'.
 */
static uaddr_t
longval(b, field, symadd)
uaddr_t	b, field;
int	symadd;
{
	if (symadd && ((field&0x00FF0000L)==0x00800000L
		    || (field&0x00FF0000L)==0x007F0000L))
		return ((b&0x00FF0000L) | 0x00800000L | ((b+field)&0xFFFFL));
	return (b + field);
}

static int
shortok(v)
uaddr_t	v;
{
	return ((v&0x00800000L) != 0 && (v&0xFFFFL) < 0x100);
}

/*
 * CALR subtracts twice its 12-bit displacement from the updated PC.
 */
static int
calrok(pc, v)
uaddr_t	pc, v;
{
	long	d;

	if ((v&0x00800000L) == 0 || ((pc>>16)&0x7F) != ((v>>16)&0x7F))
		return (0);
	d = (long)(pc&0xFFFFL) - (long)(v&0xFFFFL);
	return (d >= -4096L && d <= 4094L);
}

/*
 * Bytes cut from mp's text before module offset `off'.
 */
uaddr_t
cutat(mp, off)
register mod_t	*mp;
uaddr_t	off;
{
	register unsigned int	lo, hi, mid;

	lo = 0;
	hi = mp->nsite;
	while (lo < hi) {
		mid = (lo+hi) / 2;
		if (mp->site[mid].off < off)
			lo = mid+1;
		else
			hi = mid;
	}
	if (lo == 0)
		return (0);
	return (mp->site[lo-1].cut + fcut[mp->site[lo-1].form]);
}

/*
 * The module whose text holds pass-1 SHRI offset x, and x within it.  NULL
 * past the modules, where the stubs are.  A symbol at the end of its own
 * module belongs to that module.
 */
static mod_t *
rlxmod(x, hint, offp)
uaddr_t	x;
register mod_t	*hint;
uaddr_t	*offp;
{
	register mod_t	*mp;

	*offp = x;
	if (hint != NULL && hint->fname != NULL && x >= hint->ooff[L_SHRI]
	 && x - hint->ooff[L_SHRI] <= hint->seg[L_SHRI].size) {
		*offp = x - hint->ooff[L_SHRI];
		return (hint);
	}
	if (x >= rlxmods)
		return (NULL);
	for (mp = modhead; mp != NULL; mp = mp->next)
		if (mp->fname != NULL && x >= mp->ooff[L_SHRI]
		 && x - mp->ooff[L_SHRI] < mp->seg[L_SHRI].size) {
			*offp = x - mp->ooff[L_SHRI];
			return (mp);
		}
	return (NULL);
}

/*
 * Relaxed SHRI offset of a text point, `newmods' being the modules' new size.
 */
static uaddr_t
textat(tm, off, newmods)
register mod_t	*tm;
uaddr_t	off, newmods;
{
	if (tm == NULL)
		return (off - (rlxmods - newmods));
	return (tm->noff + off - cutat(tm, off));
}

/*
 * Resolve a site's target once: the symbol, or the module's own segment.
 */
static void
rlxtarget(mp, s, symno)
register mod_t	*mp;
register site_t	*s;
unsigned int	symno;
{
	register sym_t	*sp;
	int	seg;

	if (s->seg == L_SYM) {
		if (symno >= mp->nsym || (sp = mp->sym[symno]) == NULL) {
			s->nogo = NOSHORT|NOCALR;
			return;
		}
		s->sp = sp;
		seg = sp->s.ls_type & ~L_GLOBAL;
		if (sp->s.ls_type == (L_GLOBAL|L_REF)
		 || seg >= L_SYM && seg != L_ABS)
			s->nogo = NOSHORT|NOCALR;
		else if (seg == L_SHRI)
			s->tm = rlxmod(sp->s.ls_addr, sp->mod, &s->toff);
		return;
	}
	if (s->seg == L_SHRI) {
		s->tm = mp;
		s->toff = (s->field - mp->seg[L_SHRI].vbase) & 0xFFFFL;
	} else if (s->seg >= NXSEG && s->seg != L_ABS)
		s->nogo = NOSHORT|NOCALR;
}

/*
 * Read the LR_SHORT and LR_CALL records in mp's text, and each one's field.
 */
static void
rlxread(mp)
register mod_t	*mp;
{
	FILE	*rfp, *tfp;
	seg_t	rs, ts;
	register site_t	*s;
	int	opcode, pass;
	unsigned int	n, symno;
	uaddr_t	addr, tbase;

	if ((rfp = fopen(mp->fname, ORMODE)) == NULL
	 || (tfp = fopen(mp->fname, ORMODE)) == NULL) {
		filerr(mp->fname, "can't open (relax)");
		exit(1);
	}
	tbase = mp->seg[L_SHRI].vbase;
	n = 0;
	for (pass = 0; pass < 2; pass++) {
		rs.size = mp->seg[L_REL].size;
		rs.vbase = 0;
		fseek(rfp, mp->seg[L_REL].daddr, 0);
		n = 0;
		while ((opcode = getbyte(rfp, &rs)) != EOF) {
			addr = getaddr(rfp, &rs);
			symno = (opcode&LR_SEG) == L_SYM ? getsymno(rfp, &rs) : 0;
			if ((opcode&LR_OP) != LR_SHORT && (opcode&LR_OP) != LR_CALL
			 || (opcode&LR_PCR) != 0 || addr < tbase
			 || addr - tbase >= mp->seg[L_SHRI].size)
				continue;
			if (pass == 0) {
				n++;
				continue;
			}
			s = &mp->site[n++];
			s->off = addr - tbase;
			s->kind = opcode & LR_OP;
			s->seg = opcode & LR_SEG;
			s->sp = NULL;
			s->tm = NULL;
			s->toff = s->cut = 0;
			s->form = RF_LONG;
			s->nogo = 0;
			ts.size = 4;
			ts.vbase = 0;
			fseek(tfp, mp->seg[L_SHRI].daddr + s->off
				+ (s->kind == LR_CALL ? 2 : 0), 0);
			s->field = vtop(getlong(tfp, &ts));
			rlxtarget(mp, s, symno);
		}
		if (n == 0)
			break;
		if (pass == 0
		 && (mp->site = (site_t *)malloc(n * sizeof(site_t))) == NULL)
			fatal(nospace);
	}
	mp->nsite = n;
	fclose(rfp);
	fclose(tfp);
}

/*
 * Lay the text out for the present forms: each module's cuts, its offset,
 * and under -L the padding that keeps it inside one hardware segment.  The
 * segment bases go in lay[]; the modules' new SHRI size is returned.
 */
static uaddr_t
rlxlay(lay)
seg_t	lay[];
{
	register mod_t	*mp;
	register unsigned int	i;
	uaddr_t	cur, size, c, max, max1;

	cur = 0;
	max = segmax[machine];
	max1 = max-1;
	for (mp = modhead; mp != NULL; mp = mp->next) {
		if (mp->fname == NULL)
			continue;
		c = 0;
		for (i = 0; i < mp->nsite; i++) {
			mp->site[i].cut = c;
			c += fcut[mp->site[i].form];
		}
		size = mp->seg[L_SHRI].size - c;
		mp->pad = 0;
		if (lmodel && (cur&max1) + size > max) {
			mp->pad = max - (cur&max1);
			cur += mp->pad;
		}
		mp->noff = cur;
		cur += size;
	}
	for (i = 0; i < NLSEG; i++)
		lay[i] = oseg[i];
	lay[L_SHRI].size = cur + oseg[L_SHRI].size - rlxmods;
	baseall(lay, &oldh);
	return (cur);
}

/*
 * The value pass 2 would put in a site's long field under layout lay[].
 */
static uaddr_t
rlxval(mp, s, lay, newmods)
register mod_t	*mp;
register site_t	*s;
seg_t	lay[];
uaddr_t	newmods;
{
	register sym_t	*sp;
	uaddr_t	b;
	int	seg;

	if ((sp = s->sp) != NULL) {
		seg = sp->s.ls_type & ~L_GLOBAL;
		if (seg == L_ABS)
			b = sp->s.ls_addr;
		else if (seg == L_SHRI)
			b = lay[L_SHRI].vbase + textat(s->tm, s->toff, newmods);
		else
			b = lay[seg].vbase + sp->s.ls_addr;
		return (longval(b, s->field, 1));
	}
	if (s->seg == L_ABS)
		return (s->field);
	b = lay[s->seg].vbase - mp->seg[s->seg].vbase;
	if (s->seg == L_SHRI)
		b += mp->noff - cutat(mp, s->toff);
	else
		b += mp->ooff[s->seg];
	return (b + s->field);
}

void
relax()
{
	register mod_t	*mp;
	register site_t	*s;
	register sym_t	*sp;
	register unsigned int	i;
	seg_t	lay[NLSEG];
	uaddr_t	newmods, v, off;
	int	changed, want;
	unsigned int	nform[3];

	changed = 0;
	for (mp = modhead; mp != NULL; mp = mp->next)
		if (mp->fname != NULL && mp->relax) {
			rlxread(mp);
			changed |= mp->nsite != 0;
		}
	if (!changed)
		return;
	do {
		newmods = rlxlay(lay);
		changed = 0;
		nform[RF_LONG] = nform[RF_SHORT] = nform[RF_CALR] = 0;
		for (mp = modhead; mp != NULL; mp = mp->next)
			for (i = 0; i < mp->nsite; i++) {
				s = &mp->site[i];
				want = RF_LONG;
				if ((s->nogo&(NOSHORT|NOCALR)) != (NOSHORT|NOCALR)) {
					v = rlxval(mp, s, lay, newmods);
					if (s->kind == LR_CALL && (s->nogo&NOCALR) == 0
					 && calrok(lay[L_SHRI].vbase + mp->noff + s->off
						   - s->cut + 2, v))
						want = RF_CALR;
					else if ((s->nogo&NOSHORT) == 0 && shortok(v))
						want = RF_SHORT;
				}
				if (s->form == RF_CALR && want != RF_CALR)
					s->nogo |= NOCALR;
				if (s->form == RF_SHORT && want == RF_LONG)
					s->nogo |= NOSHORT;
				if (want != s->form) {
					s->form = want;
					changed = 1;
				}
				nform[want]++;
			}
	} while (changed);
	if (watch)
		message("relax: %u short, %u calr, %u long",
			nform[RF_SHORT], nform[RF_CALR], nform[RF_LONG]);
	if (nform[RF_SHORT] == 0 && nform[RF_CALR] == 0)
		return;

	/*
	 * Commit: symbols and stubs move with their text, and the pads -L's
	 * placeholder modules held are now each module's own.
	 */
	relaxed = 1;
	for (i = 0; i < NHASH; i++)
		for (sp = symtable[i]; sp != NULL; sp = sp->next)
			if (sp->s.ls_type != (L_GLOBAL|L_REF)
			 && (sp->s.ls_type&~L_GLOBAL) == L_SHRI) {
				mp = rlxmod(sp->s.ls_addr, sp->mod, &off);
				sp->s.ls_addr = textat(mp, off, newmods);
			}
	for (mp = modhead; mp != NULL; mp = mp->next)
		if (mp->fname == NULL)
			mp->seg[L_SHRI].size = 0;
	slshift(rlxmods - newmods);
	oseg[L_SHRI].size = lay[L_SHRI].size;
	baseall(oseg, &oldh);
	slbind();
	for (i = 0; i < NXSEG; i++)
		rbase[i] = oseg[i].vbase;
}

/*
 * Pass 2: the site at module text offset `off', if any; *ip walks forward.
 */
site_t *
rlxsite(mp, off, ip)
register mod_t	*mp;
uaddr_t	off;
unsigned int	*ip;
{
	while (*ip < mp->nsite && mp->site[*ip].off < off)
		++*ip;
	if (*ip < mp->nsite && mp->site[*ip].off == off)
		return (&mp->site[*ip]);
	return (NULL);
}

/*
 * Pass 2: write a site in its form.  `op' is a CALL's opcode word, `v' the
 * long field's value.
 */
void
rlxput(mp, s, op, v, ofp, osgp)
mod_t	*mp;
register site_t	*s;
unsigned int	op;
uaddr_t	v;
FILE	*ofp;
seg_t	*osgp;
{
	long	d;

	if (s->form == RF_CALR) {
		if (!calrok(osgp->vbase + 2, v))
			mperr(mp, "CALR at %06lo cannot reach %06lo",
				(long)osgp->vbase, (long)v);
		d = (long)((osgp->vbase+2)&0xFFFFL) - (long)(v&0xFFFFL);
		putword((unsigned short)(0xD000 | (int)((d>>1)&0xFFF)), ofp, osgp);
		return;
	}
	if (s->kind == LR_CALL)
		putword((unsigned short)op, ofp, osgp);
	if (s->form == RF_SHORT) {
		if (!shortok(v))
			mperr(mp, "short address %06lo out of range", (long)v);
		putword((unsigned short)(((v>>8)&0x7F00) | (v&0xFF)), ofp, osgp);
		return;
	}
	putlong((long)ptov(v), ofp, osgp);
}

static long
sext16(w)
unsigned int	w;
{
	return ((w & 0x8000) ? (long)w - 0x10000L : (long)w);
}

/*
 * Pass 2: re-aim a JR, CALR, DJNZ or LDAR inside the module across the cuts,
 * or with `self' a word holding its target less its own address.  `tbase' is
 * the module's input text base.
 */
void
rlxbranch(mp, tbase, self, ifp, isgp, ofp, osgp)
register mod_t	*mp;
uaddr_t	tbase;
int	self;
FILE	*ifp, *ofp;
seg_t	*isgp, *osgp;
{
	unsigned short	w;
	long	s, t, d;
	int	kind, ok;

	s = isgp->vbase - tbase;
	w = getword(ifp, isgp);
	kind = self ? 0 : (w>>12) & 0xF;
	if (kind == 0x3 && (w & 0xFFF0) != 0x3400)
		kind = -1;
	switch (kind) {
	case 0x0:				/* table word: target - itself */
		t = s + sext16(w);
		break;
	case 0x3:				/* LDAR: PC + 16-bit d */
		t = s + 4 + sext16(getword(ifp, isgp));
		break;
	case 0xE:				/* JR cc: PC + 2d */
		d = w & 0xFF;
		if (d & 0x80)
			d -= 0x100;
		t = s + 2 + 2*d;
		break;
	case 0xD:				/* CALR: PC - 2d */
		d = w & 0xFFF;
		if (d & 0x800)
			d -= 0x1000;
		t = s + 2 - 2*d;
		break;
	case 0xF:				/* DJNZ, DBJNZ: PC - 2d */
		t = s + 2 - 2*(long)(w & 0x7F);
		break;
	default:
		mperr(mp, "relocated branch %06o is not JR, CALR, DJNZ or LDAR", w);
		putword(w, ofp, osgp);
		return;
	}
	t -= cutat(mp, (uaddr_t)t);
	s -= cutat(mp, (uaddr_t)s);
	if (kind == 0x0 || kind == 0x3) {
		d = t - (kind ? s+4 : s);
		if (d < -32768L || d > 32767L)
			mperr(mp, "branch at %06lo out of reach", (long)s);
		if (kind)
			putword(w, ofp, osgp);
		putword((unsigned short)d, ofp, osgp);
		return;
	}
	d = (t - (s+2)) / 2;
	switch (kind) {
	case 0xE:
		ok = d >= -128 && d <= 127;
		w = (w & 0xFF00) | (int)(d & 0xFF);
		break;
	case 0xD:
		ok = d >= -2047 && d <= 2048;
		w = 0xD000 | (int)(-d & 0xFFF);
		break;
	default:
		ok = d <= 0 && d >= -127;
		w = (w & 0xFF80) | (int)(-d & 0x7F);
		break;
	}
	if (!ok)
		mperr(mp, "branch at %06lo out of reach", (long)s);
	putword(w, ofp, osgp);
}
