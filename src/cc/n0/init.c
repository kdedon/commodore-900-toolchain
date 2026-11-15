/*
 * n0/init.c
 * C compiler.
 * Initializers.
 * All storage classes.
 */

#ifdef   vax
#include "INC$LIB:cc0.h"
#else
#include "cc0.h"
#endif

/*
 * An automatic structure's initializer read before its members were known
 * to take it: a member that is not a structure takes it as its first item.
 */
static	TREE	*itp;

/*
 * An automatic aggregate's items and line records are kept, in order, until
 * its initializer has been read: an array sized by its initializer is bound
 * only then, and the members the initializer leaves out are zeroed, as a
 * static's are, which may be done by clearing the whole object first.  An
 * item records the member it initializes; the symbol is iflexp's.  A gap is a
 * run of members left out, merged with the gap before it when no item lies
 * between them.
 */
SYM	*iflexp;
typedef	struct	{
	TREE	*f_tp;			/* Value, or NULL for a line record or gap */
	DIM	*f_dp;			/* Item's dimensions */
	INFO	*f_ip;			/* Item's info */
	sizeof_t f_bo;			/* Byte offset, or the line */
	sizeof_t f_n;			/* Gap's size, or 0 */
	char	f_type;			/* Item's type */
	char	f_flag;			/* Item's volatility */
	char	f_self;			/* Item is the array's own symbol */
}	IFLEX;
static	IFLEX	*iflist;
static	int	nflex, maxflex;
static	int	lastgap, ngap;
static	IFLEX	*iflex1();
static	int	inewtree();
static	INFO	zinfo;
static	int	igap(), ikeep(), izitem(), iwhole(), izero();
extern	sizeof_t zcost();

init(sp, dp, bo, flex)
register SYM	*sp;
register DIM	*dp;
sizeof_t	bo;
int		flex;
{
	register int	t;
	DIM		*ndp;
	TREE		*tp;
	sizeof_t	width, nbe, nel, ninit, bo0;
	int		brace, c, adj, own;

	bo0 = bo;
	t  = sp->s_type;
	width = sdsize(sp, dp);
	ndp = dp;
	if (dp!=NULL && dp->d_type==D_ARRAY) {
		if (dp->d_bound != 0)
			flex = 0;
		ndp = dp->d_dp;
		if (width==0 && !flex)
			cerror("array row has 0 length");
	} else
		flex = 0;
	nel = 0;
	nbe = sdsize(sp, ndp);
	if (nbe != 0)
		nel = width/nbe;
	own = 0;
	if (dp==NULL && istruct(t) && isauto(sp) && itp==NULL
	 && s!=LBRACE && s!=RBRACE && s!=STRING) {
		++own;
		inewtree();
		++ininit;
		itp = expr();
		--ininit;
		if (tltype(itp)==T_STRUCT && itp->t_ip==sp->s_ip) {
			stdok(STD_C89, "a structure initialized by an expression");
			icollect(itp, bo, sp, NULL);
			itp = NULL;
			return;
		}
	}
	brace = 0;
	if (s==LBRACE && (dp!=NULL || !istruct(t))) {
		++brace;
		lex();
	} else if (s!=LBRACE && (dp!=NULL || istruct(t)))
		notbook();
	ninit = 0;
	while (s != RBRACE || itp != NULL) {
		if (ndp==NULL && istruct(t)) {
			if (dp!=NULL && isauto(sp))
				init(sp, (DIM *)NULL, bo, 0);	/* may be whole */
			else
				sinit(sp, bo);
		}
		else if (ndp!=NULL && ndp->d_type==D_ARRAY)
			init(sp, ndp, bo, 0);
		else if (itp != NULL) {
			icollect(itp, bo, sp, ndp);
			itp = NULL;
		} else {
			adj = 0;
			if (s==STRING && t<T_INT && ndp==NULL) {
again:
				instring = '"';
				while ((c = getmap('\"')) >= 0) {
					inewtree();
					icollect(bicon((ival_t)c), bo, sp, ndp);
					++ninit;
					++bo;
				}
				instring = 0;
				if (lex() == STRING) {
					++adj;
					goto again;
				}
				if (adj)
					notbook();
				if (!flex && ninit==nel) {
					cwarn("string initializer not terminated by NUL");
					break;
				}
				inewtree();
				icollect(bicon((ival_t)0), bo, sp, ndp);
				++ninit;
				break;
			}
			inewtree();
			++ininit;
			tp = expr();
			--ininit;
			icollect(tp, bo, sp, ndp);
		}
		++ninit;
		bo += nbe;
		if (s != COMMA)
			break;
		if (ninit>=nel && !flex) {
			if (brace) {
				lex();
				if (s == RBRACE)
					cwarn("trailing ',' in initialization list");
				else {
					cerror("too many initializers");
					iskip();
				}
			}
			break;
		}
		itrail();
	}
	if (own)
		itp = NULL;
	if (brace)
		mustbe(RBRACE);
	if (ninit < nel) {
		c = sp->s_class;
		if (c==C_GDEF || c==C_SIN || c==C_SEX) {
			bput(BLOCK);
			zput(nbe*(nel-ninit));
		} else if (iflexp != NULL)
			igap(bo0 + nbe*ninit, nbe*(nel-ninit));
	}
	if (ninit > nel) {
		if (!flex)
			cerror("too many initializers");
		if (dp != NULL)
			dp->d_bound = ninit;
	}
}

