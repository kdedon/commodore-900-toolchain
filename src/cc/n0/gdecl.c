/*
 * n0/gdecl.c
 * Read in declarators and build up the DIM and INFO structures.
 */

#ifdef   vax
#include "INC$LIB:cc0.h"
#else
#include "cc0.h"
#endif

/*
 * Read declarator.
 * The arg "tdp" is the dimensions from a typedef.
 * The storage class is passed since
 * it determines the lexic level of the lookup.
 */
gdecl(asp, adp, tdp, c, ls)
SYM	**asp;
DIM	**adp, *tdp;
int	c, ls;
{
	register SYM	*sp;
	DIM		*dp;
	int		ll;	/* Lexical level */
	int		aok;	/* Args are OK flag */
	sizeof_t	bound;	/* Array bound */
	int		vf;	/* `* volatile' */

	aok = (llex==LL_EXT && (c==C_GDEF || c==C_GREF || c==C_SEX) && nargs==0);
	while (s == CONST || s == VOLATILE) {
		/* Ignore these for now.  They should be treated as MUL */
		/* They can appear before the type-name as well */
		lex();
	}
	if (s == MUL) {
		lex();
		vf = 0;
		for (; s == CONST || s == VOLATILE; lex())
			vf |= s == VOLATILE;
		if (gdecl(asp, adp, NULL, c, ls) == 0)
			return 0;
		if (vf)
			dvol |= ptrdims(*adp, -1) ? S_VTARG : S_VOLAT;
		*adp = tackdim(*adp, D_PTR, (sizeof_t)0);
		while (tdp != NULL) {
			*adp = tackdim(*adp, tdp->d_type, tdp->d_bound);
			tdp = tdp->d_dp;
		}
		return 1;
	}
	if (s == LPAREN) {
		lex();
		if (pdecl != 0 && (s == RPAREN || isproto())) {
			sp = NULL;	/* abstract `(int)': function suffix */
			dp = NULL;
			garglist(&aok, &dp);
			mustbe(RPAREN);
			goto again;
		}
		if (gdecl(asp, adp, NULL, c, ls) == 0)
			return 0;
		mustbe(RPAREN);
		sp = *asp;
		dp = *adp;
		if (nargs != 0 || pansi)
			aok = 0;
	} else if (s == ID) {
		if (c==C_ARG || c==C_PAUTO || c==C_PREG)
			ll = LL_ARG;
		else if (c==C_GDEF || c==C_GREF)
			ll = LL_EXT;
		else
			ll = llex;
		sp = NULL;
		if (pdecl != 2)
			sp = deflookup(ls, ll);
		dp = NULL;
		lex();
	} else if (pdecl != 0 && (s == COMMA || s == RPAREN || s == LBRACK)) {
		sp = NULL;		/* abstract parameter declarator */
		dp = NULL;
	} else {
		cerror("declarator syntax");
		while (s!=EOF && s!=COMMA && s!=SEMI)
			skip();
		return 0;
	}
again:
	if (s == LPAREN) {
		lex();
		garglist(&aok, &dp);
		mustbe(RPAREN);
		goto again;
	}
	if (s == LBRACK) {
		lex();
		bound = 0;
		if (s != RBRACK)
			bound = getbound();
		mustbe(RBRACK);
		dp = tackdim(dp, D_ARRAY, bound);
		goto again;
	}
	while (tdp != NULL) {
		dp = tackdim(dp, tdp->d_type, tdp->d_bound);
		tdp = tdp->d_dp;
	}
	*asp = sp;
	*adp = dp;
	return 1;
}

/*
 * This routine generates tags for tagless struct/union/enum
 * declarations.  This makes life easier for csd.
 */
SYM *newtag(ll) int ll;
{
	sprintf(id, ".%d", newlab());
	setid(id);
	return deflookup(SL_TAG, ll);
}

/*
 * This routine processes structure and union declarations.
 * The type and INFO data gets passed back indirectly through the
 * "call by reference" parameters.
 * The storage class is passed so that local extern structure
 * definitions get entered at the correct (global) lexical level.
 */
