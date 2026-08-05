/*
 * n0/z8001/bind.c
 * Machine-dependent parser binding (storage layout, type sizes, alignment, arg
 * ABI). Segmented Z8001. Template: n0/i8086/bind.c -- its 16-bit-int + segmented
 * SPTR/LPTR + word-alignment model already matches the Z8001 (mch.h).
 */
#include "cc0.h"

typedef	struct  locals	{
	struct  locals *l_lstp;
	int     l_lofs;
	int     l_mask;
}	LOCALS;

LOCALS	*clstp;		        /* Local stack */
int	clofs;                  /* Current local offset */
int	cmask;			/* Current mask */
int	llofs;			/* Last local offset reported */
int	lmask;			/* Last register mask reported */
int	lastword = T_PTR;	/* Last 16 bit type */
char	inbtr[]	 = "identifier \"%s\" not bound to register";

/*
 * This table is indexed by C type to obtain the size
 * in bytes of a machine object.
 * The T_PTR entry is 2; this is for ONLYSMALL.
 * The entry is patched based on the model.
 */
int     mysizes[] = {
	0,
	1,	1,
	2,	2,
	2,	2,
	2,
	4,	4,
	4,	8,
	0,
	0,	0,
	0,	0,
	0,	0
};

/*
 * This table is indexed by C type to obtain the machine type,
 * as defined in 'mch.h'.
 */
char    mytypes[] = {
	0,
	S8,     U8,
	S16,    U16,
	S16,    U16,
	SPTR,
	S32,    U32,
	F32,    F64,
	S16,
	BLK,    0,
	BLK,    0,
	0,      0
};

/*
 * main() calls this routine to perform machine-dependent setup.
 * On the i8086, it changes the size of a pointer and some other things
 * that alter the allocation of register variables.
 */
int	alignment;		/* alignment from #pragma align (4.2.12 interface) */

vinit()
{
	alignment = 0;
#if !ONLYSMALL
	lastword = T_PTR;
	mysizes[T_PTR] = 2;
	mytypes[T_PTR] = SPTR;
	if (notvariant(VSMALL)) {
		lastword = T_UINT;
		mysizes[T_PTR] = 4;
		mytypes[T_PTR] = LPTR;
	}
#endif
}

/*
 * Handle a #pragma. Returns 1 if recognized, 0 if not.
 * #pragma align N sets the structure-member alignment.
 */
pragma(p) char *p;
{
	static char align[] = "align";

	while (*p == ' ' || *p == '\t')
		++p;
	if (strncmp(align, p, sizeof(align)-1) == 0) {
		alignment = atoi(p + sizeof(align)-1);
		if (alignment < 0) {
			cerror("#pragma align: bad alignment %d", alignment);
			alignment = 0;
		}
		return 1;
	}
	return 0;
}

/*
 * Given a field type, return an appropriate alignment type.
 */
int
faligntype(t) register int t;
{
	if (t <= T_ULONG && t != T_PTR)
		return mysizes[t];
	if (t == T_FSTRUCT || t == T_FUNION || t == T_FENUM) {
		cerror("alignment of incomplete %s type is not known",
			(t == T_FSTRUCT) ? "struct"
		      : (t == T_FUNION)  ? "union"
		      : "enumeration");
		return mysizes[T_INT];
	}
	cbotch("faligntype %d", t);
}

/*
 * Empty the local binding stack and mark the registers usable
 * for register variables (SI and DI) as available.
 */
initlocals()
{
	clstp = NULL;
	clofs = 0;
	cmask = NOFREE;		/* FP + SP (R13:R15) always busy; no segment regs */
	llofs = 0;
	lmask = NOFREE;
	bput(AUTOS);
	iput((ival_t)clofs);
	iput((ival_t)cmask);
}

/*
 * Save the current state of the local bindings.
 */
savelocals()
{
	register LOCALS	*lstp;

	lstp = (LOCALS *) new(sizeof(LOCALS));
	lstp->l_lstp = clstp;
	lstp->l_lofs = clofs;
	lstp->l_mask = cmask;
	clstp = lstp;
}

/*
 * Restore locals.  Tell the code generator if it changes.
 */