/*
 * Initialize a structure.
 * Create a fake variable for each member;
 * this is necessary for the call to build() in iassign()
 * to do the correct things.
 */
sinit(sp, bo) SYM *sp; sizeof_t bo;
{
	register SYM	*mp;
	register INFO	*ip;
	int		n, brace, c, t, f, bfflag;
	sizeof_t	mo, lo, hi;
	SYM		sym;

	c = sp->s_class;
	t = sp->s_type;
	if (t==T_UNION || t==T_FUNION)
		cerror("cannot initialize unions");
	if (t==T_FSTRUCT || t==T_FUNION)
		return;
	ip = sp->s_ip;
	sym.s_class = c;
	sym.s_value = sp->s_value;
	sym.s_flag = sp->s_flag & S_VOLAT;
	brace = 0;
	if (s == LBRACE) {
		++brace;
		lex();
	}
	lo = hi = n = f = 0;
	while (s != RBRACE || itp != NULL) {
		bfflag = 0;
		if (n >= ip->i_nsp) {
			if (f == 0) {
				cerror("too many structure initializers");
				++f;
			}
			sym.s_type = T_INT;
			sym.s_dp = sym.s_ip = NULL;
			mo = 0;
		} else {
			mp = ip->i_sp[n++];
			sym.s_type = mp->s_type;
			sym.s_dp   = mp->s_dp;
			sym.s_ip   = mp->s_ip;
			sym.s_flag = (sp->s_flag | mp->s_flag) & S_VOLAT;
			mo = mp->s_value;
			if (!isauto(&sym) && lo!=mo) {
				/* Output BLOCK item for padding. */
				bput(BLOCK);
				zput(mo-lo);
				lo = mo;
			}
			if (mp->s_width != 0)		/* bitfield initializer */
				bfflag = bfinit(&sym, mp, ip, &n, bo+mo);
		}
		if (!bfflag)
			init(&sym, sym.s_dp, bo+mo, 0);
		lo += ssize(&sym);
		if (mo + ssize(&sym) > hi)
			hi = mo + ssize(&sym);
		if (bfflag != 2 && s != COMMA)
			break;
		if (n >= ip->i_nsp && !brace)
			break;
		if (bfflag != 2)
			itrail();	/* skip COMMA, check for RBRACE */
	}
	if (brace)
		mustbe(RBRACE);
	if (t==T_STRUCT && (c==C_GDEF || c==C_SIN || c==C_SEX)) {
		if ((mo = ip->i_size-lo) > 0) {
			bput(BLOCK);
			zput(mo);
		}
	} else if (iflexp != NULL) {
		while (n < ip->i_nsp && ip->i_sp[n]->s_value < hi)
			++n;
		if (n < ip->i_nsp) {
			mo = ip->i_sp[n]->s_value;
			igap(bo+mo, ip->i_size-mo);
		}
	}
}

