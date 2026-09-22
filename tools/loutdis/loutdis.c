/*
 * loutdis -- disassemble a Coherent Z8001 l.out/n.out object.
 *
 *	loutdis FILE		far-vs-near pointer histogram of the text
 *	loutdis FILE -v		... plus the full disassembly listing
 *	loutdis FILE -hdr	the parsed header and section sizes
 *	loutdis FILE -syms	the symbol table
 *	loutdis FILE -fn NAME	disassemble one function, by symbol
 *
 * The instruction knowledge is not here: it is in z8ktab.h, generated from a
 * verified decoder, and z8kdis.c applies it.  This file reads the container and
 * prints.
 *
 * Header (n.out.h): short l_magic,l_flag,l_machine,l_tbase; long l_ssize[9];
 * long l_entry -- 48 bytes, text following.  Code words are big-endian, but the
 * integer FIELDS of recovered objects are not always stored the same way, so
 * the 16- and 32-bit field encodings are detected from invariants (magic 0407,
 * l_tbase == the header size, section sizes consistent with the file length)
 * rather than assumed.
 *
 * K&R C, 16-bit int safe: every header field is read through unsigned long, or
 * a 0xFFFF field comes back negative on the target.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

#include "z8kdis.h"

#define	LMAGIC	0407
#define	NLSEG	9
#define	SYMSIZE	22		/* char[16] + short ls_type + long ls_addr */
#define	SEGSHRI	0
#define	SEGPRVI	1
#define	SEGSYM	7

char *progname = "loutdis";

static char *segname[NLSEG] = {
	"SHRI", "PRVI", "BSSI", "SHRD", "PRVD", "BSSD", "DEBUG", "SYM", "REL"
};

/* the sections that occupy bytes on disk; BSSI and BSSD are size only. */
static int filebacked[7] = { 0, 1, 3, 4, 6, 7, 8 };

static char *d16name[2] = { "BE", "LE" };
static char *d32name[4] = { "BE", "LE", "PDP", "PDPLE" };

struct hdr {
	int d16, d32;
	int hsize, stride, entryoff;
	unsigned long flag, machine, tbase;
	unsigned long ssize[NLSEG];
	unsigned long entry;
};

struct sym {
	char name[17];
	unsigned long typ, addr;
	int seg;
};

static void
fatal(what, detail)
char *what, *detail;
{
	if (detail)
		fprintf(stderr, "%s: %s: %s\n", progname, what, detail);
	else
		fprintf(stderr, "%s: %s\n", progname, what);
	exit(1);
}

static unsigned long
u16of(dec, b)
int dec;
unsigned char *b;
{
	if (dec == 0)
		return ((unsigned long)b[0] << 8) | b[1];
	return ((unsigned long)b[1] << 8) | b[0];
}

static unsigned long
u32of(dec, b)
int dec;
unsigned char *b;
{
	switch (dec) {
	case 0:
		return ((unsigned long)b[0] << 24) | ((unsigned long)b[1] << 16) |
		       ((unsigned long)b[2] << 8) | b[3];
	case 1:
		return ((unsigned long)b[3] << 24) | ((unsigned long)b[2] << 16) |
		       ((unsigned long)b[1] << 8) | b[0];
	case 2:
		return ((unsigned long)b[2] << 24) | ((unsigned long)b[3] << 16) |
		       ((unsigned long)b[0] << 8) | b[1];
	}
	return ((unsigned long)b[1] << 24) | ((unsigned long)b[0] << 16) |
	       ((unsigned long)b[3] << 8) | b[2];
}

/* detect chooses the field encodings that make the header self-consistent:
 * magic 0407, l_tbase == the header size, and 48 + the file-backed section
 * sizes closest to the real file length. */
static int
detect(data, n, h)
unsigned char *data;
long n;
struct hdr *h;
{
	static int lhsize[2] = { 48, 88 };
	static int lstride[2] = { 4, 8 };
	static int lentry[2] = { 44, 80 };
	struct hdr t;
	long best, score, total;
	int lay, d16, d32, i, ok;