restlocals()
{
	register LOCALS	*lstp;

	if ((lstp=clstp) == NULL)
		cbotch("restlocals");
	clstp = lstp->l_lstp;
	clofs = lstp->l_lofs;
	cmask = lstp->l_mask;
	putautos();
	free((char *) lstp);
}

/*
 * Bind locals to the correct place on the stack frame.
 * Where things end up is a function of the model of compilation.
 */
bindlocal(sp)
register SYM	*sp;
{
	register int	c, regno;

	if ((c=sp->s_class) == C_REG) {
		if ((regno=grabreg(sp)) >= 0) {
			sp->s_value = regno;
			return;
		}
		sp->s_class = C_AUTO;
		if (isvariant(VSNREG))
			cstrict(inbtr, sp->s_id);
	}
	if (c==C_AUTO || c==C_REG) {
		clofs -= ssize(sp);
		/*
		 * Z8000: word and long frame accesses must be EVEN-aligned;
		 * round an odd offset down for any auto bigger than a char
		 * (chars still byte-pack).  The donor guarded this with
		 * OMF286 only -- without it a char local makes the next
		 * pointer/long local land odd, and the LDL spill through the
		 * frame silently mis-addresses.  cc2 keeps the stack pointer
		 * itself even.
		 */
		if (ssize(sp) != 1 && (clofs & 1) != 0)
			--clofs;
#if	OMF286
		/*
		 * The 80287 does not function properly for arguments
		 * on odd boundaries.
		 * The OMF286 compiler therefore rounds up the offsets
		 * of autos to keep them on even boundaries;
		 * however, char and unsigned char autos are not word-aligned.
		 * The compiler driver must also setvariant(VALIGN) to keep
		 * the stack word-aligned.
		 * fieldalign() should also keep structure members
		 * on word boundaries within the struct, but it does not;
		 * this is a kludge to maintain compatability with PL/M-286,
		 * which does not word-align structure members.
		 * The UDI interface routines fail if structure members
		 * are forced to word boundaries.
		 */
		if (ssize(sp) != 1 && (clofs & 1) != 0)
			--clofs;
#endif
		sp->s_value = clofs;
		if (clofs >= 0)
			cerror("auto \"%s\" is not addressable", sp->s_id);
	}
}

/*
 * Attempt to get a register for symbol 'sp'.
 * Only word things go in registers;
 * this includes pointers in SMALL model.
 */
/* Allocate the next free register-variable register from the callee-saved
 * pool R6..R12 (saved by cc2's prolog per the cmask in the AUTOS record). */
static int
nextreg()
{
	register int r;

	for (r = R6; r <= R12; ++r) {
		if ((cmask & BREG(r)) == 0) {
			cmask |= BREG(r);
			return (r);
		}
	}
	return (-1);
}

/* Allocate the next free callee-saved register PAIR for a far (segmented) pointer
 * register variable.  The usable pairs are the even-aligned ones wholly inside the
 * callee-saved word pool R6..R12: RR6(R6,R7), RR8(R8,R9), RR10(R10,R11).  Both word
 * halves are marked busy so the prolog saves them and nextreg() won't reuse them.
 * Returns the pair register id (RRn = RR0 + r/2), or -1 if none free. */
static int
nextpair()
{
	register int r;

	for (r = R6; r <= R10; r += 2) {
		if ((cmask & (BREG(r) | BREG(r+1))) == 0) {
			cmask |= BREG(r) | BREG(r+1);
			return (RR0 + (r >> 1));
		}
	}
	return (-1);
}

grabreg(sp)
register SYM	*sp;
{
	register DIM	*dp;
	register int	type;

	if ((dp=sp->s_dp) != NULL) {
		if (dp->d_type == D_PTR) {
#if !ONLYSMALL
			if (isvariant(VSMALL))
				return (nextreg());	/* near (SPTR) pointer: one word reg */
			return (nextpair());		/* far (LPTR) pointer: a register PAIR */
#else
			return (nextreg());
#endif
		}
		return (-1);
	}
	type = sp->s_type;
	if (type>=T_SHORT && type<=lastword)
		return (nextreg());
	return (-1);
}

/*
 * Bind arguments.
 */
