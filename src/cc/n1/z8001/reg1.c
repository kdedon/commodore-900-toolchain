/*
 * Copyright (c) 2026 Kevin Dedon.
 * SPDX-License-Identifier: MIT
 */
/*
 * n1/z8001/reg1.c
 * Machine-specific parts of the cc1 register allocator. Segmented Z8001.
 * Template: n1/i8086/reg1.c. Z8001 deltas: byte values may occupy only the
 * byte-addressable registers R0..R7 (mch.h BYTEREGS) instead of i8086's
 * AX/BX/CX/DX; and the Z8000 dynamic shift (SDA/SDL) takes its count in ANY
 * register, so the i8086 "keep CX free for the shift count" restriction is gone.
 */
#ifdef   vax
#include "INC$LIB:cc1.h"
#else
#include "cc1.h"
#endif

/*
 * A shift op-assign by a count in a register (ashl.t, ashr.t) loads its value
 * temp from the lvalue after the count is selected, and the count, selected
 * after the temp is bound, can land in the register bound to it.  So
 * isusable() does not bind the caller's register early but records it, and
 * regselect() binds the temp to it once the count is busy, unless the count
 * holds it.
 */
static	TREE	*shtree;	/* the shift op-assign */
static	int	shreg;		/* the caller's register for its value temp */

static
isvarshift(tp)
register TREE *tp;
{
	return ((tp->t_op == ASHL || tp->t_op == ASHR) && tp->t_rp->t_op != ICON);
}

/*
 * A signed int divided by 2^k, which modoper gives an unsigned word or long
 * constant: shifts and masks in one register, no DIV pair.
 */
static
ispow2div(tp)
register TREE *tp;
{
	return ((tp->t_op == DIV && tp->t_rp->t_op == ICON && tp->t_rp->t_type == U16
	      || tp->t_op == REM && tp->t_rp->t_op == LCON && tp->t_rp->t_type == U32)
	     && tp->t_type == S16);
}

/*
 * Select a register. 'tp' is the tree; 'c' is a context (PAIR or ANY*); 'flag'
 * is true if ANY should be resolved.
 */
regselect(tp, c, flag)
TREE	*tp;
{
	register REGDESC	*rp;
	register KIND		kind;
	register PREGSET	busy;
	register int		byte;
	register PERTYPE	*ptp;

	if (tp == shtree && c != PAIR && flag != 0) {
		shtree = NULL;
		if (!isrealreg(tp->t_rp->t_rreg)
		 || (reg[shreg].r_phys & reg[tp->t_rp->t_rreg].r_phys) == 0)
			return (shreg);
	}
	ptp = &pertype[tp->t_type];
	kind = ptp->p_pair;
	byte = bytereg(tp);
	if (c != PAIR) {
		if (flag == 0 && byte == 0)
			return (c);
		kind = ptp->p_kind;
	}
	busy = curbusy;
	/* RR0's exclusion from far-pointer ADDRESSING is a property of the role the
	 * register plays, not of the value's type: the Z8000 forbids R0/RR0 only as
	 * an indirect, base or index register (Z8000 CPU Technical Manual, 5.2 "Use
	 * of CPU Registers", p.5-2).  That role is exactly reg[].r_lvalue, where
	 * table1.c withholds KLP from RR0 -- so the ANYL arm below already refuses
	 * it, and no extra test belongs here.  A far pointer that is merely HELD or
	 * returned (r_rvalue KLP; RR0 is the long/pointer return pair) is legal and
	 * must stay legal, or every such value pays a needless copy. */
	for (rp = &reg[FRREG]; rp < &reg[NRREG]; ++rp) {
		if ((rp->r_phys & busy) != 0)
			continue;
		if (c == ANYL) {
			if ((rp->r_lvalue & kind) == 0)
				continue;
		} else {
			if ((rp->r_rvalue & kind) == 0)
				continue;
		}
		if (byte && (rp->r_phys & ~BYTEREGS) != 0)
			continue;
		return (rp - &reg[0]);
	}
	return (-1);
}

/*
 * Return true if register 'r' is a usable temporary for tree 'tp'.
 */
isusable(tp, c, r)
register TREE	*tp;
register int	r;
{
	register int		op;
	register PERTYPE	*ptp;
	register KIND		kind;
	register int		byte;

#if !TINY
	if (sflag > 2)
		snapf("Isusable(%P, %C, %R)? ", tp, c, r);
#endif
	op = tp->t_op;
	ptp = &pertype[tp->t_type];
	if (((op >= MUL && op <= REM) || (op >= AMUL && op <= AREM)) && !ispow2div(tp))
		kind = ptp->p_pair;
	else
		kind = ptp->p_kind;
	byte = bytereg(tp);
	if (c == MLVALUE) {
		if ((reg[r].r_lvalue & kind) == 0)
			goto no;
	} else {
		if ((reg[r].r_rvalue & kind) == 0)
			goto no;
	}
	if (byte && (reg[r].r_phys & ~BYTEREGS) != 0)
		goto no;
	/* Keep r used, as binding it would, so the lvalue's index avoids it. */
	if (isvarshift(tp)) {
		tp->t_used |= reg[r].r_phys;
		shtree = tp;
		shreg = r;
		goto no;
	}
#if !TINY
	if (sflag > 2)
		snapf("yes\n");
#endif
	return (1);
no:
#if !TINY
	if (sflag > 2)
		snapf("no\n");
#endif
	return (0);
}

/*
 * Test if a byte register is needed (machine-independent).
 */
bytereg(tp)
register TREE *tp;
{
	register op;

	if (isbyte(tp->t_type))
		return (1);
	if ((op = tp->t_op) == LEAF || op == CONVERT || op == CAST)
		tp = tp->t_lp;
	if (isbyte(tp->t_type))
		return (1);
	/* A store/RMW into a byte lvalue needs the value temp in a byte-addressable
	 * register (R0..R7), because the byte rules dial out its low half via [LO R]:
	 * ASSIGN, the compound-assigns (AADD..ASHR), AND prefix/postfix ++/-- on a byte
	 * (INCBEF..DECAFT) -- aft.t/bef.t fetch the old byte with `ZLDB [LO R],[AL]'.
	 * Omitting the inc/dec ops let a word temp land in R8..R15, where lohalf() is -1
	 * and genadr read ramode[-1] (col.c's `*p++'-style byte postfix). */
	if ((op == ASSIGN || (op >= AADD && op <= ASHR) || (op >= INCBEF && op <= DECAFT))
	 && isbyte(tp->t_lp->t_type))
		return (1);
	return (0);
}

/* end of n1/z8001/reg1.c */