gstruct(sc, at, aip)
int	sc, *at;
INFO	**aip;
{
	int	c, dt, i, j, mc, t, tc, w, rf, ls, ll, nbpstrg;
	SYM	*tsp, *msp, *mp;
	DIM	*dp,  **mdp;
	INFO	*ip, *nip;
	TOK	*oidp;
	unsigned long	ofs, max, bitsize;

	ll = (sc == C_GREF) ? LL_EXT : llex;
	ls = lsym;
	if (notvariant(VSINU))
		lsym += 1;
	dt = T_STRUCT;
	tc = C_STAG;
	mc = C_MOS;
	if (s == UNION) {
		dt = T_UNION;
		tc = C_UTAG;
		mc = C_MOU;
	}
	tsp = NULL;
	lex();
	if (s == ID) {
		tsp = reflookup(SL_TAG);
		if (tsp == NULL)
			tsp = deflookup(SL_TAG, ll);
		oidp = idp;		/* save idp, lex() may clobber it */
		lex();
		if (s != LBRACE) {
			c = tsp->s_class;
			if (c == C_NONE) {
				*at = dt+1;     /* Forward */
				*aip = tsp;
				return;
			}
			if (c==C_STAG || c==C_UTAG) {
				if (c != tc)
					tagmismatch(tsp);
				*at = dt;
				*aip = tsp->s_ip;
				++tsp->s_ip->i_refc;
				return;
			}
			cerror("\"%s\" is not a tag", tsp->s_id);
			*at = T_INT;
			*aip = NULL;
			return;
		}
		idp = oidp;		/* restore idp for deflookup() */
		tsp = deflookup(SL_TAG, ll);
	} else
		tsp = newtag(ll);
	mustbe(LBRACE);
	nip = (INFO *) new(sizeof(INFO));
	nip->i_refc = 1;
	nip->i_nsp = 0;
	ofs = 0;
	max = 0;
	while (s!=EOF && s!=RBRACE) {
		gcandt(&c, &t, &dp, &ip, &rf);
		if (t == T_NONE) {
			if (s == ID)
				cerror("\"%s\" is not a typedef name", id);
			else
				cerror("missing type in structure body");
			while (s!=EOF && s!=RBRACE && s!=SEMI)
				lex();
			if (s == SEMI)
				lex();
			continue;
		}
		if ((rf & ~(S_VOLAT|S_VTARG)) != 0 || c != C_NONE)
			cerror("class not allowed in structure body");
		if (isvariant(VSINU)) {
		/*
		 * Handle the "struct" in "union" rule.
		 * A series of unnamed structures within a union are united
		 * into a set of named/typed offsets within the union.
		 * Basically, we add the unique members of the
		 * new structure to the members of the current union.
		 * Not strictly part of C, and only works if all MOS in
		 * same level of symbol table.
		 */
			if (dt==T_UNION && t==T_STRUCT && s==SEMI) {
				notbook();
				lex();
				bitsize = (unsigned long)ip->i_size*NBPBYTE;
				if (bitsize > max)
					max = bitsize;
				for (i=0; i<ip->i_nsp; ++i) {
					mp = ip->i_sp[i];
					j = nip->i_nsp;
					while (--j >= 0)
						if (nip->i_sp[j] == mp)
							break;
					if (j < 0) {
						nip = newinfo(nip, mp);
						if (tsp != NULL)
							mp->s_flag |= S_TAG;
					}
				}
				continue;
			}
		}
		for (;;) {
			if (s == COLON) {
				lex();
				newtree(sizeof(TREE));
				++ininit;
				w = iconexpr();
				--ininit;
				if (w < 0)
					cerror("bad filler field width");
				ofs = fieldalign(t, NULL, ip, w, ofs) + w;
			} else if (gdecl(&msp, &mdp, dp, mc, ls)) {
				if (sc == C_GREF)
					msp->s_level = LL_EXT;
				w = 0;
				if (s == COLON) {
					lex();
					newtree(sizeof(TREE));
					++ininit;
					w = iconexpr();
					--ininit;
					if (w <= 0)
						cerror("bad field width");
				}
				ofs = fieldalign(t, mdp, ip, w, ofs);
				msp = declare(msp, mc, t, mdp, ip,
					      volqual(rf, mdp, dp), w, ofs);
				nip = newinfo(nip, msp);
				if (tsp != NULL)
					msp->s_flag |= S_TAG;
				if (w == 0)
				    ofs += (unsigned long)ssize(msp)*NBPBYTE;
				else
				    ofs += w;
			}
			if (dt == T_UNION) {
				if (ofs > max)
					max = ofs;
				ofs = 0;
			}
			if (s != COMMA)
				break;
			lex();
		}
		xdropinfo(t, ip);
		mustbe(SEMI);
	}
	mustbe(RBRACE);
	if (dt == T_STRUCT)
		max = ofs;
	nbpstrg = saligntype(nip) * NBPBYTE;
	if (nbpstrg == 0)
		nbpstrg = NBPBYTE;
	max = (max + nbpstrg - 1) / nbpstrg;
	max = max * nbpstrg / NBPBYTE;
	if (max > MAXESIZE) {
		cerror("size of %s too large",
			(dt==T_STRUCT) ? "struct" : "union");
		max = 0;
	}
	nip->i_size = max;
	if (tsp != NULL)
		tsp = declare(tsp, tc, 0, NULL, nip, 0);
	*at = dt;
	*aip = nip;
}