	best = -1;
	for (lay = 0; lay < 2; lay++) {
		for (d16 = 0; d16 < 2; d16++) {
			if (u16of(d16, data) != LMAGIC)
				continue;
			if ((int)u16of(d16, data + 6) != lhsize[lay])
				continue;
			for (d32 = 0; d32 < 4; d32++) {
				t.d16 = d16;
				t.d32 = d32;
				t.hsize = lhsize[lay];
				t.stride = lstride[lay];
				t.entryoff = lentry[lay];
				t.flag = u16of(d16, data + 2);
				t.machine = u16of(d16, data + 4);
				t.tbase = u16of(d16, data + 6);
				for (i = 0; i < NLSEG; i++)
					t.ssize[i] = u32of(d32, data + 8 + lstride[lay] * i);
				t.entry = u32of(d32, data + lentry[lay]);
				total = t.hsize;
				ok = 1;
				for (i = 0; i < 7; i++) {
					if (t.ssize[filebacked[i]] > (unsigned long)n) {
						ok = 0;
						break;
					}
					total += (long)t.ssize[filebacked[i]];
				}
				if (!ok)
					continue;
				score = total - n;
				if (score < 0)
					score = -score;
				if (best < 0 || score < best) {
					best = score;
					*h = t;
				}
			}
		}
	}
	return best >= 0;
}

static long
segoffset(h, s)
struct hdr *h;
int s;
{
	long off;
	int i, j;

	off = h->hsize;
	for (i = 0; i < s; i++)
		for (j = 0; j < 7; j++)
			if (filebacked[j] == i)
				off += (long)h->ssize[i];
	return off;
}

static int
textseg(h)
struct hdr *h;
{
	return h->ssize[SEGSHRI] > 0 ? SEGSHRI : SEGPRVI;
}

/* the symbol table, in file order. */
static int
symbols(h, data, n, out)
struct hdr *h;
unsigned char *data;
long n;
struct sym *out;
{
	long start, o;
	int i, k, cnt;

	start = segoffset(h, SEGSYM);
	cnt = (int)(h->ssize[SEGSYM] / SYMSIZE);
	for (i = 0; i < cnt; i++) {
		o = start + (long)i * SYMSIZE;
		if (o + SYMSIZE > n)
			return i;
		for (k = 0; k < 16; k++)
			out[i].name[k] = (char)data[o + k];
		out[i].name[16] = '\0';
		for (k = 0; k < 16; k++)
			if (out[i].name[k] == '\0')
				break;
		out[i].name[k] = '\0';
		out[i].typ = u16of(h->d16, data + o + 16);
		out[i].addr = u32of(h->d32, data + o + 18);
		out[i].seg = (int)(out[i].typ & 017);
	}
	return cnt;
}

/* stable, by address: two symbols at one address keep file order. */
static void
symsort(s, n)
struct sym *s;
int n;
{
	struct sym t;
	int i, j;

	for (i = 1; i < n; i++) {
		t = s[i];
		for (j = i; j > 0 && s[j - 1].addr > t.addr; j--)
			s[j] = s[j - 1];
		s[j] = t;
	}
}

/* cmpreg names the register the block compares really compare against memory.
 * Their second word is `0000 rrrr dddd cccc': rrrr is the counter and dddd the
 * compared register -- a BYTE register in the B forms.  The decoder prints that
 * field as @RRd rounded down to an even pair, which reads as an access through
 * a register pair the instruction never touches. */
static char *
cmpreg(mnem, w, nw, buf)
char *mnem;
unsigned long *w;
int nw;
char *buf;
{
	static char *word[4] = { "CPI", "CPD", "CPIR", "CPDR" };
	static char *byte[4] = { "CPIB", "CPDB", "CPIRB", "CPDRB" };
	int i, d;

	if (nw < 2)
		return 0;
	d = (int)((w[1] >> 4) & 0xF);
	for (i = 0; i < 4; i++)
		if (strcmp(mnem, byte[i]) == 0) {
			if (d < 8)
				sprintf(buf, "RH%d", d);
			else
				sprintf(buf, "RL%d", d - 8);
			return buf;
		}
	for (i = 0; i < 4; i++)
		if (strcmp(mnem, word[i]) == 0) {
			sprintf(buf, "R%d", d);
			return buf;
		}
	return 0;
}

