/*
 * Copyright (c) 2026 Kevin Dedon.
 * SPDX-License-Identifier: MIT
 */
/*
 * n1/z8001/gen1.c
 * Address printing, function prologue/epilogue framing, switch compilation, and
 * the low-level instruction-emission primitives. Segmented Z8001.
 * Template: n1/i8086/gen1.c. Deltas vs i8086:
 *   - ramode[] is the Z8001 register file (R0..R15 word, RH/RL byte);
 *   - no x87 FPAC pseudo-register (that branch is dead, FPAC = -1);
 *   - conditional jumps are ONE opcode (ZJP) + a condition code, not a per-
 *     relation opcode (the optab relation rows hold CC_*);
 *   - gencoll's REG case: any base reg R1..R15 -> indexed mode A_X|reg (the
 *     Z8000 has no fixed BX/BP/SI/DI index registers);
 *   - genswitch dispatches a dense switch through a table of self-relative
 *     words, else compares case by case.
 * The emission primitives + prologue/epilogue framing are machine-independent
 * (they write CODE/AUTOS records into the n1->n2 IR; n2 emits real instructions).
 */
#ifdef   vax
#include "INC$LIB:cc1.h"
#else
#include "cc1.h"
#endif
#include "pseudops.h"

/* Machine-dependent allocation state (set up by routines here). Types match the
 * extern declarations in cc1.h (4.2.12 uses ival_t for the auto/temp counters). */
ival_t	maxauto;		/* Max autos in this function */
ival_t	basauto;		/* Block auto size as read from cc0, before any
				 * modify-phase temp raises maxauto over it */
int	mdtcoded;		/* Instructions emitted since the last modify-phase
				 * temp: that statement is coded, its temps dead */
ival_t	maxtemp;		/* Max temps in this function */
ival_t	curtemp;		/* Current temp */
PREGSET	regbusy;		/* Busy flags */
PREGSET	maxregbusy;		/* Union of regbusy over the whole function: the callee-saved
				 * registers cc2 (n2) must save/restore in the prolog/epilog. */
int	retreg = -1;		/* Return register of the return statement being coded */
int	retlab;			/* First cc1 label of that statement */

/*
 * Register -> addressing-mode table, indexed by 'real' register number
 * (mch.h). Word regs R0..R15 -> A_WR|n; byte regs RH0..RH7 -> A_BR|(0..7),
 * RL0..RL7 -> A_BR|(8..15) (the grouped Z8000 byte-register encoding). Pairs
 * and quads are 0 here -- genadr reaches their word halves via hihalf/lohalf.
 */
static	short	ramode[] = {
	A_WR|0,  A_WR|1,  A_WR|2,  A_WR|3,	/* R0..R3   */
	A_WR|4,  A_WR|5,  A_WR|6,  A_WR|7,	/* R4..R7   */
	A_WR|8,  A_WR|9,  A_WR|10, A_WR|11,	/* R8..R11  */
	A_WR|12, A_WR|13, A_WR|14, A_WR|15,	/* R12..R15 */
	/* RR0..RR14 (pairs): a long register is named by its EVEN word register,
	 * so the operand field carries R0,R2,...,R14 (= the pair's high half). */
	A_WR|0,  A_WR|2,  A_WR|4,  A_WR|6,
	A_WR|8,  A_WR|10, A_WR|12, A_WR|14,
	A_WR|0,  A_WR|4,  A_WR|8,  A_WR|12,	/* RQ0..RQ12 (quads)  */
	A_BR|0,  A_BR|1,  A_BR|2,  A_BR|3,	/* RH0..RH3 */
	A_BR|4,  A_BR|5,  A_BR|6,  A_BR|7,	/* RH4..RH7 */
	A_BR|8,  A_BR|9,  A_BR|10, A_BR|11,	/* RL0..RL3 */
	A_BR|12, A_BR|13, A_BR|14, A_BR|15	/* RL4..RL7 */
};

/*
 * Machine-dependent coder init: zero patcache[] entries that need a machine
 * variant the current build does not enable (Z8001: the Z8070 EPU patterns).
 */
coderinit()
{
	extern int patcsize;
	register int i;
	register PATFLAG *pfp;
	register PATFLAG pflag;

	for (pfp = patcache, i = 0; i < patcsize; pfp++, i++) {
		if (((pflag = *pfp) & MDPFLAGS) != 0)
			*pfp = (notvariant(VEPU) && ((pflag & PEPU) != 0))
				? 0 : (pflag & ~MDPFLAGS);
	}
}