/*
 * Read an enumeration.
 */
genum(sc, at, aip)
int	sc, *at;
INFO	**aip;
{
	register SYM	*sp, *tsp;
	INFO		*ip;
	TOK		*oidp;
	int		c, emv, emvmax, emvmin, ll;

	ll = (sc == C_GREF) ? LL_EXT : llex;
	tsp = NULL;
	lex();
	if (s == ID) {
		tsp = reflookup(SL_TAG);
		oidp = idp;		/* save idp, lex() may clobber it */
		lex();
		if (s != LBRACE) {
			if (tsp == NULL)
				tsp = deflookup(SL_TAG, ll);
			c = tsp->s_class;
			if (c == C_NONE) {
				*at = T_FENUM;
				*aip = tsp;
				return;
			}
			if (c == C_ETAG) {
				*at = T_ENUM;
				*aip = tsp->s_ip;
				++tsp->s_ip->i_refc;
				return;
			}
			cerror("\"%s\" is not an \"enum\" tag",
					 tsp->s_id);
			*at = T_INT;
			*aip = NULL;
			return;
		}
		idp = oidp;		/* restore idp for deflookup() */
		tsp = deflookup(SL_TAG, ll);
	} else
		tsp = newtag(ll);
	mustbe(LBRACE);
	ip = (INFO *) new(sizeof(INFO));
	ip->i_refc = 1;
	ip->i_nsp = 0;
	emvmax = emvmin = emv = 0;
	for (;;) {
		if (s==EOF || (s==RBRACE && ip->i_nsp == 0)) {
			cerror("unexpected end of enumeration list");
			break;
		} else if (s==RBRACE) {
			cwarn("trailing ',' in enumeration list");
			break;
		} else if (s != ID) {
			cerror("error in enumeration list syntax");
			skip();
			continue;
		}
		sp = deflookup(SL_VAR, ll);
		lex();
		if (s == ASSIGN) {
			lex();
			newtree(sizeof(TREE));
			++ininit;
			emv = iconexpr();
			--ininit;
		}
		if (emv > emvmax)
			emvmax = emv;
		if (emv < emvmin)
			emvmin = emv;
		ip = newinfo(ip, sp);
		sp = declare(sp, C_MOE, 0, NULL, NULL, 0, emv);
		++emv;
		if (s == RBRACE)
			break;
		mustbe(COMMA);
	}
	if (s == RBRACE)
		lex();
	ip->i_type = (emvmax>MAXUCE || emvmin<0) ? T_INT : T_UCHAR;
	if (tsp != NULL)
		tsp = declare(tsp, C_ETAG, 0, NULL, ip, 0);
	*at = T_ENUM;
	*aip = ip;
}

/*
 * Read an old-style K&R function argument list.
 * '*aokp' indicates whether the storage class of the parent declarator
 * and the position of the parenthesized list is appropriate for the
 * formal parameter list of an actual function definition.
 * '*adp' is where the function prototype DIM should be stored.
 */
