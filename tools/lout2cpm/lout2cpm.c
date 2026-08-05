/*
 * lout2cpm -- wrap a linked MWC (ld-z8001) l.out into a CP/M-8000 x.out that
 * the may83 pgmld accepts.
 *
 *	usage:  lout2cpm INPUT.lout OUTPUT.Z8K
 *
 * Container choice (stock-format rules, XOUT.H / pgmld.c):
 *   - entry segment != 0  ->  0xEE01 segmented executable.  The program was
 *     linked flat at its CPU segment base (ld -R 0xSS000000); pgmld's
 *     segmented path places each file segment at x_sg_no<<24, so x_sg_no
 *     carries the link segment and the entry must be at segment offset 0
 *     (pgmld enters at the first text byte).
 *   - entry segment == 0  ->  0xEE03 non-segmented executable, loaded at
 *     offset 0 of the TPA segment (only correct for genuinely non-segmented
 *     code linked at 0 -- e.g. hand-written nonseg assembly).
 *
 * No relocation records are emitted: the x.out formats place non-segmented
 * programs positionally (the TPA mapping supplies the base) and segmented
 * programs at their absolute link segment, so an absolutely-linked l.out
 * needs none, and the may83 loader processes none.
 *
 * l.out header (ld-z8001 output, verified field encoding: 16-bit fields
 * little-endian, 32-bit fields PDP-swapped little-endian words):
 *
 *	off 0  l_magic 0407    off 6  l_tbase 48 (= header size)
 *	off 8  l_ssize[9]: SHRI PRVI BSSI SHRD PRVD BSSD DEBUG SYM REL
 *	off 44 l_entry (seg<<24 | offset)
 *
 * text = SHRI+PRVI+BSSI, data = SHRD+PRVD, bss = BSSD; text and data bytes
 * follow the header in that order and are copied verbatim.
 *
 * Reads and writes by explicit byte offsets -- never by struct overlay -- so
 * the same source is correct under the LP64 host gcc and under the ILP32 MWC
 * compiler.  K&R C; host tool, distributed with the toolchain.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define	LMAGIC	0407		/* l_magic			*/
#define	HDRSIZE	48		/* sizeof(struct ldheader)	*/
#define	NLSEG	9		/* l_ssize[] entries		*/

#define	XSXMAGIC   0xEE01	/* segmented executable			*/
#define	XNXNMAGIC  0xEE03	/* non-segmented executable, non-shared	*/

#define	SG_BSS	1
#define	SG_COD	3
#define	SG_DAT	5

#define	SEGLEN	0x10000L	/* one Z8000 segment	*/
#define	BPLEN	0x100		/* pgmld base page	*/
#define	DEFSTACK 0x100		/* pgmld DEFSTACK	*/

#define	XHDRSIZE (16 + 3 * 4)	/* x_hdr + three x_sg entries */

char	*progname = "lout2cpm";

/* out is written by the b16/b32/copy helpers below; op is the put offset. */
unsigned char	*out;
long		op;

void
fatal(what, detail)
char *what, *detail;
{
	if (detail)
		fprintf(stderr, "%s: %s: %s\n", progname, what, detail);
	else
		fprintf(stderr, "%s: %s\n", progname, what);
	exit(1);
}

/* l.out 16-bit field: little-endian. */
long
le16(b)
unsigned char *b;
{
	return (long)b[0] | ((long)b[1] << 8);
}

/* l.out 32-bit field: high 16-bit word first, each word little-endian. */
long
pdple32(b)
unsigned char *b;
{
	return (le16(b) << 16) | le16(b + 2);
}

void
b16(v)
long v;
{
	out[op++] = (unsigned char)(v >> 8);
	out[op++] = (unsigned char)v;
}

void
b32(v)
long v;
{
	b16((v >> 16) & 0xFFFF);
	b16(v & 0xFFFF);
}

/* Read the whole file; *lenp gets its size. */
unsigned char *
slurp(name, lenp)
char *name;
long *lenp;
{
	FILE *f;
	long n;
	unsigned char *b;

	if ((f = fopen(name, "rb")) == NULL)
		fatal(name, "cannot open");
	if (fseek(f, 0L, 2) != 0)
		fatal(name, "cannot seek");
	n = ftell(f);
	rewind(f);
	if ((b = (unsigned char *)malloc((size_t)(n ? n : 1))) == NULL)
		fatal(name, "out of memory");
	if (n && fread((char *)b, 1, (size_t)n, f) != (size_t)n)
		fatal(name, "short read");
	fclose(f);
	*lenp = n;
	return b;
}