/* fixops rewrites the first operand of a block compare to that register. */
static void
fixops(mnem, ops, w, nw)
char *mnem, *ops;
unsigned long *w;
int nw;
{
	char buf[8], tmp[ZOPSMAX];
	char *r, *comma;

	r = cmpreg(mnem, w, nw, buf);
	if (r == 0)
		return;
	comma = strchr(ops, ',');
	if (comma == 0) {
		strcpy(ops, r);
		return;
	}
	strcpy(tmp, comma);
	strcpy(ops, r);
	strcat(ops, tmp);
}

static int
hassub(s, sub)
char *s, *sub;
{
	return strstr(s, sub) != 0;
}

static int
endswith(s, c)
char *s;
int c;
{
	int n;

	n = (int)strlen(s);
	return n > 0 && s[n - 1] == (char)c;
}

static char *hist[12] = {
	"LDL", "LD", "LDB", "PUSHL", "POPL", "PUSH", "LDM", "LDIRB", "LDIR",
	"CALL", "CALR", "LDA"
};

/* disassemble a run of text words, optionally printing each instruction.
 * Counts go into *total, *far, *near and the mnemonic histogram. */
static void
disasm(w, nwords, base, print, total, far, near, counts)
unsigned long *w;
long nwords, base;
int print;
long *total, *far, *near;
long *counts;
{
	char ops[ZOPSMAX], *mnem;
	long pc;
	int nw, wc, i;

	for (pc = 0; pc < nwords;) {
		nw = (int)(nwords - pc);
		if (nw > 4)
			nw = 4;
		wc = z8kdis(w + pc, nw, (unsigned long)(base + pc * 2), &mnem, ops);
		if (wc <= 0) {
			pc++;
			continue;
		}
		(*total)++;
		for (i = 0; i < 12; i++)
			if (strcmp(mnem, hist[i]) == 0)
				counts[i]++;
		fixops(mnem, ops, w + pc, nw);
		if (endswith(mnem, 'L') || hassub(ops, "@RR") ||
		    (hassub(ops, "RR") && hassub(ops, "(")))
			(*far)++;
		if (hassub(ops, "@R") && !hassub(ops, "@RR"))
			(*near)++;
		if (print)
			printf("  %04lx: %-8s %s\n",
			       (unsigned long)(base + pc * 2), mnem, ops);
		pc += wc;
	}
}

/* the text segment as big-endian words. */
static long
textwords(data, n, off, size, w)
unsigned char *data;
long n, off, size;
unsigned long *w;
{
	long i, cnt;

	if (off + size > n)
		size = n - off;
	cnt = size / 2;
	for (i = 0; i < cnt; i++)
		w[i] = ((unsigned long)data[off + 2 * i] << 8) | data[off + 2 * i + 1];
	return cnt;
}