bindargs()
{
	register SYM	*sp;
	register int	i;
	register sizeof_t offset;

	/*
	 * First-arg offset off FP. Segmented frame: saved FP = R13 only (one word,
	 * pushed `PUSH @RR14,R13` per the BIOS prolog at 00:01fa) = 2 bytes, plus the
	 * 4-byte segmented return PC the CALL pushes = 6; the Coherent BIOS reads
	 * args at FP+6/FP+8 (cf. bios_disassembly 339-340).
	 * Near (VSMALL) frame: saved FP (2) + near return PC (2) = 4.
	 */
#if !ONLYSMALL
	if (isvariant(VSMALL))
		offset = 4;
	else
		offset = 6;
#else
	offset = 4;
#endif
	for (i=0; i<nargs; ++i) {
		sp = args[i];
		if (sp->s_class != C_PREG)
			sp->s_class = C_PAUTO;
		sp->s_value = offset;
		offset += ssize(sp);
		if (isvariant(VALIGN) && (offset & 1) != 0)
			++offset;
		if ((short)offset != offset)
		    cerror("parameter \"%s\" is not addressible", sp->s_id);
	}
}

/*
 * Copy register arguments from the stack into the register.
 * Change class of the argument to plain register.
 * Note that bindargs() has put the stack displacement
 * into the 's_value' field of the argument symbol.
 */
loadargs()
{
	register SYM	*sp;
	register int	i, r, v;

	for (i=0; i<nargs; ++i) {
		sp = args[i];
		if (sp->s_class == C_PREG) {
			if ((r=grabreg(sp)) >= 0) {
				v = sp->s_value;
				sp->s_class = C_REG;
				sp->s_value = r;
				loadreg(sp, v);
				continue;
			}
			sp->s_class = C_PAUTO;
			if (isvariant(VSNREG))
				cstrict(inbtr, sp->s_id);
		}
	}
}

/*
 * Load register-variable symbol 'sp' from its argument slot at frame 'offset'.
 * A word register var copies as T_INT; a far (segmented) pointer register var was
 * given a register PAIR (s_value >= RR0) and must copy as a 4-byte T_PTR (-> LDL),
 * else only the offset half would be loaded.
 */
loadreg(sp, offset)
SYM	*sp;
{
	register TREE	*lp, *rp, *tp;
	register int	rtype;

	rtype = (sp->s_value >= RR0) ? T_PTR : T_INT;
	newtree(sizeof(TREE));
	lp = talloc();
	lp->t_op = REG;
	lp->t_type = rtype;
	lp->t_reg = sp->s_value;
	rp = talloc();
	rp->t_op = PID;
	rp->t_type = rtype;
	rp->t_offs = offset;
	tp = build(ASSIGN, lp, rp);
	putautos();
	tput(EEXPR, 0, tp);
}

/*
 * Inform the code generator (and perhaps the optimizer)
 * about the current automatic variable allocation.
 * Keep the stack word-aligned if isvariant(VALIGN).
 */
putautos()
{
	if (clofs != llofs || cmask != lmask) {
		if (isvariant(VALIGN) && (clofs & 1) != 0)
			--clofs;
		llofs = clofs;
		lmask = cmask;
		bput(AUTOS);
		iput((ival_t)-clofs);
		iput((ival_t)cmask);
	}
}

/*
 * Look at type 't', DIM list 'dp' and field width 'w' (0 for non fields)
 * and return the bit offset of the base of the structure member.
 * The 'offset' argument is the current bit offset in the structure or union.
 * Check for fields that are too wide, bad field base types, and arrange
 * that the byte or word that spans the field can be grabbed in one grab.
 * See comments in bindlocal() above concerning reals and bitfield alignment.
 */
/*
 * Alignment (in bytes) required of a structure member of base type `t'
 * with derivation list `dp'.  The Z8000 accesses word and multiword data
 * only at even addresses, so every member wider than a byte must start on
 * a word boundary; a byte member may start anywhere.
 */