/*
 * A local the source did not declare `register' still gets a callee-saved
 * register when nothing outside the function can reach its frame slot.  That
 * takes the whole body, so at PROLOG the records are read ahead to EPILOG; if
 * anything is promoted they are copied into memory with the automatic ids
 * made registers and the allocation records widened, and the tree reader
 * takes its input from there until EPILOG.
 *
 * A candidate is a word, long or pointer slot of the function's own block --
 * inner-block slots are reused once the block closes -- whose address is never
 * taken and that is never accessed volatile, in a function that names no
 * setjmp: a register holds a stale value when setjmp returns the second time.
 * The most used candidates are served first.  Not under VDEBUG, whose records
 * name the frame slot.
 */
#define	NPCAND	48		/* candidates considered, first declared first */
#define	PMAXLEN	65536L		/* a longer function is not considered */
#define	PWORD	1
#define	PPAIR	2

typedef struct {
	lval_t	pm_offs;
	int	pm_uses;
	char	pm_kind;	/* PWORD, PPAIR, or 0: never a register */
	char	pm_vol;
	char	pm_esc;		/* address taken */
	int	pm_reg;		/* register given, or -1 */
} PMSLOT;

static	PMSLOT	*pmslot;
static	int	npmslot, pmslotmax;
static	unsigned char	*pmbuf;	/* the rewritten function */
static	unsigned char	*pmout;	/* the rewrite goes here; NULL: only look */
static	unsigned char	*pmend;
extern	unsigned char	*ibufp, *ibufend;
static	long	pmlen;		/* bytes read since PROLOG */
static	int	pmbad;		/* not a function this can read */
static	int	pmsetjmp;
static	int	pmnauto;	/* allocation records seen */
static	ival_t	pmtop;		/* frame size of the function's own block */
static	PREGSET	pmmask;		/* registers claimed anywhere in the function */
static	PREGSET	pmpro;		/* ... and those promotion added */

static int
pmget()
{
	register int	c;

	if ((c = getc(ifp)) == EOF) {
		pmbad = 1;
		return (0);
	}
	++pmlen;
	return (c);
}

static
pmput(p, n)
register char	*p;
register int	n;
{
	if (pmout != NULL)
		while (n-- > 0)
			if (pmout < pmend)
				*pmout++ = *p++;
			else {
				pmbad = 1;
				return;
			}
}

static
pmbyte()
{
	char	c;

	c = pmget();
	pmput(&c, 1);
	return (c & 0377);
}

static ival_t
pmival()
{
	ival_t		i;
	register char	*p;
	register int	n;

	p = (char *)&i;
	for (n = sizeof(i); n > 0; --n)
		*p++ = pmget();
	return (i);
}

static lval_t
pmlval()
{
	lval_t		l;
	register char	*p;
	register int	n;

	p = (char *)&l;
	for (n = sizeof(l); n > 0; --n)
		*p++ = pmget();
	return (l);
}

static
pmputi(i)
ival_t	i;
{
	pmput((char *)&i, sizeof(i));
}

static ival_t
pmicpy()
{
	ival_t	i;

	i = pmival();
	pmputi(i);
	return (i);
}

/* Copy a size; returns it as a long. */
static lval_t
pmzcpy()
{
#if	SIZEOF_LARGE
	lval_t	l;

	l = pmlval();
	pmput((char *)&l, sizeof(l));
	return (l);
#else
	return ((lval_t)pmicpy());
#endif
}

/* Copy a string into 'buf' of 'n' bytes. */
static
pmscpy(buf, n)
register char	*buf;
register int	n;
{
	register int	c;

	while ((c = pmbyte()) != 0 && !pmbad)
		if (n > 1) {
			*buf++ = c;
			--n;
		}
	*buf = 0;
}

static PMSLOT *
pmfind(offs)
lval_t	offs;
{
	register PMSLOT	*sp;
	register int	i;

	for (i = 0, sp = pmslot; i < npmslot; ++i, ++sp)
		if (sp->pm_offs == offs)
			return (sp);
	return (NULL);
}

static
pmkind(t)
{
	switch (t) {
	case S16:
	case U16:
	case SPTR:
		return (PWORD);
	case S32:
	case U32:
	case LPTR:
		return (PPAIR);
	}
	return (0);
}

