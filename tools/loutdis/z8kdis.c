/*
 * The Z8001 decode core.  Every opcode, field position and name is in the
 * generated table z8ktab.h, which gentab.py derives from the assembler's own
 * tables; this file finds the form a word belongs to and renders its operands
 * by kind.
 *
 * K&R C, 16-bit int safe: every instruction word and address is carried in an
 * unsigned long.
 */
#include <stdio.h>
#include <string.h>

#include "z8kdis.h"
#include "z8ktab.h"

/* the words of the instruction being decoded */
static unsigned long *zw;
static int znw;			/* words available */
static int zseg, zlong;		/* address word, and whether it is long */

/* the word at index k of the instruction itself, or -1 */
static long
zraw(k)
int k;
{
	return k < znw ? (long)(zw[k] & 0xFFFFL) : -1L;
}

/* word k of the instruction as the table counts it (all addresses short),
 * or -1 when it is past the words available. */
static long
zword(k)
int k;
{
	if (zseg && k > zseg && zlong)
		k++;
	return zraw(k);
}

static unsigned long
zfield(p)
struct zop *p;
{
	long w;

	w = zword((int)p->word);
	if (w < 0)
		w = 0;
	return ((unsigned long)w >> p->shift) & ((1L << p->width) - 1);
}

static char *
zreg(o, kind, r)
char *o;
int kind;
unsigned long r;
{
	switch (kind) {
	case ZK_RB:
		sprintf(o, "R%c%d", r < 8 ? 'H' : 'L', (int)(r & 7));
		break;
	case ZK_RR:
		sprintf(o, "RR%d", (int)r);
		break;
	case ZK_RQ:
		sprintf(o, "RQ%d", (int)r);
		break;
	case ZK_IR:
		sprintf(o, "@R%d", (int)r);
		break;
	case ZK_IRR:
		sprintf(o, "@RR%d", (int)r);
		break;
	default:
		sprintf(o, "R%d", (int)r);
		break;
	}
	return o + strlen(o);
}

/* a segmented address at table word k: 0xSS:0xOO short, 0xSS:0xOOOO long */
static char *
zaddr(o, k)
char *o;
int k;
{
	long a, b;

	a = zraw(k);
	if (a < 0) {
		strcpy(o, "?");
		return o + 1;
	}
	if (a & 0x8000L) {
		b = zraw(k + 1);
		if (b < 0)
			sprintf(o, "0x%02lX:?", (a >> 8) & 0x7FL);
		else
			sprintf(o, "0x%02lX:0x%04lX", (a >> 8) & 0x7FL, b);
	} else
		sprintf(o, "0x%02lX:0x%02lX", (a >> 8) & 0x7FL, a & 0xFFL);
	return o + strlen(o);
}

/* a relative target: the offset wraps within pc's segment */
static char *
ztarget(o, pc, d)
char *o;
unsigned long pc;
long d;
{
	sprintf(o, "0x%02lX:0x%04lX", (pc >> 16) & 0x7FL,
		(unsigned long)((long)(pc & 0xFFFFL) + d) & 0xFFFFL);
	return o + strlen(o);
}

/* the names of the bits of an n-bit field that equal `set', high bit first */
static char *
zlist(o, names, n, bits, set)
char *o;
unsigned short *names;
int n;
unsigned long bits;
int set;
{
	int i, any;

	any = 0;
	for (i = 0; i < n; i++)
		if ((int)((bits >> (n - 1 - i)) & 1) == set) {
			if (any)
				*o++ = ',';
			strcpy(o, zstr[names[i]]);
			o += strlen(o);
			any = 1;
		}
	*o = '\0';
	return o;
}

/* the signed count of a static shift; a byte shift's is in the low byte */
static long
zcount(p)
struct zop *p;
{
	long v;

	v = zword((int)p->word);
	if (v < 0)
		return 0L;
	if (p->width == 8) {
		v &= 0xFFL;
		if (v & 0x80L)
			v -= 0x100L;
	} else if (v & 0x8000L)
		v -= 0x10000L;
	return v;
}