garglist(aokp, adp) register int *aokp; register DIM **adp;
{
	register SYM *ap;
	sizeof_t pi;

	pi = 0;
	if (protohere()) {
		pi = gproto(*aokp == 1);
		*aokp = 0;
	} else if (*aokp==1) {
		nargs = 0;
		if (s != RPAREN)
			for (;;) {
				if (s != ID) {
					cerror("argument list has incorrect syntax");
					break;
				}
				if (nargs >= NARGS)
					cfatal("too many arguments");
				ap = deflookup(SL_VAR, LL_ARG);
				ap = declare(ap, C_ARG, T_INT,
					           NULL, NULL, 0);
				args[nargs++] = ap;
				lex();
				if (s != COMMA)
					break;
				lex();
			}
		*aokp = 0;
	}
	*adp = tackdim(*adp, D_FUNC, pi);
}

/*
 * Prototypes.  A parameter list is kept as the promoted type of each
 * parameter -- what the call passes -- in a pool shared by identical lists.
 * A D_FUNC's d_bound is 0 for `()', else the list's pool index.  A list is
 * [count][flags][type...] behind a two-byte hash chain link.
 */
#define	PCHUNK	512		/* Pool chunk				*/
#define	NPCHUNK	64		/* Chunks; the index stays in 16 bits	*/
#define	NPHASH	32		/* Hash chains				*/

int	pdecl;			/* 1: defining parameters, 2: prototype	*/
int	pansi;			/* This declarator's parameters are ANSI	*/
static	char	*ppool[NPCHUNK];
static	unsigned ptop;		/* Pool bytes used			*/
static	unsigned phash[NPHASH];

/*
 * Does 's' begin a parameter declaration rather than an identifier list?
 */
isproto()
{
	register SYM	*sp;

	if ((s >= INT && s <= SIGNED) || s == DOT)
		return 1;
	return (s == ID && (sp = reflookup(SL_VAR)) != NULL
		&& sp->s_class == C_TYPE);
}

/*
 * Does a parameter type list start here, at the language level?  Under
 * K&R, `f(T)' with T a typedef name is a parameter named T, as in the
 * donor, and a list that starts with a type keyword is an error.
 */
protohere()
{
	if (!isproto())
		return 0;
	if (stdlevel() == STD_KR) {
		if (s == ID)
			return 0;
		stdok(STD_C89, "a function prototype");
	}
	return 1;
}

/*
 * The list at pool index 'pi'.
 */
char *
pproto(pi)
sizeof_t pi;
{
	register unsigned i;

	i = (unsigned)pi - 1;
	return ppool[i / PCHUNK] + i % PCHUNK + 2;
}

/*
 * Intern a list of 'n' types 'k' with flags 'f'; return its index.
 */
sizeof_t
pintern(n, f, k)
register int	n;
int		f;
char		*k;
{
	register char	*p;
	register unsigned i;
	unsigned	h;

	h = n + f;
	for (i = 0; i < n; ++i)
		h = h * 3 + k[i];
	h %= NPHASH;
	for (i = phash[h]; i != 0; i = (p[-2]&0377) << 8 | (p[-1]&0377)) {
		p = pproto((sizeof_t)i);
		if (p[0] == n && p[1] == f && memcmp(p+2, k, n) == 0)
			return (sizeof_t)i;
	}
	if (ptop % PCHUNK + n + 4 > PCHUNK)
		ptop += PCHUNK - ptop % PCHUNK;
	if (ptop / PCHUNK >= NPCHUNK)
		cfatal("too many prototypes");
	if (ptop % PCHUNK == 0)
		ppool[ptop / PCHUNK] = new(PCHUNK);
	i = ptop + 1;
	p = pproto((sizeof_t)i);
	p[-2] = phash[h] >> 8;
	p[-1] = phash[h];
	p[0] = n;
	p[1] = f;
	memcpy(p+2, k, n);
	phash[h] = i;
	ptop += n + 4;
	return (sizeof_t)i;
}

/*
 * The type a parameter of type 't' and dims 'dp' is passed as.
 */
pkind(t, dp)
register int	t;
DIM		*dp;
{
	if (dp != NULL)
		return T_PTR;
	switch (t) {
	case T_CHAR:
	case T_SHORT:
	case T_ENUM:
	case T_FENUM:
		return T_INT;
	case T_UCHAR:
	case T_USHORT:
		return T_UINT;
	case T_FLOAT:
		return T_DOUBLE;
	case T_FSTRUCT:
		return T_STRUCT;
	case T_FUNION:
		return T_UNION;
	}
	return t;
}