/* Note a reference to the slot at 'offs' of type 't'. */
static
pmref(offs, t, addr)
lval_t	offs;
{
	register PMSLOT	*sp;

	if ((sp = pmfind(offs)) == NULL) {
		if (npmslot >= pmslotmax) {
			pmslotmax = pmslotmax ? 2*pmslotmax : 32;
			sp = (PMSLOT *)(pmslot != NULL
			    ? realloc((char *)pmslot, pmslotmax*sizeof(PMSLOT))
			    : malloc(pmslotmax*sizeof(PMSLOT)));
			if (sp == NULL) {
				pmbad = 1;
				return;
			}
			pmslot = sp;
		}
		sp = &pmslot[npmslot++];
		sp->pm_offs = offs;
		sp->pm_uses = 0;
		sp->pm_kind = pmkind(t & ~TVOL);
		sp->pm_vol = sp->pm_esc = 0;
		sp->pm_reg = -1;
	}
	++sp->pm_uses;
	if (pmkind(t & ~TVOL) != sp->pm_kind)
		sp->pm_kind = 0;
	if ((t & TVOL) != 0)
		sp->pm_vol = 1;
	if (addr)
		sp->pm_esc = 1;
}

/* Copy a tree whose parent is 'up'. */
static
pmtree(up)
{
	register PMSLOT	*sp;
	register int	t;
	ival_t		op, size;
	lval_t		offs;
	char		name[NCSYMB];

	op = pmival();
	if (op == NIL || pmbad) {
		pmputi(op);
		return;
	}
	t = pmget();
	name[0] = t;
	if ((t & ~TVOL) == BLK)
		size = pmival();
	if (op == AID) {
#if	SIZEOF_LARGE
		offs = pmlval();
#else
		offs = pmival();
#endif
		if (pmout == NULL)
			pmref(offs, t, up == ADDR);
		else if ((sp = pmfind(offs)) != NULL && sp->pm_reg >= 0) {
			pmputi((ival_t)REG);
			pmput(name, 1);
			pmputi((ival_t)sp->pm_reg);
			return;
		}
	}
	pmputi(op);
	pmput(name, 1);
	if ((t & ~TVOL) == BLK)
		pmputi(size);
	switch (op) {
	case ICON:
	case REG:
		pmicpy();
		break;
	case LCON:
		offs = pmlval();
		pmput((char *)&offs, sizeof(offs));
		break;
	case DCON:
		for (t = sizeof(dval_t); t > 0 && !pmbad; --t)
			pmbyte();
		break;
	case AID:
#if	SIZEOF_LARGE
		pmput((char *)&offs, sizeof(offs));
#else
		pmputi((ival_t)offs);
#endif
		break;
	case PID:
		pmzcpy();
		break;
	case LID:
		pmzcpy();
		pmbyte();
		pmicpy();
		break;
	case GID:
		pmzcpy();
		pmbyte();
		pmscpy(name, NCSYMB);
#if	APPENDBAR
		if ((t = strlen(name)) > 0 && name[t-1] == '_')
			name[t-1] = 0;
#endif
		if (strcmp(name, "setjmp") == 0 || strcmp(name, "_setjmp") == 0
		 || strcmp(name, "sigsetjmp") == 0 || strcmp(name, "envsave") == 0)
			pmsetjmp = 1;
		break;
	case FIELD:
		pmbyte();
		pmbyte();
		pmtree(op);
		break;
	default:
		if (!pmbad)
			pmtree(op);
		if (!pmbad)
			pmtree(op);
	}
}

/* Copy a debug record of class 'class'. */
static
pmdbg(class)
{
	register int	n;
	lval_t		z;
	char		name[NCSYMB];

	pmicpy();
	if (class >= DC_AUTO && class < DC_MOS)
		pmicpy();
	else if (class >= DC_MOS) {
		pmbyte();
		pmbyte();
		pmicpy();
	}
	pmscpy(name, NCSYMB);
	while (!pmbad) {
		n = pmbyte();
		z = pmzcpy();
		switch (n) {
		case DT_STRUCT:
		case DT_UNION:
		case DT_ENUM:
		case DD_PTR:
		case DD_FUNC:
		case DD_ARRAY:
			continue;
		case DX_MEMBS:
			while (--z >= 0 && !pmbad)
				pmdbg(pmbyte());
			return;
		case DX_NAME:
			pmscpy(name, NCSYMB);
			return;
		default:
			if (n > DT_VOID)
				pmbad = 1;
			return;
		}
	}
}