/*
 * Fetch the next symbol.
 * The current symbol is a COMMA.
 * If the new symbol is '}', the program has said ", }"; this is legal.
 * If you pull the comments here, it becomes not quite so legal.
 */
static
itrail()
{
	lex();
	if (s == RBRACE)
		cwarn("trailing ',' in initialization list");
}

/*
 * An initialization starting with '{' contains too many initializers.
 * Skip initializers to the matching '}' or EOF.
 */
static
iskip()
{
	register int braces;

	braces = 0;
	for(;;) {
		if (s == LBRACE)
			++braces;
		else if (s == RBRACE) {
			if (braces == 0)
				return;
			else
				--braces;
		}
		else if (s == EOF)
			return;
		lex();
	}
}

/*
 * Return true if symbol "sp" is an automatic,
 * in the sense that an assigment statement must be generated
 * for the initialization item.
 * Registers are considered auto.
 */
int
isauto(sp) register SYM *sp;
{
	register int c;

	c = sp->s_class;
	return (c==C_AUTO || c==C_PAUTO || c==C_REG);
}

/*
 * This routine actually performs the initialization.
 * Either an build an assignment node and evaluate it for effect,
 * or output an initialization tree.
 */
icollect(tp, bo, sp, dp)
register TREE	*tp;
sizeof_t	bo;
register SYM	*sp;
DIM		*dp;
{
	register IFLEX	*ip;
	register TREE	*xp;

	if (isauto(sp)) {
		if (iflexp != NULL) {
			lastgap = -1;
			ip = iflex1(tp, (sizeof_t)bo);
			ip->f_dp = dp;
			ip->f_ip = sp->s_ip;
			ip->f_type = sp->s_type;
			ip->f_flag = sp->s_flag;
			ip->f_self = sp == iflexp;
		} else
			iassign(sp, dp, bo, tp);
		return;
	}
	xp = talloc();
	xp->t_op = INIT;
	xp->t_type = sp->s_type;
	xp->t_dp = dp;
	xp->t_ip = sp->s_ip;
	xp->t_lp = tp;
	tput(IEXPR, 0, xp);
}

/*
 * Actually do the assignment for an automatic initialization thing.
 */
iassign(sp, dp, bo, tp)
register SYM	*sp;
register TREE	*tp;
sizeof_t	bo;
DIM		*dp;
{
	register TREE	*ip;
	DIM		*ssdp;

	ssdp = sp->s_dp;
	sp->s_dp = dp;
	ip = bid(sp);
	sp->s_dp = ssdp;
	if (sp->s_class != C_REG)
		ip->t_offs += bo;
	tp = build(ASSIGN, ip, tp);
	tput(EEXPR, 0, tp);
}

/*
 * Collect one or more bitfield initializers.
 * Each bitfield initializer must be an integer constant.
 * Multiple bitfield initializers get output as a single initialization item:
 * look for more initializers if the next
 * structure member is another bitfield at the same offset (s_value).
 * This may or may not need to look ahead to the next initializer,
 * so it returns 1 if it has not read COMMA, 2 if it has read the COMMA.
 */
