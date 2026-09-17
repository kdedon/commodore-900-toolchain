/*
 * The Z8001 decode core: it walks the generated table in z8ktab.h and nothing
 * else.  No opcode, no field position and no register name is written here --
 * all of that is in the table, which the generator read out of a verified
 * decoder.  This file only knows how to APPLY a table row: match the form,
 * render its pieces, and compute the length.
 *
 * K&R C, 16-bit int safe: every instruction word and address is carried in an
 * unsigned long.
 */
#include <stdio.h>
#include <string.h>

#include "z8kdis.h"
#include "z8ktab.h"

static char *
zappend(p, s)
char *p, *s;
{
	while (*s)
		*p++ = *s++;
	*p = '\0';
	return p;
}

/* the word a src code names: 0..3 directly, ZSRC_POST1/2 the word after a
 * segmented address, which is one or two words long. */
static int
zwordidx(src, w, nw)
int src;
unsigned long *w;
int nw;
{
	switch (src) {
	case ZSRC_POST1:
		if (nw > 1 && (w[1] & 0x8000L))
			return 3;
		return 2;
	case ZSRC_POST2:
		if (nw > 2 && (w[2] & 0x8000L))
			return 4;
		return 3;
	}
	return src;
}

static unsigned long
zwordval(idx, w, nw)
int idx;
unsigned long *w;
int nw;
{
	if (idx < 0 || idx >= nw || idx >= 4)
		return 0L;
	return w[idx] & 0xFFFFL;
}

static char *
zsegtarget(p, addr)
char *p;
unsigned long addr;
{
	sprintf(p, "0x%02lX:0x%04lX", (addr >> 16) & 0x7FL, addr & 0xFFFFL);
	return p + strlen(p);
}

static char *
zstyle(p, style, src, w0, w, nw, pc)
char *p;
int style, src;
unsigned long w0, *w;
int nw;
unsigned long pc;
{
	int k;
	long d;
	unsigned long a;

	k = zwordidx(src, w, nw);
	switch (style) {
	case ZS_HEX4:
		sprintf(p, "0x%04lX", zwordval(k, w, nw));
		break;
	case ZS_HEX2HI:
		sprintf(p, "0x%02lX", zwordval(k, w, nw) >> 8);
		break;
	case ZS_HEX2LO:
		sprintf(p, "0x%02lX", zwordval(k, w, nw) & 0xFFL);
		break;
	case ZS_HEX8:
		sprintf(p, "0x%08lX",
			(zwordval(k, w, nw) << 16) | zwordval(k + 1, w, nw));
		break;
	case ZS_DECS:
		d = (long)zwordval(k, w, nw);
		if (d >= 0x8000L)
			d -= 0x10000L;
		sprintf(p, "%ld", d);
		break;
	case ZS_SEGADDR:
		if (k >= nw) {
			strcpy(p, "?");
			break;
		}
		a = w[k] & 0xFFFFL;
		if (a & 0x8000L) {
			if (k + 1 >= nw)
				sprintf(p, "0x%02lX:?", (a >> 8) & 0x7FL);
			else
				sprintf(p, "0x%02lX:0x%04lX", (a >> 8) & 0x7FL,
					zwordval(k + 1, w, nw));
		} else
			sprintf(p, "0x%02lX:0x%04lX", (a >> 8) & 0x7FL, a & 0xFFL);
		break;
	case ZS_PCREL16:
		d = (long)zwordval(k, w, nw);
		if (d >= 0x8000L)
			d -= 0x10000L;
		sprintf(p, "0x%04lX", ((unsigned long)((long)pc + d + 4)) & 0xFFFFL);
		break;
	case ZS_PCREL8:
		d = (long)(w0 & 0xFFL);
		if (d & 0x80L)
			d -= 0x100L;
		return zsegtarget(p, (unsigned long)((long)pc + 2 + (d << 1)));
	case ZS_PCREL12:
		d = (long)(w0 & 0xFFFL);
		if (d & 0x800L)
			d -= 0x1000L;
		return zsegtarget(p, (unsigned long)((long)pc - (d << 1) + 2));
	case ZS_DJNZ:
		d = (long)(w0 & 0x7FL);
		return zsegtarget(p, (unsigned long)((long)pc - (d << 1) + 2));
	default:
		strcpy(p, "?style");
		break;
	}
	return p + strlen(p);
}

static struct zform *
zmatch(w0)
unsigned long w0;
{
	int i;

	for (i = 0; i < ZNFORM; i++)
		if ((w0 & zform[i].mask) == zform[i].val)
			return &zform[i];
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
	struct zvar *v;
	struct zpiece *p;
	unsigned long field, word;
	char *o;
	int i, wc, idx, lf;

	*mnem = "ILLEGAL";
	ops[0] = '\0';
	if (nw < 1)
		return 1;
	if (nw > 4)
		nw = 4;
	f = zmatch(w[0] & 0xFFFFL);
	if (f == (struct zform *)0)
		return 1;
	/* the long form of a segmented address at w[1] is a second word, and so
	 * a different template, not a different field value. */
	lf = (nw > 1 && (w[1] & 0x8000L)) ? 1 : 0;
	v = &zvar[zvidx[f->var0 + (nw - 1) * 2 + lf]];
	if (v->mtab >= 0)
		*mnem = zstr[ztab[v->mtab + (int)(zwordval(1, w, nw) & 0xFL)]];
	else
		*mnem = zstr[v->mnem];

	o = ops;
	for (i = 0; i < (int)v->npiece; i++) {
		p = &zpiece[v->piece + i];
		switch (p->kind) {
		case ZP_LIT:
			o = zappend(o, zstr[p->arg]);
			break;
		case ZP_TAB:
			if (p->src == 0)
				word = w[0] & 0xFFFFL;
			else {
				idx = zwordidx((int)p->src, w, nw);
				word = zwordval(idx, w, nw);
			}
			field = (word >> p->shift) & ((1L << p->width) - 1);
			o = zappend(o, zstr[ztab[p->arg + (int)field]]);
			break;
		case ZP_FMT:
			o = zstyle(o, (int)p->arg, (int)p->src, w[0] & 0xFFFFL,
				   w, nw, pc);
			break;
		}
	}

	wc = f->wc;
	if ((f->flags & 1) && wc >= 3 && nw >= 2 && (w[1] & 0x8000L) == 0)
		wc--;
	if ((f->flags & 2) && wc >= 4 && nw >= 3 && (w[2] & 0x8000L) == 0)
		wc--;
	return wc;
}