/* Copy the records up to and including EPILOG.  Returns 0 if it cannot. */
static
pmfunc()
{
	register int	op, n;
	ival_t		ofs, mask;
	char		name[NCSYMB];

	pmlen = 1;
	while (!pmbad) {
		op = pmbyte();
		switch (op) {
		case LINE:
		case LLABEL:
		case JUMP:
			pmicpy();
			break;
		case DLABEL:
			pmdbg(pmbyte());
			break;
		case MNAME:
		case FNAME:
		case GLABEL:
		case SLABEL:
			pmscpy(name, NCSYMB);
			break;
		case COMM:
			pmscpy(name, NCSYMB);
			pmzcpy();
			break;
		case BLOCK:
			pmzcpy();
			break;
		case ENTER:
		case ALIGN:
			pmbyte();
			break;
		case AUTOS:
			ofs = pmival();
			mask = pmival();
			pmputi(ofs);
			pmputi((ival_t)(mask | pmpro));
			pmtop = ofs;
			pmmask |= (PREGSET)(uival_t)mask;
			++pmnauto;
			break;
		case IBLOCK:
			for (n = pmbyte(); n > 0 && !pmbad; --n)
				pmbyte();
			break;
		case FEXPR:
		case TEXPR:
			pmicpy();
			/* fall through */
		case EEXPR:
		case IEXPR:
		case REXPR:
		case SEXPR:
			pmtree(-1);
			break;
		case SBODY:
			pmicpy();
			for (n = 2*pmicpy(); n > 0 && !pmbad; --n)
				pmicpy();
			break;
		case LSBODY:
			pmicpy();
			n = pmicpy();
			pmbyte();
			for (; n > 0 && !pmbad; --n) {
				pmzcpy();
				pmicpy();
			}
			break;
		case EPILOG:
			return (!pmbad);
		default:
			return (0);
		}
	}
	return (0);
}

/* Take a free register, or an even-aligned pair, from R6..R12. */
static
pmreg(pair)
{
	register int	r;

	if (pair) {
		for (r = R10; r >= R6; r -= 2)
			if ((pmmask & (BREG(r)|BREG(r+1))) == 0) {
				pmmask |= BREG(r) | BREG(r+1);
				return (RR0 + (r >> 1));
			}
	} else {
		for (r = R12; r >= R6; --r)
			if ((pmmask & BREG(r)) == 0) {
				pmmask |= BREG(r);
				return (r);
			}
	}
	return (-1);
}

static
pmcmp(a, b)
PMSLOT	*a, *b;
{
	return (a->pm_offs < b->pm_offs ? 1 : a->pm_offs > b->pm_offs ? -1 : 0);
}

/* Give registers to the most used candidates.  Returns the number given. */
static
pmpick()
{
	register PMSLOT	*sp, *best;
	register int	i, n, r;
	PREGSET		was, held;

	shellsort((char *)pmslot, npmslot, sizeof(PMSLOT), &pmcmp);
	n = 0;
	for (i = 0, sp = pmslot; i < npmslot; ++i, ++sp) {
		if (sp->pm_offs < -(lval_t)pmtop || sp->pm_offs >= 0
		 || sp->pm_kind == 0 || sp->pm_vol)
			continue;
		if (n++ >= NPCAND)
			sp->pm_esc = 1;
	}
	was = pmmask;
	/* Keep one aligned pair free: a far pointer live across a call needs
	 * a callee-saved pair, and so does its spill. */
	held = 0;
	if ((r = pmreg(1)) >= 0)
		held = BREG(2*(r-RR0)) | BREG(2*(r-RR0)+1);
	n = 0;
	for (;;) {
		best = NULL;
		for (i = 0, sp = pmslot; i < npmslot; ++i, ++sp) {
			if (sp->pm_offs < -(lval_t)pmtop || sp->pm_offs >= 0
			 || sp->pm_kind == 0 || sp->pm_vol || sp->pm_esc
			 || sp->pm_reg >= 0)
				continue;
			if (best == NULL || sp->pm_uses > best->pm_uses)
				best = sp;
		}
		if (best == NULL
		 || (best->pm_reg = pmreg(best->pm_kind == PPAIR)) < 0)
			break;
		++n;
	}
	pmpro = pmmask & ~held & ~was;
	return (n);
}

/* On PROLOG: decide, and if anything is promoted, switch to a rewritten copy. */
promote()
{
	long	start;

	if (isvariant(VDEBUG) || ifp == NULL || (start = ftell(ifp)) < 0)
		return;
	pmout = NULL;
	pmbad = pmsetjmp = pmnauto = npmslot = 0;
	pmtop = 0;
	pmmask = NOFREE;
	pmpro = 0;
	if (pmfunc() && pmlen <= PMAXLEN && pmnauto != 0 && !pmsetjmp
	 && pmpick() != 0) {
		/* The rewrite is never longer than the original.  Failing here
		 * rather than skipping keeps the output independent of the heap. */
		if ((pmbuf = (unsigned char *)malloc((unsigned)(pmlen-1))) == NULL)
			cnomem("promote");
		fseek(ifp, start, 0);
		pmout = pmbuf;
		pmend = pmbuf + (unsigned)(pmlen-1);
		if (pmfunc()) {
			ibufp = pmbuf;
			ibufend = pmout;
			pmout = NULL;
			return;
		}
		pmout = NULL;
		free((char *)pmbuf);
		pmbuf = NULL;
	}
	fseek(ifp, start, 0);
}