static int
memalign(t, dp) register int t; register DIM *dp;
{
	while (dp != NULL && (dp->d_type == D_ARRAY || dp->d_type == D_MOSAR))
		dp = dp->d_dp;			/* alignment of the element */
	if (dp != NULL)				/* pointer/function: a word pointer */
		return 2;
	if (t == T_STRUCT || t == T_UNION)	/* may hold word data: word-align */
		return 2;
	return (mysizes[t] <= 1) ? 1 : 2;	/* char/byte 1; int/long/float word */
}

/*
 * Alignment (in bytes) of a whole structure or union: the maximum alignment
 * of any member (1 for an all-byte struct, 2 once any word member appears).
 * The overall size is rounded up to this so arrays of the struct keep every
 * element's word members on even addresses.  Backs the saligntype() macro.
 */
int
salign(ip) register INFO *ip;
{
	register int	i, a, mx;

	mx = 1;
	if (ip != NULL)
		for (i = 0; i < ip->i_nsp; ++i) {
			a = memalign(ip->i_sp[i]->s_type, ip->i_sp[i]->s_dp);
			if (a > mx)
				mx = a;
		}
	return mx;
}

long
fieldalign(t, dp, ip, w, offset)
register DIM	*dp;
INFO		*ip;
register int	w;
long		offset;
{
	register int	maxwidth;
	register long	albits;

	if (w != 0) {					/* nonzero width */
		if (dp != 0)
			cerror("non scalar field");
		if ((maxwidth=8*mysizes[t]) > 16)	/* 8 for char, 16 for int */
			cerror("bad base type for field");
		if (w > maxwidth)
			cerror("field too wide");
		if ((offset&7)+w > maxwidth)
			offset = (offset+7) & ~7L;
	} else {					/* zero width */
		albits = (long)memalign(t, dp) * 8;
		offset = (offset + albits - 1) & ~(albits - 1);
	}
	return (offset);
}

/*
 * Convert a tree into its low level form.
 * Fill in the machine type byte looking at the C type
 * and the segment information.
 */
TREE *
transform(tp, why, above)
register TREE	*tp;
{
	register TREE	*lp;
	register TREE	*sp;
	register int	t;
	register int	wd;
	lval_t		iv;
	lval_t		es;

	/*
	 * The way that this code looks at the DIM lists to decide
	 * what type of conversion is inserted makes me sick.
	 * The correct type of conversion node (MUL, DIV, etc.)
	 * should really be inserted when the tree is constructed,
	 * guided by a table.
	 */
	if (tp->t_op == CONVERT) {
		lp = tp->t_lp;
		if (tp->t_dp!=NULL && lp->t_dp==NULL
		&&  why!=REXPR) {
			tp->t_op = MUL;
			tp->t_dp = NULL;
			/*
			 * A CONSTANT index whose scaled byte displacement lands in
			 * [0x8000, 0xFFFF] scales as UNSIGNED int, so the scale
			 * fold and the later symbol-offset fold read the
			 * displacement back positive -- an object bigger than 32K
			 * is addressed at such displacements, which a signed
			 * 16-bit fold misreads as negative (a segment borrow on a
			 * positive addend).  Every other index scales as INT:
			 * the hardware offset add wraps mod 64K within the
			 * segment, and no object crosses a segment boundary.
			 */
			iv = 0;
			if (lp->t_op == ICON)
				iv = (lp->t_type == T_UINT)
					? (lval_t)(lp->t_ival & 0xFFFF)
					: (lval_t)lp->t_ival;
			else if (lp->t_op == LCON)
				iv = lp->t_lval;
			es = 1;
			if ((sp = tp->t_rp) != NULL) {
				if (sp->t_op == ICON)
					es = sp->t_ival;
				else if (sp->t_op == LCON)
					es = sp->t_lval;
				else if (sp->t_op == ZCON)
					es = sp->t_zval;
			}
			iv *= es;
			if ((lp->t_op == ICON || lp->t_op == LCON)
			&& iv > 32767L && iv <= 65535L) {
				if (lp->t_type != T_UINT)
					tp->t_lp = bconvert(lp, T_UINT, NULL,NULL,NULL);
				tp->t_type = T_UINT;
			} else {
				if (lp->t_type != T_INT)
					tp->t_lp = bconvert(lp, T_INT, NULL,NULL,NULL);
				tp->t_type = T_INT;
			}
		} else if (tp->t_dp==NULL && lp->t_dp!=NULL && tp->t_rp!=NULL) {
			tp->t_op = DIV;
			lp->t_dp = NULL;
			lp->t_type = T_INT;
		}
	}
	/* Fixup any remaining ZCON's */
	if (tp->t_op == ZCON) {
		tp->t_op = ICON;
		if (tp->t_zval > 0xFFFFL)
			cwarn("sizeof truncated to unsigned");
		if (tp->t_zval < 0x8000L)
			tp->t_type = T_INT;
		tp->t_ival = tp->t_zval;
	}
	if (tp->t_dp != NULL)
		tp->t_type = mytypes[T_PTR];
	else if ((t=tp->t_type)==T_FSTRUCT || t==T_FUNION || t==T_FENUM) {
		unksize(t, tp->t_ip);
		tp->t_type = S16;
	} else {
		if (t == T_ENUM)
			t = tp->t_ip->i_type;
		tp->t_type = mytypes[t];
	}
	if (tp->t_op >= MIOBASE) {
		wd = why;
		if (why == REXPR)
			wd = EEXPR;
		tp->t_lp = transform(tp->t_lp, wd, tp->t_op);
		if (tp->t_op!=FIELD && tp->t_rp!=NULL)
			tp->t_rp = transform(tp->t_rp, wd, -1);
		if (tp->t_op==CONVERT && tp->t_rp==NULL) {
			lp = tp->t_lp;
			if (tp->t_type == lp->t_type)
				tp = lp;
		}
	}
	return (tp);
}