int
bfinit(sp, mp, ip, np, off) SYM *sp; register SYM *mp; INFO *ip; register int *np; sizeof_t off;
{
	register unsigned long val, mval, mask;
	int status;

	for (val = (unsigned long)0; ; ) {

		status = 1;			/* COMMA not read yet */

		/* Widen the initialized symbol base type if necessary. */
		if (ssize(sp) < ssize(mp))
			sp->s_type = mp->s_type;

		/* Grab the initializer value. */
		if (itp != NULL) {
			mval = iconval(itp);
			itp = NULL;
		} else {
			++ininit;
			mval = iconexpr();
			--ininit;
		}

		/* Make sure the initializer is appropriate. */
		mask = (((unsigned long)1) << mp->s_width) - 1;
		if ((mval & ~mask) != (unsigned long)0 && (mval & ~mask) != ~mask)
			cwarn("bitfield initializer out of range");
		mval &= mask;			/* mask value to bitfield width */

		/* Build up the initializer in val. */
		val |= (mval << mp->s_offset);	/* put value in the right place */

		/* Check whether more bitfield initializers follow. */
		if (s != COMMA)			/* no more initializers */
			break;
		itrail();			/* skip COMMA */
		++status;			/* COMMA has been read */
		if (s == LBRACE || s == RBRACE	/* { or }, no more bitfield inits */
		 || *np >= ip->i_nsp		/* no more members */
		 || ip->i_sp[*np]->s_width==0	/* next not a bitfield */
		 || ip->i_sp[*np]->s_value != mp->s_value)	/* next at different value */
			break;
		mp = ip->i_sp[(*np)++];		/* repeat for next bitfield */
	}

	/*
	 * Output the bitfield initializer built up in val.
	 * FIX_ME The initializer value collected in unsigned long 'val'
	 * is passed to icollect() as bicon((ival_t)val),
	 * this does not seem not quite right.
	 */
	icollect(bicon((ival_t)val), off, sp, NULL);
	return status;
}

/*
 * Reset the tree space for the next initializer item, unless the items
 * are being kept for an automatic array sized by its initializer.
 */
static int
inewtree()
{
	if (iflexp == NULL)
		newtree(sizeof(TREE));
}

/*
 * Keep one more item: value 'tp' at offset 'bo', or a line record.
 */
static IFLEX *
iflex1(tp, bo)
TREE	*tp;
sizeof_t bo;
{
	register IFLEX	*ip;

	if (nflex == maxflex) {
		maxflex = maxflex ? 2*maxflex : 16;
		iflist = (IFLEX *)(iflist ? realloc((char *)iflist, maxflex*sizeof(IFLEX))
					  : malloc(maxflex*sizeof(IFLEX)));
		if (iflist == NULL)
			cfatal("out of space in initializer");
	}
	ip = &iflist[nflex++];
	ip->f_tp = tp;
	ip->f_bo = bo;
	ip->f_n = 0;
	return ip;
}

/*
 * Keep a gap: 'n' bytes at 'bo' that no item initializes.
 */
static
igap(bo, n)
sizeof_t bo, n;
{
	register IFLEX	*ip;

	if (n <= 0)
		return;
	if (lastgap >= 0) {
		ip = &iflist[lastgap];
		ip->f_n = bo + n - ip->f_bo;
		return;
	}
	lastgap = nflex;
	iflex1((TREE *)NULL, bo)->f_n = n;
	++ngap;
}

/*
 * Keep the line record expr() would write.
 */
iline()
{
	iflex1((TREE *)NULL, (sizeof_t)line);
}

/*
 * Initialize automatic array 'sp', whose bound is the number of items in
 * its initializer.
 */
iflex(sp)
SYM	*sp;
{
	stdok(STD_C89, "an automatic array sized by its initializer");
	ikeep(sp, 1);
}

/*
 * Initialize automatic 'sp', which is bound.
 */
iauto(sp)
register SYM	*sp;
{
	register DIM	*dp;

	if ((dp = sp->s_dp) != NULL ? dp->d_type == D_ARRAY
	    : sp->s_type == T_STRUCT || sp->s_type == T_UNION)
		ikeep(sp, 0);
	else
		init(sp, dp, (sizeof_t)0, 0);
}