/* Function prolog: clear the max auto / temp watermarks. */
doprolog()
{
	blkflab = 0;
	maxauto = 0;
	basauto = 0;
	mdtcoded = 1;
	maxtemp = 0;
	maxregbusy = 0;
	retreg = -1;
	promote();
}

/* Just before EPILOG: emit one AUTOS record telling cc2 the temp space and the
 * callee-saved register set used anywhere in the function (so cc2 can save/restore
 * it).  cc0's per-block cmask grows and shrinks; the UNION is what must be saved. */
doepilog()
{
	if (pmbuf != NULL) {		/* back from the rewritten copy */
		ibufp = NULL;
		free((char *)pmbuf);
		pmbuf = NULL;
	}
	bput(AUTOS);
	iput(maxtemp);
	iput((ival_t)maxregbusy);
}

/* Read a new auto/register allocation item (auto size + register-busy mask). */
doautos()
{
	basauto = maxauto = iget();
	mdtcoded = 1;
	regbusy = iget();
	maxregbusy |= regbusy;
}

/*
 * Unconditional jump.  The jump that ends a return statement names a cc0
 * label, below the labels cc1 made while coding the value.  Before it, tell
 * cc2 which registers the epilogue returns: ZRETV reads them and emits no code.
 */
genubr(n)
{
	register int	r;

	if (retreg >= 0 && n < retlab) {
		for (r = R0; r <= R3; ++r)
			if ((reg[retreg].r_phys & BREG(r)) != 0) {
				bput(CODE);
				bput(ZRETV);
				iput(A_WR|r);
			}
		retreg = -1;
	}
	genl(ZJP, n);
}

/*
 * Conditional jump. The Z8000 has ONE conditional jump (ZJP) + a 4-bit cc;
 * the optab relation row holds the CC_* code. Emit ZJP, the cc as an immediate
 * operand, then the target label (n2 encodes JP cc,target).
 */
gencbr(c, n)
{
	/* optab[rel][0] is the per-condition relative-jump opcode ZJREL|cc; emit it
	 * with the target label, exactly like an unconditional jump. n2 maps the
	 * 0xD0..0xDF opcode range to JR cc. Matches the table [REL0] mechanism. */
	genl(optab[c-MIOBASE][0], n);
}

/*
 * Switch compilation.  The MI (code.c) evaluates the switch expression into
 * SWREG.  A compare chain costs 6 bytes and 13 cycles per case passed.  A table
 * dispatch costs 18 bytes and 58 cycles, plus 4 bytes and 7 cycles to rebase a
 * nonzero low case, plus a word per value in the range:
 *
 *	SUB	R0,#lo
 *	CP	R0,#hi-lo
 *	JR	UGT,default
 *	ADD	R0,R0
 *	LDAR	RR2,table
 *	ADD	R3,R0		RR2 -> the value's entry
 *	ADD	R3,@RR2		entry holds case - entry
 *	JP	@RR2
 * table:	.word	case-.	...	one per value, default for gaps
 *
 * The table is used only when it is smaller than the chain and faster than
 * the chain's average case.  It needs no relocation, so it holds in any text
 * segment and in shared code.
 */
genswitch(def, n)
{
	register int i;
	register ival_t l;
	long lo, span, tsize, tcyc;
	int tab;

	if (n > 0) {
		lo = cases[0].c_val;
		if (lo > 0 && lo <= 2)
			lo = 0;			/* two default words beat a SUB */
		span = (long)cases[n-1].c_val - lo;
		tsize = 18 + 2*(span+1) + (lo != 0 ? 4 : 0);
		tcyc = 58 + (lo != 0 ? 7 : 0);
		if (tsize < 6L*n + 2 && 2*tcyc < 13L*(n+1)) {
			if (lo != 0)
				genri(ZSUB, A_WR|SWREG, (ival_t)lo);
			genri(ZCP, A_WR|SWREG, (ival_t)span);
			gencbr(UGT, def);
			genrr(ZADD, A_WR|SWREG, A_WR|SWREG);
			tab = newlab();
			bput(CODE);
			bput(ZLDAR);
			iput(A_WR|R2);
			iput(A_LID|A_DIR);
			iput(tab);
			genrr(ZADD, A_WR|R3, A_WR|SWREG);
			genrr(ZADD, A_WR|R3, A_IR|R2);
			genr(ZJP, A_IR|R2);
			genlab(tab);
			for (i = 0; i < n; ++i) {
				while (lo < cases[i].c_val) {
					genl(ZSWREL, def);
					++lo;
				}
				genl(ZSWREL, cases[i].c_lab);
				++lo;
			}
			return;
		}
	}
	for (i = 0; i < n; ++i) {
		l = cases[i].c_val;
		if (l == 0)
			genrr(ZOR, A_WR|SWREG, A_WR|SWREG);	/* OR SWREG,SWREG -- Z if 0 */
		else
			genri(ZCP, A_WR|SWREG, l);		/* CP SWREG,#l */
		gencbr(EQ, cases[i].c_lab);
	}
	genubr(def);
}