int
main(argc, argv)
int argc;
char **argv;
{
	static long counts[12];
	struct hdr h;
	struct sym *syms;
	unsigned char *data;
	unsigned long *w;
	FILE *f;
	char *path, *fn;
	long n, toff, tsize, nwords, total, far, near, lbase, start, end;
	int i, k, verbose, dohdr, dosyms, seg, nsym, found;

#ifdef _WIN32
	_setmode(_fileno(stdout), _O_BINARY);
#endif
	verbose = dohdr = dosyms = 0;
	path = fn = 0;
	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-v") == 0)
			verbose = 1;
		else if (strcmp(argv[i], "-hdr") == 0)
			dohdr = 1;
		else if (strcmp(argv[i], "-syms") == 0)
			dosyms = 1;
		else if (strcmp(argv[i], "-fn") == 0) {
			if (++i < argc)
				fn = argv[i];
		} else if (argv[i][0] == '-')
			fatal("unknown option", argv[i]);
		else if (path == 0)
			path = argv[i];
	}
	if (path == 0) {
		fprintf(stderr, "usage: %s FILE [-v|-hdr|-syms|-fn NAME]\n", progname);
		return 2;
	}
	if ((f = fopen(path, "rb")) == 0)
		fatal("cannot read", path);
	fseek(f, 0L, SEEK_END);
	n = ftell(f);
	rewind(f);
	if (n < 48)
		fatal("too short for an l.out header", path);
	if ((data = (unsigned char *)malloc((size_t)n)) == 0)
		fatal("out of memory", (char *)0);
	if ((long)fread(data, 1, (size_t)n, f) != n)
		fatal("short read", path);
	fclose(f);
	if (!detect(data, n, &h))
		fatal("no l.out layout (48/88-byte) matches magic 0407", path);

	if (dohdr) {
		printf("%s: %ld bytes\n", path, n);
		printf("field encoding: 16-bit=%s 32-bit=%s\n",
		       d16name[h.d16], d32name[h.d32]);
		printf("flag=%s%lo machine=%lu tbase=%lu entry=0x%lx\n",
		       h.flag == 0 ? "" : "0", h.flag, h.machine, h.tbase, h.entry);
		for (i = 0; i < NLSEG; i++)
			printf("  l_ssize[%-5s] = %lu\n", segname[i], h.ssize[i]);
		return 0;
	}

	nsym = (int)(h.ssize[SEGSYM] / SYMSIZE);
	syms = (struct sym *)malloc((size_t)(nsym + 1) * sizeof(struct sym));
	if (syms == 0)
		fatal("out of memory", (char *)0);
	nsym = symbols(&h, data, n, syms);

	if (dosyms) {
		symsort(syms, nsym);
		printf("%s: %d symbols (16-bit=%s 32-bit=%s)\n", path, nsym,
		       d16name[h.d16], d32name[h.d32]);
		for (i = 0; i < nsym; i++)
			printf("  %08lx  %-6s %s\n", syms[i].addr,
			       syms[i].seg < NLSEG ? segname[syms[i].seg] : "?",
			       syms[i].name);
		return 0;
	}

	seg = textseg(&h);
	toff = segoffset(&h, seg);
	tsize = (long)h.ssize[seg];
	w = (unsigned long *)malloc((size_t)(tsize / 2 + 4) * sizeof(unsigned long));
	if (w == 0)
		fatal("out of memory", (char *)0);
	total = far = near = 0;

	if (fn) {
		/* text symbols, sorted; the window is this symbol to the next. */
		k = 0;
		for (i = 0; i < nsym; i++)
			if (syms[i].seg == seg)
				syms[k++] = syms[i];
		nsym = k;
		symsort(syms, nsym);
		start = 0;
		end = tsize;
		found = 0;
		for (i = 0; i < nsym; i++)
			if (strcmp(syms[i].name, fn) == 0) {
				start = (long)syms[i].addr;
				if (i + 1 < nsym)
					end = (long)syms[i + 1].addr;
				found = 1;
				break;
			}
		if (!found) {
			fprintf(stderr, "symbol \"%s\" not found in text segment %s\n",
				fn, segname[seg]);
			return 1;
		}
		printf("%s  %s [0x%lx..0x%lx)  (%ld bytes)\n", path, fn,
		       (unsigned long)start, (unsigned long)end, end - start);
		/* symbol addresses are absolute in a linked image, 0-based in a .o */
		lbase = 0;
		if (nsym > 0 && (long)syms[0].addr >= tsize)
			lbase = (long)syms[0].addr;
		nwords = textwords(data, n, toff + start - lbase, end - start, w);
		disasm(w, nwords, start, 1, &total, &far, &near, counts);
		return 0;
	}

	nwords = textwords(data, n, toff, tsize, w);
	disasm(w, nwords, 0L, verbose, &total, &far, &near, counts);
	printf("%s: text=%s %ld insns, FAR-ish(@RR/L/RRn-base)=%ld  near(@Rn single)=%ld\n",
	       path, segname[seg], total, far, near);
	for (i = 0; i < 12; i++)
		if (counts[i] > 0)
			printf("    %-6s %ld\n", hist[i], counts[i]);
	return 0;
}