/*
 * Check if the operator 'op', when applied to C types 'lt' and 'rt'
 * (which are outputs from tltype(), which means that all pointers
 * have been converted to type T_PTR), involves no conversions.
 * What this means is that the code generator
 * has to be prepared to deal with the type mismatch.
 * This code has been edited too many times; I am really
 * quite ashamed of the number of bugs that have been
 * tracked down to this code. It is no longer amusing.
 */
noconvert(op, lt, rt)
register int	op;
register int	lt;
register int	rt;
{
	if (op==ASSIGN || op==CAST || (op>=EQ && op<=ULT)) {
		if ((lt>=T_CHAR && lt<=T_UCHAR)
		&&  (rt>=T_CHAR && rt<=T_UCHAR))
			return(1);
		if ((lt>=T_SHORT && lt<=T_UINT)	
		&&  (rt>=T_SHORT && rt<=T_UINT))
			return (1);
		if ((lt>=T_LONG  && lt<=T_ULONG)
		&&  (rt>=T_LONG  && rt<=T_ULONG))
			return (1);
		if (lt==T_PTR && rt==T_PTR)
			return (1);
#if !ONLYSMALL
		if (notvariant(VSMALL)
		&&   op != CAST) {
			if ((lt>=T_SHORT && lt<=T_ULONG)
			&&  (rt>=T_SHORT && rt<=T_ULONG)
			&&  (lt==T_PTR || rt==T_PTR))
				return (1);
		} else if (isvariant(VSMALL)) {
#endif
			if ((lt>=T_SHORT && lt<=T_PTR)
			&&  (rt>=T_SHORT && rt<=T_PTR))
				return (1);
#if !ONLYSMALL
		}
#endif
		if (op==CAST && lt==T_FLOAT && rt==T_DOUBLE)
			return (1);
	}
	return (0);
}

/*
 * Put out an ALIGN object of the correct flavor to align
 * the location counter well enough for the object to which 'sp' points.
 * On the i8086 there is only one type of alignment,
 * so the argument is unused.
 */
align(sp)
SYM	*sp;
{
	bput(ALIGN);
	bput(0);
}

/*
 * Check object sizes for overflow.
 */
sizeof_t szcheck(n, a, s) sizeof_t n; int a; char *s;
{
	if (n < 0x10000L)
		return n;
	if (a == 0 || (n & ~MAXUV) != 0) {
		cerror("size of %s too large", s);
		return(0);
	}
	if (isvariant(VSLCON))
		cstrict("size of %s overflows fsize_t", s);
	return (n);
}