/*
 * A long switch, its value in RR0 and its cases sorted, signed or 'uns'
 * unsigned.  A dense range dispatches through the same table as genswitch,
 * indexed by R1 once the rebased value is known to be in range:
 *
 *	SUBL	RR0,#lo
 *	CPL	RR0,#hi-lo
 *	JR	UGT,default
 *	ADD	R1,R1	...	as genswitch, with R1 for R0
 *
 * 26 bytes, 6 more to rebase, and a word per value.  A case otherwise costs a
 * CPL and a JR, 8 bytes, and the table is taken only when it is smaller.  The
 * compares are a binary search: CPL against the middle case, JR EQ to it and
 * JR LT (ULT) to the lower half, down to runs of four compared in turn.
 */
genlswitch(def, n, uns)
{
	register int i;
	lval_t lo, span;
	int tab;

	if (n > 0) {
		lo = lcases[0].c_val;
		span = (ulval_t)lcases[n-1].c_val - (ulval_t)lo;
		if ((ulval_t)span < 0x4000
		 && 26 + 2*(span+1) + (lo != 0 ? 6 : 0) < 8L*n + 2) {
			if (lo != 0)
				genril(ZSUBL, A_WR|R0, lo);
			genril(ZCPL, A_WR|R0, span);
			gencbr(UGT, def);
			genrr(ZADD, A_WR|R1, A_WR|R1);
			tab = newlab();
			bput(CODE);
			bput(ZLDAR);
			iput(A_WR|R2);
			iput(A_LID|A_DIR);
			iput(tab);
			genrr(ZADD, A_WR|R3, A_WR|R1);
			genrr(ZADD, A_WR|R3, A_IR|R2);
			genr(ZJP, A_IR|R2);
			genlab(tab);
			for (i = 0; i < n; ++i) {
				while (lo != lcases[i].c_val) {
					genl(ZSWREL, def);
					++lo;
				}
				genl(ZSWREL, lcases[i].c_lab);
				++lo;
			}
			return;
		}
	}
	genlsearch(0, n, def, uns);
}

/* Search lcases[lo..hi-1] for the value in RR0, else go to 'def'. */
genlsearch(lo, hi, def, uns)
{
	register int i, mid;
	int l;

	while (hi - lo > 4) {
		mid = (lo + hi) / 2;
		genril(ZCPL, A_WR|R0, lcases[mid].c_val);
		gencbr(EQ, lcases[mid].c_lab);
		l = newlab();
		gencbr(uns ? ULT : LT, l);
		genlsearch(mid+1, hi, def, uns);
		genlab(l);
		hi = mid;
	}
	for (i = lo; i < hi; ++i) {
		genril(ZCPL, A_WR|R0, lcases[i].c_val);
		gencbr(EQ, lcases[i].c_lab);
	}
	genubr(def);
}

/*
 * Dump a tree to stderr, under Z1DBG, for the "collect" botch below.
 *
 * This prints cc1's IN-MEMORY tree at the moment addressing-mode collection
 * fails, which is state no dump of the intermediate FILES can show: t_reg is an
 * allocation the selector just made, and t_flag/t_seg are annotations the
 * modify phase added.  cc3 prints the trees cc1 read and the CODE records it
 * wrote -- the two sides of this failure, not the failure itself -- and the
 * donor's own tool for the middle, snapf/-S, is compiled out (mch.h TINY=1)
 * until snapf is host-ported to stdarg.  So this stays, and it stays HERE:
 * addressing-mode collection is machine-dependent, and so is the diagnostic.
 */