/*
 * Read a parameter type list; 's' is its first token.  Each name is
 * declared as a parameter when 'def' says the list may begin a function
 * definition, and is otherwise scoped to the list.  Return the list's index.
 */
sizeof_t
gproto(def)
{
	register int	n;
	int		c, t, rf, f, i, odv, opd;
	DIM		*dp, *pdp, *xdp;
	INFO		*ip;
	SYM		*sp;
	char		k[NARGS];

	odv = dvol;
	opd = pdecl;
	if (def) {
		nargs = 0;
		pansi = 1;
	}
	n = f = 0;
	for (;;) {
		if (s == DOT) {
			for (i = 0; i < 3 && s == DOT; ++i)
				lex();
			if (i < 3 || n == 0)
				cerror("parameter list syntax");
			f = 1;
			break;
		}
		pdecl = 0;
		dvol = 0;
		gcandt(&c, &t, &dp, &ip, &rf);
		if (c == C_REG)
			c = C_PREG;
		else {
			if (c != C_NONE)
				cerror("bad argument storage class");
			c = C_PAUTO;
		}
		if (t == T_NONE) {
			cerror("parameter type required");
			t = T_INT;
		}
		pdecl = def ? 1 : 2;
		if (gdecl(&sp, &pdp, dp, def ? c : C_ARG, SL_VAR)) {
			if (t == T_VOID && pdp == NULL) {
				if (n == 0 && sp == NULL && s == RPAREN) {
					pdecl = 0;
					break;
				}
				cerror("illegal use of \"void\" type");
				t = T_INT;
			}
			if (pdp != NULL && pdp->d_type == D_FUNC) {
				xdp = pdp;
				pdp = tackdim(NULL, D_PTR, (sizeof_t)0);
				pdp->d_dp = xdp;
			}
			if (n >= NARGS)
				cfatal("too many arguments");
			k[n++] = pkind(t, pdp);
			if (def && sp != NULL) {
				sp = declare(sp, C_ARG, T_INT, NULL, NULL, 0);
				sp = declare(sp, c, t, pdp, ip,
					     volqual(rf, pdp, dp));
				args[nargs++] = sp;
			} else {
				volqual(rf, pdp, dp);
				dropdim(pdp);
			}
		}
		pdecl = 0;
		xdropinfo(t, ip);
		if (s != COMMA)
			break;
		lex();
	}
	dvol = odv;
	pdecl = opd;
	return pintern(n, f, k);
}

/*
 * The token holding the name of 'sp'.
 */
TOK *
symtok(sp)
register SYM	*sp;
{
	register TOK	*tp;
	register char	*p;
	register unsigned h;
	int		i;

	h = 0;
	for (p = sp->s_id; *p != 0; ++p)
		h += *p;
	for (tp = hash0[h % NHASH]; tp != NULL; tp = tp->t_tp)
		if (tp->t_id == sp->s_id)
			return tp;
	for (i = 0; i < NHASH; ++i)
		for (tp = hash0[i]; tp != NULL; tp = tp->t_tp)
			if (tp->t_id == sp->s_id)
				return tp;
	cbotch("symtok");
	return NULL;
}

/*
 * A prototype in a declaration that is not a definition named its
 * parameters: remove them.
 */
dropargs()
{
	register SYM	*sp, **spp;
	register int	i;

	for (i = 0; i < nargs; ++i) {
		sp = args[i];
		for (spp = &symtok(sp)->t_sym; *spp != sp; spp = &(*spp)->s_sp)
			;
		*spp = sp->s_sp;
		if (sp->s_ip != NULL)
			xdropinfo(sp->s_type, sp->s_ip);
		dropdim(sp->s_dp);
		free((char *) sp);
	}
	nargs = 0;
	pansi = 0;
}

/*
 * Check the parameters of the definition of 'sp' against its prototype.
 */
protochk(sp)
SYM	*sp;
{
	register char	*p;
	register SYM	*ap;
	register int	i, n;
	sizeof_t	pi;

	if ((pi = sp->s_dp->d_bound) == 0)
		return;
	p = pproto(pi);
	n = p[0];
	i = (nargs == n || (nargs > n && p[1] != 0));
	while (i != 0 && --n >= 0) {
		ap = args[n];
		i = (p[2+n] == pkind(ap->s_type, ap->s_dp));
	}
	if (i == 0)
		cerror("\"%s\" does not match its prototype", sp->s_id);
}