static char *
zoperand(o, p, pc)
char *o;
struct zop *p;
unsigned long pc;
{
	unsigned long f;
	long v, d;
	int r;

	f = zfield(p);
	r = (int)((zw[0] >> p->shift) & 0xFL);
	switch (p->kind) {
	case ZK_R:
	case ZK_RB:
	case ZK_RR:
	case ZK_RQ:
	case ZK_IR:
	case ZK_IRR:
		return zreg(o, (int)p->kind, f);
	case ZK_IM8:
		/* a byte operand repeats in both halves of its word */
		v = zword((int)p->word);
		if (v < 0)
			strcpy(o, "#?");
		else
			sprintf(o, "#0x%02lX", p->aux ? v & 0xFFL : (v >> 8) & 0xFFL);
		break;
	case ZK_IM16:
		v = zword((int)p->word);
		if (v < 0)
			strcpy(o, "#?");
		else
			sprintf(o, "#0x%04lX", v);
		break;
	case ZK_PORT:
		v = zword((int)p->word);
		if (v < 0)
			strcpy(o, "?");
		else
			sprintf(o, "0x%04lX", v);
		break;
	case ZK_IM32:
		v = zword((int)p->word);
		d = zword((int)p->word + 1);
		if (v < 0 || d < 0)
			strcpy(o, "#?");
		else
			sprintf(o, "#0x%04lX%04lX", v, d);
		break;
	case ZK_NUM:
		sprintf(o, "#%ld", (long)f + (long)p->aux);
		break;
	case ZK_SHIFT:
		v = zcount(p);
		sprintf(o, "#%ld", v < 0 ? -v : v);
		break;
	case ZK_DA:
		return zaddr(o, (int)p->word);
	case ZK_X:
		o = zaddr(o, (int)p->word);
		sprintf(o, "(R%d)", r);
		break;
	case ZK_BA:
		v = zword((int)p->word);
		if (v < 0)
			sprintf(o, "?(R%d)", r);
		else
			sprintf(o, "0x%04lX(R%d)", v, r);
		break;
	case ZK_BX:
		sprintf(o, "R%d(R%d)", (int)((zw[0] >> p->aux) & 0xFL), (int)f);
		break;
	case ZK_RA16:
		v = zword((int)p->word);
		if (v < 0) {
			strcpy(o, "?");
			break;
		}
		if (v & 0x8000L)
			v -= 0x10000L;
		sprintf(o, "0x%04lX", (unsigned long)((long)(pc & 0xFFFFL) + 4 + v) & 0xFFFFL);
		break;
	case ZK_RA8:
		d = (long)f;
		if (d & 0x80L)
			d -= 0x100L;
		return ztarget(o, pc, 2 + 2 * d);
	case ZK_RA12:
		d = (long)f;
		if (d & 0x800L)
			d -= 0x1000L;
		return ztarget(o, pc, 2 - 2 * d);
	case ZK_RA7:
		return ztarget(o, pc, 2 - 2 * (long)f);
	case ZK_CC:
		strcpy(o, zstr[zcc[(int)f]]);
		break;
	case ZK_FLG:
		return zlist(o, zflg, 4, f, 1);
	case ZK_INT:
		return zlist(o, zint, 2, f, 0);
	case ZK_LIT:
		strcpy(o, zstr[p->aux]);
		break;
	default:
		strcpy(o, "?");
		break;
	}
	return o + strlen(o);
}

static struct zform *
zmatch(w0, w1)
unsigned long w0;
long w1;
{
	struct zform *f;
	int i, k;

	for (i = 0; i < ZNFORM; i++) {
		f = &zform[i];
		if ((w0 & f->mask) != f->val)
			continue;
		for (k = 0; k < 16; k += 4)
			if (((f->nz >> k) & 1) && ((w0 >> k) & 0xFL) == 0)
				break;
		if (k < 16)
			continue;
		if (f->m1 && (w1 < 0 || ((unsigned long)w1 & f->m1) != f->v1))
			continue;
		return f;
	}
	return (struct zform *)0;
}

int
z8kdis(w, nw, pc, mnem, ops)
unsigned long *w;
int nw;
unsigned long pc;
char **mnem, *ops;
{
	struct zform *f;
	struct zop *p;
	char *o;
	int i;

	*mnem = "ILLEGAL";
	ops[0] = '\0';
	if (nw < 1)
		return 1;
	if (nw > 4)
		nw = 4;
	zw = w;
	znw = nw;
	zseg = 0;
	f = zmatch(w[0] & 0xFFFFL, nw > 1 ? (long)(w[1] & 0xFFFFL) : -1L);
	if (f == (struct zform *)0)
		return 1;
	zseg = f->segw;
	zlong = zseg && zseg < nw && (w[zseg] & 0x8000L);
	*mnem = zstr[f->mnem];
	o = ops;
	for (i = 0; i < (int)f->nop; i++) {
		p = &zop[f->op + i];
		if (i)
			*o++ = ',';
		o = zoperand(o, p, pc);
		if (f->alt && p->kind == ZK_SHIFT && zcount(p) < 0)
			*mnem = zstr[f->alt];
	}
	*o = '\0';
	return f->nw + zlong;
}