static
dbgtree(tp, d)
TREE *tp;
{
	int i;

	if (tp == NULL)
		return;
	for (i = 0; i < d; i++)
		fprintf(stderr, "  ");
	fprintf(stderr, "op=%d type=%d size=%d flag=%x seg=%d ival=%ld reg=%d offs=%ld\n",
		tp->t_op, tp->t_type, tp->t_size, tp->t_flag, tp->t_seg,
		(long)tp->t_ival, tp->t_reg, (long)tp->t_offs);
	if (tp->t_op == LEAF || tp->t_op > 19) {
		dbgtree(tp->t_lp, d+1);
		if (tp->t_op != LEAF)
			dbgtree(tp->t_rp, d+1);
	}
}

/*
 * Output an address. 'tp' is the (address) tree; 'nsef' suppresses side-effect
 * escapes (LDA); 'pfx[npfx]' holds HI/LO half-selector prefixes.
 */
genadr(tp, nsef, npfx, pfx)
register TREE	*tp;
unsigned char	pfx[];
{
	register int	op;
	register int	bias;
	register int	memf;
	register int	byte;
	register int	reg;
	register ival_t	ival;
	int		mode;
	int		offs;
	lval_t		loffs;
	int		lidn;
	SYM		*gidp;

	static	char	basebias[] = {
		0,	0,		/* S8,   U8,    */
		1,	1,		/* S16,  U16,   */
		2,	2,		/* S32,  U32,   */
		2,	4,		/* F32,  F64,   */
		0,			/* BLK,         */
		0,	1,		/* FLD8, FLD16, */
		2,	2,		/* LPTR, LPTB,  */
		1,	1		/* SPTR, SPTB   */
	};

	mdtcoded = 1;
	while ((op = tp->t_op) == LEAF)
		tp = tp->t_lp;
	/* A register node: apply HI/LO half selectors, emit its addressing mode. */
	if (op == REG && (reg = tp->t_reg) != FPAC) {
		while (npfx--) {
			if (pfx[npfx] == M_LO)
				reg = lohalf(reg);
			else
				reg = hihalf(reg);
		}
		iput(ramode[reg]);
		return;
	}
	/* Constants/memory: HI/LO dial out the selected word; compute byte offset. */
	offs = 0;
	if (npfx) {
		memf = 0;
		if (op != ICON && op != LCON && op != DCON)
			++memf;
		bias = basebias[tp->t_type];
		while (npfx--) {
			byte = pfx[npfx];
			if (memf && bias == 2) {
				/* Z8000 is BIG-ENDIAN: a multi-word value in memory keeps
				 * its HIGH word at the base (lower address) and its LOW
				 * word at +2. (The i8086 donor was little-endian: HI@+2.) */
				if (byte == M_LO)
					offs += 2;
			} else if (byte == M_LO)
				offs += bias;
			bias >>= 1;
		}
	}
	if (op == DCON) {
		ival  = tp->t_dval[7-offs] & 0377;
		ival |= tp->t_dval[6-offs] << 8;
		iput(A_OFFS|A_IMM);
		iput(ival);
		return;
	}
	if (op == LCON) {
		if (npfx == 0) {	/* whole long: 32-bit immediate, high word then low */
			iput(A_OFFS|A_IMML);
			iput(upper(tp->t_lval));
			iput(lower(tp->t_lval));
			return;
		}
		ival = lower(tp->t_lval);
		if (offs == 0)
			ival = upper(tp->t_lval);
		iput(A_OFFS|A_IMM);
		iput(ival);
		return;
	}
	if (op == ICON) {
		ival = tp->t_ival;
		iput(A_OFFS|A_IMM);
		iput(ival);
		return;
	}
	/* General memory address: collect the addressing mode. */
	mode = A_DIR;
	loffs = offs;
	if (gencoll(tp, &mode, &loffs, &lidn, &gidp, 0, nsef) == 0) {
		if (getenv("Z1DBG")) {
			fprintf(stderr, "collect failed on:\n");
			dbgtree(tp, 0);
		}
		cbotch("collect");
	}
	if ((mode&A_AMOD) == A_IMM || nsef != 0)
		mode &= ~A_PREFX;
	if ((mode&A_AMOD) == A_IMM)
		mode &= ~A_VOL;			/* an address taken, not an access */
	/*
	 * A symbol-relative offset is two words, high then low: the full signed
	 * 32-bit displacement from the symbol (getfield reads it back the same
	 * way).  A bare offset (frame slot, register displacement) is one
	 * signed word.
	 */
	if ((mode&(A_LID|A_GID)) != 0) {
		if (loffs == 0)
			iput(mode);
		else {
			iput(mode|A_OFFS);
			iput(upper(loffs));
			iput(lower(loffs));
		}
	} else {
		offs = loffs;
		if (offs == 0)
			iput(mode);
		else {
			iput(mode|A_OFFS);
			iput(offs);
		}
	}
	if ((mode&A_LID) != 0)
		iput(lidn);
	else if ((mode&A_GID) != 0)
		sput(gidp->s_id);
}