/*
 * Tack a DIM structure onto the end
 * of the dimension list associated with "dp".
 */
DIM *
tackdim(dp, t, b)
DIM	*dp;
int	t;
sizeof_t b;
{
	register DIM	*dp1, *dp2;

	dp1 = (struct dim *) new(sizeof(struct dim));
	dp1->d_dp = NULL;
	dp1->d_type = t;
	dp1->d_bound = b;
	if ((dp2 = dp) == NULL)
		return dp1;
	while (dp2->d_dp != NULL)
		dp2 = dp2->d_dp;
	dp2->d_dp = dp1;
	return dp;
}

/*
 * Nonzero if any of the first 'n' dims (all, if 'n' < 0) is not an array:
 * a `volatile' past it qualifies something pointed at, not the object.
 */
ptrdims(dp, n)
register DIM	*dp;
register int	n;
{
	for (; dp != NULL && n-- != 0; dp = dp->d_dp)
		if (dp->d_type != D_ARRAY)
			return 1;
	return 0;
}

/*
 * Volatile flags for a declarator with dims 'dp' whose specifier gave 'rf'
 * and dims 'tdp'.  The specifier's S_VOLAT becomes S_VTARG when the declarator
 * adds a pointer or function; the declarator's own `* volatile' are added.
 */
volqual(rf, dp, tdp)
register int	rf;
DIM	*dp, *tdp;
{
	register int	n;
	register DIM	*p;

	n = 0;
	for (p = dp; p != NULL; p = p->d_dp)
		++n;
	for (; tdp != NULL; tdp = tdp->d_dp)
		--n;
	if ((rf & S_VOLAT) != 0 && ptrdims(dp, n))
		rf = (rf & ~S_VOLAT) | S_VTARG;
	rf |= dvol;
	dvol = 0;
	return rf;
}

/*
 * Release a DIM chain.
 */
dropdim(dp)
register DIM	*dp;
{
	if (dp != NULL) {
		dropdim(dp->d_dp);
		free((char *) dp);
	}
}

/*
 * Duplicate a DIM chain.
 */
DIM *
dupldim(dp)
register DIM	*dp;
{
	register DIM	*np;

	if (dp == NULL)
		return NULL;
	np = (struct dim *) new(sizeof(struct dim));
	np->d_dp = dupldim(dp->d_dp);
	np->d_type = dp->d_type;
	np->d_bound = dp->d_bound;
	return np;
}

/*
 * Append a symbol to a struct/union/enum information array.
 * Grow the array if necessary and possible.
 */
INFO *
newinfo(ip, sp)
register INFO	*ip;
SYM	*sp;
{
	register INFO	*tip;
	register int	i;

	i = ip->i_nsp;
	if ((i % 16) == 0) {
		tip = ip;
		ip = (INFO *) new(sizeof(INFO) + (i+16) * sizeof(SYM *));
		ip->i_refc = tip->i_refc;
		ip->i_data = tip->i_data;
		ip->i_nsp = i;
		while (--i >= 0)
			ip->i_sp[i] = tip->i_sp[i];
		free((char *) tip);
		i = ip->i_nsp;
	}
	ip->i_sp[i] = sp;
	ip->i_nsp += 1;
	return ip;
}

/*
 * Read an array bound.
 * An array bound is a constant expression.
 * It may be inside a cast, so save and restore the tree allocate pointer.
 * If signed, give an error if the bound is less than 0.
 * Call the machine dependent size check routine for upper bound check.
 */
sizeof_t getbound()
{
	register TREE	*tp;
	extern TREE	*expr();
	register int	t;
	register long	bound;
	TREE		*tmp;

	tmp = talloc();
	tp = expr();
	treset(tmp);
	if (tp->t_op == ICON)
		bound = tp->t_ival;
	else if (tp->t_op == LCON)
		bound = tp->t_lval;
	else if (tp->t_op == ZCON)
		bound = tp->t_zval;
	else {
		cerror("array bound must be a constant");
		return 0;
	}
	t = tltype(tp);
	if ((t==T_CHAR || t==T_SHORT || t==T_INT || t==T_LONG)
	&& bound < 0) {
		cerror("array bound must be positive");
		return 0;
	}
	return szcheck(bound, 1, "array bound");
}