/*
 * Initialize automatic aggregate 'sp': read the initializer, keeping its
 * items, bind the array if it is sized by them, then write what
 * `T a[n] = ...' writes, in the order it writes it, with the gaps zeroed.
 * When clearing the whole object first is the shorter code, the clear comes
 * first and the items storing a constant 0 are dropped.
 */
static
ikeep(sp, flex)
register SYM	*sp;
{
	register IFLEX	*ip, *ep;
	SYM		sym;
	int		whole;

	newtree(sizeof(TREE));
	iflexp = sp;
	nflex = ngap = 0;
	lastgap = -1;
	init(sp, sp->s_dp, (sizeof_t)0, flex);
	iflexp = NULL;
	if (flex) {
		bindlocal(sp);
		putautos();
	}
	whole = ngap != 0 && iwhole(sp);
	for (ip = iflist, ep = iflist+nflex; ip < ep; ++ip) {
		if (ip->f_tp == NULL && ip->f_n == 0) {
			bput(LINE);
			iput((ival_t)ip->f_bo);
			continue;
		}
		if (whole == 1) {
			izero(sp, (sizeof_t)0, ssize(sp));
			whole = 2;
		}
		if (ip->f_tp == NULL) {
			if (!whole)
				izero(sp, ip->f_bo, ip->f_n);
		} else if (whole && izitem(ip))
			;
		else if (ip->f_self)
			iassign(sp, ip->f_dp, ip->f_bo, ip->f_tp);
		else {
			sym = *sp;
			sym.s_type = ip->f_type;
			sym.s_dp = ip->f_dp;
			sym.s_ip = ip->f_ip;
			sym.s_flag = ip->f_flag;
			iassign(&sym, ip->f_dp, ip->f_bo, ip->f_tp);
		}
	}
}

/*
 * Is the item a constant 0 the clear of the whole object stores already?
 */
static int
izitem(ip)
register IFLEX	*ip;
{
	register TREE	*tp;

	if ((ip->f_flag & S_VOLAT) != 0)
		return 0;
	for (tp = ip->f_tp; tp->t_op == CAST || tp->t_op == CONVERT; tp = tp->t_lp)
		;
	return (tp->t_op == ICON && tp->t_ival == 0)
	    || (tp->t_op == LCON && tp->t_lval == 0);
}

/*
 * Is clearing all of 'sp' and dropping its constant 0 items shorter code
 * than clearing its gaps?  zcost() prices a clear.
 */
static int
iwhole(sp)
register SYM	*sp;
{
	register IFLEX	*ip, *ep;
	sizeof_t	gaps, whole;

	gaps = 0;
	whole = zcost(sp, (sizeof_t)0, ssize(sp));
	for (ip = iflist, ep = iflist+nflex; ip < ep; ++ip) {
		if (ip->f_tp == NULL) {
			if (ip->f_n != 0)
				gaps += zcost(sp, ip->f_bo, ip->f_n);
		} else if (izitem(ip))
			whole -= zcost(sp, ip->f_bo,
				tidsize(ip->f_type, ip->f_ip, ip->f_dp, 0));
	}
	return whole < gaps;
}

/*
 * Zero 'n' bytes at 'bo' in automatic aggregate 'sp': an assignment of the
 * constant 0 to an aggregate of that size, which the code generator does as
 * a clear.
 */
static
izero(sp, bo, n)
SYM		*sp;
sizeof_t	bo, n;
{
	register TREE	*tp;
	SYM		sym;

	zinfo.i_size = n;
	sym = *sp;
	sym.s_type = T_STRUCT;
	sym.s_dp = NULL;
	sym.s_ip = &zinfo;
	tp = talloc();
	tp->t_op = ASSIGN;
	tp->t_type = T_STRUCT;
	tp->t_ip = &zinfo;
	tp->t_lp = bid(&sym);
	tp->t_lp->t_offs += bo;
	tp->t_rp = bicon((ival_t)0);
	tput(EEXPR, 0, tp);
}

/* end of n0/init.c */