/*
 * Walk an address tree, building up the addressing mode, offset and symbol base.
 * Caller sets *modep = A_DIR and *offsp = 0. 's' negates (under SUB); 'f' marks
 * a real indirection (STAR) so an address is not turned into an immediate.
 */
gencoll(tp, modep, offsp, lidnp, gidpp, s, f)
TREE	*tp;
int	*modep;
lval_t	*offsp;
int	*lidnp;
SYM	**gidpp;
{
	register int	op;
	register lval_t	offs;
	register int	seg;
	register int	r;

	while ((op = tp->t_op) == LEAF)
		tp = tp->t_lp;
	if (tp->t_vol)
		*modep |= A_VOL;
	switch (op) {

	case ADDR:
		if (gencoll(tp->t_lp, modep, offsp, lidnp, gidpp, s, f) == 0)
			return (0);
		if (f == 0) {
			*modep &= ~A_AMOD;
			*modep |=  A_IMM;
		}
		break;

	case STAR:
		if (gencoll(tp->t_lp, modep, offsp, lidnp, gidpp, s, 1) == 0)
			return (0);
		break;

	case ADD:
	case SUB:
		if (gencoll(tp->t_lp, modep, offsp, lidnp, gidpp, s, f) == 0)
			return (0);
		if (op == SUB)
			s = !s;
		if (gencoll(tp->t_rp, modep, offsp, lidnp, gidpp, s, f) == 0)
			return (0);
		break;

	case ICON:
	case LCON:
		offs = grabnval(tp);
		if (s != 0)
			offs = -offs;
		*offsp += offs;
		break;

	case LID:
		if ((*modep&(A_GID|A_LID)) != 0 || s != 0)
			return (0);
		*modep |= A_LID;
		*lidnp  = tp->t_label;
		goto lidgid;

	case GID:
		if ((*modep&(A_GID|A_LID)) != 0 || s != 0)
			return (0);
		*modep |= A_GID;
		*gidpp  = tp->t_sp;
	lidgid:
		*offsp += tp->t_offs;
		/* Code-space symbols get the code-space flag (vs data space).
		 * `readonly' data (SPURE) is in the data image (.shrd). */
		seg = tp->t_seg;
		if (seg == SCODE || seg == SLINK
		|| (isvariant(VLARGE)
		   && (seg == SSTRN && isvariant(VROM)))) {
			*modep &= ~A_PREFX;
			*modep |=  A_CS;
		}
		break;

	case REG:
		if ((*modep&A_AMOD) != A_DIR || s != 0)
			return (0);
		r = tp->t_reg;
		/* A far pointer held in a register PAIR (RR0..RR14): @RRn indirect
		 * (segmented seg:offset deref). The encoding names the pair by its
		 * even register = hihalf(r). */
		if (r >= RR0 && r <= RR14) {
			*modep = (*modep & ~A_AMOD) | A_IR | hihalf(r);
			break;
		}
		/* A single base register R1..R15 -> indexed addressing (R0 can't index). */
		if (r == R0 || r > R15)
			return (0);
		*modep = (*modep & ~A_AMOD) | A_X | r;
		break;

	default:
		return (0);
	}
	return (1);
}

/* ---- instruction-emission primitives (write CODE records to the IR) ---- */

/* op + one operand. */
genr(op, r)
{
	bput(CODE);
	bput(op);
	iput(r);
}

/* op + two operands. */
genrr(op, r1, r2)
{
	bput(CODE);
	bput(op);
	iput(r1);
	iput(r2);
}

/* op + register + immediate. */
genri(op, r, i)
{
	bput(CODE);
	bput(op);
	iput(r);
	iput(A_OFFS|A_IMM);
	iput(i);
}

/* op + register pair + 32-bit immediate. */
genril(op, r, l)
lval_t	l;
{
	bput(CODE);
	bput(op);
	iput(r);
	iput(A_OFFS|A_IMML);
	iput(upper(l));
	iput(lower(l));
}

/* op + local label. */
genl(op, l)
{
	bput(CODE);
	bput(op);
	iput(A_LID|A_DIR);
	iput(l);
}

/* op + global identifier. */
geng(op, g)
char	*g;
{
	bput(CODE);
	bput(op);
	iput(A_GID|A_DIR);
	sput(g);
}

/* op + immediate. */
geni(op, i)
{
	bput(CODE);
	bput(op);
	iput(A_OFFS|A_IMM);
	iput(i);
}

/* end of n1/z8001/gen1.c */