/* Reject a segment that cannot be expressed as an x_sg length. */
void
fits(fname, what, n)
char *fname, *what;
long n;
{
	char msg[128];

	if (n > 0xFFFFL) {
		sprintf(msg, "%s: %s is %ld bytes; one x_sg holds at most 65535",
			fname, what, n);
		fatal(msg, (char *)0);
	}
}

int
main(argc, argv)
int argc;
char **argv;
{
	unsigned char *lout;
	long len, ss[NLSEG], entry, text, data, bss, seg, magic;
	char msg[128], *kind, kbuf[48];
	int i, sgno;
	FILE *f;

	if (argc != 3) {
		fprintf(stderr, "usage: lout2cpm INPUT.lout OUTPUT.Z8K\n");
		exit(2);
	}
	lout = slurp(argv[1], &len);

	if (len < HDRSIZE) {
		sprintf(msg, "%s: shorter than an l.out header (%ld bytes)",
			argv[1], len);
		fatal(msg, (char *)0);
	}
	if (le16(lout) != LMAGIC) {
		sprintf(msg, "%s: bad l.out magic 0x%04lx", argv[1], le16(lout));
		fatal(msg, (char *)0);
	}
	if (le16(lout + 6) != HDRSIZE) {
		sprintf(msg,
			"%s: l_tbase %ld != %d (not a linked ld-z8001 l.out)",
			argv[1], le16(lout + 6), HDRSIZE);
		fatal(msg, (char *)0);
	}
	for (i = 0; i < NLSEG; i++)
		ss[i] = pdple32(lout + 8 + 4 * i);
	entry = pdple32(lout + 44);

	text = ss[0] + ss[1] + ss[2];	/* SHRI+PRVI+BSSI (BSSI is 0 here) */
	data = ss[3] + ss[4];		/* SHRD+PRVD			  */
	bss = ss[5];			/* BSSD				  */

	fits(argv[1], "text", text);
	fits(argv[1], "data", data);
	fits(argv[1], "bss", bss);

	if (len < HDRSIZE + text + data) {
		sprintf(msg, "%s: file truncated: need %ld text + %ld data bytes",
			argv[1], text, data);
		fatal(msg, (char *)0);
	}
	if (text + data + bss + BPLEN + DEFSTACK > SEGLEN) {
		sprintf(msg,
	"%s: text+data+bss+basepage+stack = %#lx exceeds one %#lx-byte segment",
			argv[1], text + data + bss + BPLEN + DEFSTACK, SEGLEN);
		fatal(msg, (char *)0);
	}

	seg = (entry >> 24) & 0xFF;
	if (entry & 0x00FFFFFFL) {
		sprintf(msg, "%s: entry 0x%08lx is not at segment offset 0 (pgmld enters at the first text byte; link with the entry first at -R 0xSS000000)",
			argv[1], entry);
		fatal(msg, (char *)0);
	}

	magic = XNXNMAGIC;
	sgno = 0;
	if (seg != 0) {
		magic = XSXMAGIC;
		sgno = (int)seg;
	}

	if ((out = (unsigned char *)malloc((size_t)(XHDRSIZE + text + data)))
	    == NULL)
		fatal(argv[2], "out of memory");
	op = 0;

	/* struct x_hdr (big-endian, Z8000 native: pgmld reads bytes into
	   structs), then the three x_sg entries in load order. */
	b16(magic);
	b16(3L);			/* x_nseg  */
	b32(text + data);		/* x_init  */
	b32(0L);			/* x_reloc */
	b32(0L);			/* x_symb  */
	out[op++] = (unsigned char)sgno; out[op++] = SG_COD; b16(text);
	out[op++] = (unsigned char)sgno; out[op++] = SG_DAT; b16(data);
	out[op++] = (unsigned char)sgno; out[op++] = SG_BSS; b16(bss);
	memcpy((char *)out + op, (char *)lout + HDRSIZE, (size_t)(text + data));
	op += text + data;

	if ((f = fopen(argv[2], "wb")) == NULL)
		fatal(argv[2], "cannot create");
	if (fwrite((char *)out, 1, (size_t)op, f) != (size_t)op || fclose(f))
		fatal(argv[2], "write failed");

	if (magic == XSXMAGIC) {
		sprintf(kbuf, "0xEE01 segmented (segment 0x%02X)", sgno);
		kind = kbuf;
	} else
		kind = "0xEE03 non-segmented";
	printf("%s: %s, text %ld, data %ld, bss %ld -> %s (%ld bytes)\n",
		argv[1], kind, text, data, bss, argv[2], op);
	return 0;
}