/*
 * The SYM 'sp' has storage class C_STAG or C_UTAG.
 * A new declaration has been encountered which is of the wrong class.
 * Print a diagnostic giving the name of the tag and its previous class.
 */
tagmismatch(sp)
register SYM	*sp;
{
	register char	*p;

	p = (sp->s_class == C_UTAG) ? "union" : "structure";
	cerror("\"%s\" is a %s tag", sp->s_id, p);
}

/*
 * Read a cast.
 * Return a pointer to a CAST tree node,
 * or NULL if not a legal cast.
 */
TREE *
cast()
{
	register TREE	*tp;
	DIM		*dp, *tdp;
	INFO		*ip;
	DIM		*cast1();
	int		rf, ov;
	int 		c, t;

	gcandt(&c, &t, &dp, &ip, &rf);
	if (c==C_NONE && t==T_NONE && rf==0)
		return NULL;
	if ((rf & ~(S_VOLAT|S_VTARG)) != 0 || c != C_NONE)
		cerror("storage class not allowed in cast");
	if (t == T_NONE) {
		cerror("type required in cast");
		t = T_INT;
	}
	tdp = dp;
	ov = dvol;		/* we may be in a declarator's array bound */
	dvol = 0;
	dp = cast1(dp);
	rf = volqual(rf, dp, tdp);
	dvol = ov;
	if (t == T_VOID && isvoidptr(dp))
		t = T_CHAR;
	if (t==T_VOID && dp!=NULL && !isfunction(dp)) {
		cerror("illegal use of void type in cast");
		t = T_INT;
	}
	mustbe(RPAREN);
	tp = talloc();
	tp->t_op = CAST;
	tp->t_type = t;
	if ((rf & S_VTARG) != 0)
		tp->t_vol = V_TARG;
	tp->t_dp = dp;
	tp->t_ip = ip;
	xdropinfo(t, ip);
	return tp;
}

/* this is the cast version of gdecl() */
DIM *
cast1(tdp)
DIM	*tdp;
{
	register DIM	*dp;
	register sizeof_t b;
	DIM		*cast2();
	int		vf;

	while (s == CONST || s == VOLATILE) {
		lex();
	}
	if (s == MUL) {
		lex();
		vf = 0;
		for (; s == CONST || s == VOLATILE; lex())
			vf |= s == VOLATILE;
		dp = cast1(NULL);
		if (vf)
			dvol |= ptrdims(dp, -1) ? S_VTARG : S_VOLAT;
		dp = cast2(dp, D_PTR, (sizeof_t)0);
	} else {
		dp = NULL;
		if (s == LPAREN) {
			lex();
			if (protohere()) {
				dp = cast2(dp, D_FUNC, gproto(0));
				mustbe(RPAREN);
			} else if (s != RPAREN) {
				dp = cast1(NULL);
				mustbe(RPAREN);
			} else {
				lex();
				dp = cast2(dp, D_FUNC, (sizeof_t)0);
			}
		}
	again:
		if (s == LPAREN) {
			DIM *tdp;
			lex();
			tdp = dp;
			cproto(&tdp);
			dp = tdp;
			mustbe(RPAREN);
			goto again;
		}
		if (s == LBRACK) {
			lex();
			b = 0;
			if (s != RBRACK)
				b = getbound();
			mustbe(RBRACK);
			dp = cast2(dp, D_ARRAY, b);
			goto again;
		}
	}
	while (tdp != NULL) {
		dp = cast2(dp, tdp->d_type, tdp->d_bound);
		tdp = tdp->d_dp;
	}
	return dp;
}

/* this is the cast version of tackdim() */
DIM *
cast2(dp, t, b)
DIM	*dp;
int	t;
sizeof_t b;
{
	register DIM	*dp1, *dp2;

	dp1 = (struct dim *) talloc();
	dp1->d_dp = NULL;
	dp1->d_type = t;
	dp1->d_bound = b;
	if ((dp2 = dp) == NULL)
		return dp1;
	while (dp2->d_dp != NULL)
		dp2 = dp2->d_dp;
	dp2->d_dp = dp1;
	return dp;
}

cproto(adp) DIM **adp;
{
	*adp = cast2(*adp, D_FUNC, protohere() ? gproto(0) : (sizeof_t)0);
}

/* end of n0/gdecl.c */
