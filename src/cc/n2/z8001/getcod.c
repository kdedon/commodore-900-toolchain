/*
 * Copyright (c) 2026 Kevin Dedon.
 * SPDX-License-Identifier: MIT
 */
/*
 * Read the intermediate (i1) CODE stream into the MI's INS list.  getcode() is almost
 * machine-independent; getfield() (afield.c) is the only Z8001-specific reader.  Two
 * Z8001 i1 conventions are handled here (pseudops.h):
 *
 *   0xC0..0xC3  data directives (ZBYTE/ZWORD/ZLPTR/ZGPTR) -- these flow through the
 *               normal CODE path (opinfo op_naddr 1, OF_*_ data style drives emit).
 *   0xC4        ZSWREL, a switch-table word -- becomes an LLLINK node.
 *   0xC5        ZRETV, a word register the return statement whose JP follows
 *               leaves for the epilogue -- no node; see getautos.
 *   0xD0..0xDF  the conditional relative-jump band (ZJREL|cc) -- becomes a JUMP node
 *               whose i_rel carries the 4-bit Z8000 condition code.
 *
 * The one unconditional jump JP (style OF_JP) likewise becomes a JUMP node (cc =
 * always); the MI's span-dependent machinery relaxes it and emit puts out JR.
 */
#ifdef   vax
#include "INC$LIB:cc2.h"
#else
#include "cc2.h"
#endif

#define	CC_ALWAYS	8		/* Z8000 condition code T (always)	*/

SYM	retvoid;			/* i_sp of a JUMP that returns no value	*/
int	retmask;			/* bit n: a return leaves a value in Rn	*/
int	retvoidok;			/* the marks below still hold		*/
int	fallvoid;			/* the body ends without returning a value */
INS	*lastins, *lastpred;		/* its last instruction, and the one before */
static SYM	retval;			/* i_sp of a JUMP that returns a value	*/
static int	retvregs;		/* retmask of the function being read	*/
#define	NRUN	8			/* labels kept at the end of a body	*/

/*
 * Build a span-dependent JUMP node for a branch with condition code `cc'.  cc1
 * emits the target as a label-direct address field (A_LID|A_DIR, labno) -- the same
 * shape the donor JUMP node consumes -- so read it as the mode word + label number.
 */
static INS *
jumpnode(cc, mode)
{
	register INS	*ip;

	if (mode != (A_LID|A_DIR))
		cbotch("jump target");
	ip = newi(sizeof(INS));
	ip->i_type = JUMP;
	ip->i_long = 0;
	ip->i_rel = cc;
	ip->i_fp = NULL;
	ip->i_bp = NULL;
	ip->i_labno = iget();
	ip->i_sp = NULL;
	ip->i_ip = NULL;
	return (ip);
}

/*
 * Read in a code item.
 * Return a pointer to a filled in INS node.
 */
INS *
getcode()
{
	register INS	*ip;
	register OPINFO	*opp;
	register int	i;
	register int	opcode;
	register int	retv;

	opcode = bget();
	retv = 0;
	while (opcode == ZRETV) {
		retvregs |= 1 << (iget() & A_REGM);
		if (bget() != CODE)
			cbotch("return register");
		opcode = bget();
		retv = 1;
	}
	if (opcode >= ZJREL && opcode <= (ZJREL|0xF)) {	/* conditional JR cc */
		ip = jumpnode(opcode & 0xF, iget());
		ip->i_sp = &retvoid;
		return (ip);
	}
	if (opcode == ZSWREL) {				/* switch-table word */
		ip = jumpnode(CC_ALWAYS, iget());
		ip->i_type = LLLINK;
		return (ip);
	}
	opp = &opinfo[opcode];
	if (opp->op_style == OF_JP) {
		i = iget();
		if (i == (A_LID|A_DIR)) {		/* JP -> relaxed relative jump */
			ip = jumpnode(CC_ALWAYS, i);
			ip->i_sp = retv ? &retval : &retvoid;	/* see getautos */
			return (ip);
		}
		ip = newn(1);				/* JP @RRn: a switch dispatch */
		ip->i_af[0].a_mode = i & (A_AMOD|A_REGM);
		ip->i_af[0].a_sp = NULL;
		ip->i_af[0].a_value = 0;
		ip->i_type = CODE;
		ip->i_fp = NULL;
		ip->i_bp = NULL;
		ip->i_op = opcode;
		ip->i_naddr = 1;
		return (ip);
	}
	ip = newn(opp->op_naddr);
	ip->i_type = CODE;
	ip->i_fp = NULL;
	ip->i_bp = NULL;
	for (i=0; i<opp->op_naddr; ++i)
		getfield(opcode, &ip->i_af[i]);
	ip->i_op = opcode;
	ip->i_naddr = opp->op_naddr;
	return (ip);
}

/*
 * Read in the AUTOS item that ends a function body: the size of the stack frame
 * and the callee-saved register mask, used by genprolog to put out the function
 * prolog.
 */
getautos()
{
	register INS	*ip;
	register int	i, seg, nrun;
	int		run[NRUN];

	framesize = iget();
	framemask = iget();	/* callee-saved register-variable mask (cc0) */
	/*
	 * The record ends the body.  The labels after its last instruction are
	 * where a return jumps and where the body runs off its end.  A jump there
	 * that no ZRETV preceded returns no value: on that path the epilogue reads
	 * no register.  The body runs off its end without a value unless its last
	 * instruction is a return's jump.  Every other jump loses its mark.
	 */
	seg = SCODE;
	nrun = 0;
	lastins = lastpred = NULL;
	for (ip = ins.i_fp; ip != &ins; ip = ip->i_fp) {
		if (ip->i_type == ENTER)
			seg = ip->i_seg;
		else if (seg != SCODE)
			;
		else if (ip->i_type == CODE || ip->i_type == JUMP || ip->i_type == LLLINK) {
			lastpred = lastins;
			lastins = ip;
			nrun = 0;
		} else if (ip->i_type == LLABEL && nrun >= 0) {
			if (nrun < NRUN)
				run[nrun++] = ip->i_labno;
			else
				nrun = -1;		/* too many: keep no mark */
		}
	}
	fallvoid = lastins == NULL || lastins->i_type != JUMP || lastins->i_sp != &retval;
	for (ip = ins.i_fp; ip != &ins; ip = ip->i_fp) {
		if (ip->i_type != JUMP || ip->i_sp == NULL)
			continue;
		for (i = 0; i < nrun && run[i] != ip->i_labno; ++i)
			;
		if (ip->i_sp != &retvoid || i >= nrun)
			ip->i_sp = NULL;
	}
	retmask = retvregs;
	retvregs = 0;
	retvoidok = 1;
}
