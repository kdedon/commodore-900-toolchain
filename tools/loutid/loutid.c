/*
 * loutid -- say what a file IS, from its first bytes, and fail if it is not
 * what was asked for.
 *
 *	loutid FILE...			print one line per file
 *	loutid -q -m z8001 FILE...	silent unless a file is not a Z8001
 *					l.out or a Z8001 archive; exit 1 then
 *	loutid -e FILE...		also print an l.out's entry point, as
 *					`entry=0x3000000' (segment 3, offset 0)
 *	loutid -s FILE...		also list an l.out's symbol table, one
 *					`  SHRI 0x300014a main_' line per symbol
 *
 * WHY THIS EXISTS.  An environment tree is a directory of binaries that a GUEST
 * will execute.  Every host build harness runs the host compiler too, and a
 * staging copy that grabbed the wrong artifact -- the host cc0 instead of the
 * target one, an x86 `ar' instead of the Coherent one -- produces a tree that
 * looks complete, mounts, and fails only inside the guest with a message about
 * a bad magic number.  The cost of checking is eight bytes per file, so it is
 * checked rather than assumed.
 *
 * WHAT IT READS.  The COHERENT 32-bit object header (include/n.out.h), which is
 * the Z8001 native format for assembler output, linker output and kernel exec
 * input alike:
 *
 *	off 0	short l_magic	 0407
 *	off 2	short l_flag	 LF_SHR 01 / LF_SEP 02 / LF_NRB 04 / LF_32 020
 *	off 4	short l_machine	 M_Z8001 4 (include/mtype.h)
 *	off 6	short l_tbase	 sizeof(struct ldheader), 48
 *	off 8	long l_ssize[9]
 *	off 44	long l_entry	 segment in the high word, offset in the low
 *
 * The sections follow the header in l_ssize[] order, except that the two BSS
 * sections (L_BSSI 2, L_BSSD 5) occupy no file space.  The symbol section L_SYM
 * (7) is an array of 22-byte struct ldsym: char ls_id[16] NUL-padded, short
 * ls_type (the section number in its low four bits, L_GLOBAL 020 above them),
 * long ls_addr (for a linked Z8001 program the segment is the high byte, so
 * 0x300014a is segment 3, offset 0x14a).
 *
 * 16-bit fields are little-endian on this target, so 0407 is `07 01'; a 32-bit
 * field is PDP-canonical, high word first, so entry 0x3000000 is `00 03 00 00'.
 * A header whose l_tbase is not 48 has no entry this reader will vouch for.  An
 * archive (include/ar.h) starts with the magic word 0177535 instead and holds
 * objects, which are checked individually.
 *
 * This is a HEADER identification, and it is deliberately not a disassembly:
 * it answers "is this a Z8001 program" for every file in a tree in milliseconds
 * and with no simulator and no sibling checkout.  Whether a program also RUNS
 * is a separate question that only the emulator can answer, and the environment
 * build asks it separately.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define L_MAGIC		0407
#define AR_MAGIC	0177535		/* include/ar.h ARMAG */
#define LDHDR_SIZE	48		/* sizeof(struct ldheader), and so l_tbase */
#define L_ENTRY_OFF	44
#define L_SYM		7
#define LDSYM_SIZE	22		/* sizeof(struct ldsym) */
#define NSEG		9
#define HEADREAD	4096
#define ARHDR		28		/* per-member header in a COHERENT archive */
#define MAXMACH		16		/* distinct machines named in one archive */

static char *sections[] = {
	"SHRI", "PRVI", "BSSI", "SHRD", "PRVD", "BSSD", "DEBUG", "SYM",
	"REL", "ABS", "REF"
};
#define NSECT	(sizeof(sections) / sizeof(sections[0]))

/* A growable string: a symbol listing is one line per symbol, and a linked
 * program has as many as it has. */
struct sbuf {
	char *p;
	long len, cap;
};

static void
sbinit(s)
struct sbuf *s;
{
	s->cap = 256;
	s->len = 0;
	s->p = malloc((size_t)s->cap);
	if (s->p == 0) {
		fprintf(stderr, "loutid: out of memory\n");
		exit(2);
	}
	s->p[0] = '\0';
}

static void
sbcat(s, t)
struct sbuf *s;
char *t;
{
	long n;

	n = (long)strlen(t);
	while (s->len + n + 1 > s->cap) {
		s->cap *= 2;
		s->p = realloc(s->p, (size_t)s->cap);
		if (s->p == 0) {
			fprintf(stderr, "loutid: out of memory\n");
			exit(2);
		}
	}
	memcpy(s->p + s->len, t, (size_t)n + 1);
	s->len += n;
}

/* 16-bit fields are little-endian.  unsigned long, not int: on the target an
 * int is 16 bits and a field of 0xFFFF would come back negative. */
static unsigned long
le16(b, off)
unsigned char *b;
long off;
{
	return (unsigned long)b[off] | ((unsigned long)b[off + 1] << 8);
}

/* 32-bit fields are PDP-canonical: high word first, each word little-endian. */
static unsigned long
pdp32(b, off)
unsigned char *b;
long off;
{
	return (le16(b, off) << 16) | le16(b, off + 2);
}

static char *
flagstr(f, buf)
int f;
char *buf;
{
	static int bits[] = { 01, 02, 04, 010, 020 };
	static char *names[] = { "shr", "sep", "nrb", "ker", "32" };
	int i, first;

	buf[0] = '\0';
	first = 1;
	for (i = 0; i < 5; i++) {
		if ((f & bits[i]) == 0)
			continue;
		if (!first)
			strcat(buf, "|");
		strcat(buf, names[i]);
		first = 0;
	}
	if (first)
		strcpy(buf, "-");
	return buf;
}

static char *
machname(m, buf)
int m;
char *buf;
{
	switch (m) {
	case 1:		return "pdp11";
	case 2:		return "vax";
	case 3:		return "s360";
	case 4:		return "z8001";
	case 5:		return "z8002";
	case 6:		return "i8086";
	case 7:		return "i8080";
	case 8:		return "m6800";
	case 9:		return "m6809";
	case 10:	return "m68000";
	case 11:	return "i386";
	}
	sprintf(buf, "machine%d", m);
	return buf;
}

/* The machine name of an l.out header at b[off:], or 0 when there is none. */
static char *
ident_lout(b, n, off, flags, mbuf)
unsigned char *b;
long n, off;
int *flags;
char *mbuf;
{
	if (n - off < 8)
		return 0;
	if (le16(b, off) != L_MAGIC)
		return 0;
	if (flags)
		*flags = (int)le16(b, off + 2);
	return machname((int)le16(b, off + 4), mbuf);
}

/* An l.out's l_entry, or 0 when the header is not the 48-byte one. */
static int
entry_of(b, n, ep)
unsigned char *b;
long n;
unsigned long *ep;
{
	if (n < LDHDR_SIZE || le16(b, 6) != LDHDR_SIZE)
		return 0;
	*ep = pdp32(b, L_ENTRY_OFF);
	return 1;
}

/* Append the L_SYM section as one `\n  SECT 0xADDR name' line per symbol.
 * Returns 0 when the header is not the 48-byte one or the section runs past
 * the end of the file. */
static int
symbols_of(b, n, sb)
unsigned char *b;
long n;
struct sbuf *sb;
{
	unsigned long sizes[NSEG], off, end, addr;
	long o;
	int i, typ;
	char name[17], line[64], *sect, sbuf2[16];

	if (n < LDHDR_SIZE || le16(b, 6) != LDHDR_SIZE)
		return 0;
	for (i = 0; i < NSEG; i++)
		sizes[i] = pdp32(b, 8 + 4 * i);
	off = LDHDR_SIZE;
	for (i = 0; i < L_SYM; i++)
		if (i != 2 && i != 5)		/* L_BSSI, L_BSSD hold no file space */
			off += sizes[i];
	end = off + sizes[L_SYM];
	if (sizes[L_SYM] % LDSYM_SIZE != 0 || end > (unsigned long)n)
		return 0;
	for (o = (long)off; o < (long)end; o += LDSYM_SIZE) {
		memcpy(name, b + o, 16);
		name[16] = '\0';
		typ = le16(b, o + 16) & 017;
		addr = pdp32(b, o + 18);
		if (typ < (int)NSECT)
			sect = sections[typ];
		else {
			sprintf(sbuf2, "?%d", typ);
			sect = sbuf2;
		}
		sprintf(line, "\n  %s 0x%lx ", sect, addr);
		sbcat(sb, line);
		sbcat(sb, name);
	}
	return 1;
}

static int
machcmp(a, b)
char **a, **b;
{
	return strcmp(*a, *b);
}

/* The distinct machine names of every object in a COHERENT archive.  Returns
 * -1 when a member header cannot be read, else the count in mach[]. */
static int
archive_machines(path, mach, store)
char *path;
char **mach;
char (*store)[16];
{
	FILE *f;
	unsigned char hdr[ARHDR], body[64];
	unsigned long size;
	long got;
	int nm, i, dup;
	char mbuf[16], *m;

	f = fopen(path, "rb");
	if (f == 0)
		return -1;
	if (fseek(f, 2L, SEEK_SET) != 0) {
		fclose(f);
		return -1;
	}
	nm = 0;
	for (;;) {
		if (fread(hdr, 1, ARHDR, f) < ARHDR)
			break;
		size = pdp32(hdr, 24);
		if (size == 0 || size > (1UL << 26)) {
			fclose(f);
			return -1;
		}
		got = (long)fread(body, 1, size < 64 ? (size_t)size : 64, f);
		if (got < 8)
			break;
		m = ident_lout(body, got, 0L, (int *)0, mbuf);
		if (m != 0) {
			dup = 0;
			for (i = 0; i < nm; i++)
				if (strcmp(mach[i], m) == 0)
					dup = 1;
			if (!dup && nm < MAXMACH) {
				strncpy(store[nm], m, 15);
				store[nm][15] = '\0';
				mach[nm] = store[nm];
				nm++;
			}
		}
		/* Members are NOT padded to an even boundary in this format
		 * (checked against libc-z8001.a): the next header follows the
		 * body immediately. */
		if (fseek(f, (long)size - got, SEEK_CUR) != 0)
			break;
	}
	fclose(f);
	return nm;
}

/* Describe one file.  Returns its machine name, or 0 when unidentifiable, and
 * builds the description in sb. */
static char *
ident(path, want_entry, want_syms, sb, mbuf)
char *path;
int want_entry, want_syms;
struct sbuf *sb;
char *mbuf;
{
	FILE *f;
	unsigned char *b;
	long n, cap;
	unsigned long e;
	int flags, i, nm;
	char *m, *mach[MAXMACH], line[128], fbuf[32];
	char store[MAXMACH][16];

	f = fopen(path, "rb");
	if (f == 0) {
		sprintf(line, "cannot read: [Errno %d] %s: ", errno, strerror(errno));
		sbcat(sb, line);
		sbcat(sb, "'");
		sbcat(sb, path);
		sbcat(sb, "'");
		return 0;
	}
	if (want_syms) {
		if (fseek(f, 0L, SEEK_END) != 0) {
			fclose(f);
			sbcat(sb, "cannot read");
			return 0;
		}
		cap = ftell(f);
		rewind(f);
	} else
		cap = HEADREAD;
	if (cap < 1)
		cap = 1;
	b = (unsigned char *)malloc((size_t)cap);
	if (b == 0) {
		fclose(f);
		fprintf(stderr, "loutid: out of memory\n");
		exit(2);
	}
	n = (long)fread(b, 1, (size_t)cap, f);
	fclose(f);

	if (n < 2) {
		sbcat(sb, "empty or too short");
		free(b);
		return 0;
	}
	if (n >= 4 && b[0] == 0177 && b[1] == 'E' && b[2] == 'L' && b[3] == 'F') {
		sbcat(sb, "ELF (a HOST binary)");
		free(b);
		return 0;
	}
	if (le16(b, 0) == AR_MAGIC) {
		free(b);
		nm = archive_machines(path, mach, store);
		if (nm < 0) {
			sbcat(sb, "archive (unreadable member header)");
			return 0;
		}
		if (nm == 1) {
			sbcat(sb, "archive of l.out objects");
			strcpy(mbuf, mach[0]);
			return mbuf;
		}
		if (nm == 0) {
			sbcat(sb, "archive (no objects)");
			return 0;
		}
		qsort((char *)mach, (size_t)nm, sizeof(char *), machcmp);
		sbcat(sb, "archive of MIXED machines: ");
		for (i = 0; i < nm; i++) {
			if (i)
				sbcat(sb, ",");
			sbcat(sb, mach[i]);
		}
		return 0;
	}
	flags = 0;
	m = ident_lout(b, n, 0L, &flags, mbuf);
	if (m == 0) {
		sprintf(line, "not an l.out (magic 0x%04lx)", le16(b, 0));
		sbcat(sb, line);
		free(b);
		return 0;
	}
	sprintf(line, "l.out %s [%s]", m, flagstr(flags, fbuf));
	sbcat(sb, line);
	if (want_entry) {
		if (entry_of(b, n, &e)) {
			sprintf(line, " entry=0x%lx", e);
			sbcat(sb, line);
		} else
			sbcat(sb, " entry=?");
	}
	if (want_syms && !symbols_of(b, n, sb))
		sbcat(sb, "\n  symbols=?");
	free(b);
	return m;
}

int
main(argc, argv)
int argc;
char **argv;
{
	struct sbuf sb;
	char *want, *mach, mbuf[16];
	char **files;
	int quiet, entry, syms, nf, i, bad, wrong;

	quiet = entry = syms = 0;
	want = 0;
	nf = 0;
	files = (char **)malloc((size_t)argc * sizeof(char *));
	if (files == 0) {
		fprintf(stderr, "loutid: out of memory\n");
		return 2;
	}
	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-q") == 0)
			quiet = 1;
		else if (strcmp(argv[i], "-e") == 0)
			entry = 1;
		else if (strcmp(argv[i], "-s") == 0)
			syms = 1;
		else if (strcmp(argv[i], "-m") == 0) {
			if (++i < argc)
				want = argv[i];
		} else if (argv[i][0] == '-') {
			fprintf(stderr, "loutid: unknown option %s\n", argv[i]);
			return 2;
		} else
			files[nf++] = argv[i];
	}
	if (nf == 0) {
		fprintf(stderr, "usage: loutid [-q] [-e] [-s] [-m MACHINE] FILE...\n");
		return 2;
	}
	bad = 0;
	for (i = 0; i < nf; i++) {
		sbinit(&sb);
		mach = ident(files[i], entry, syms, &sb, mbuf);
		wrong = want != 0 && (mach == 0 || strcmp(mach, want) != 0);
		if (wrong)
			bad++;
		if (!quiet || wrong) {
			printf("%-40s %s", files[i], sb.p);
			if (wrong)
				printf("   <-- WANTED %s", want);
			printf("\n");
		}
		free(sb.p);
	}
	return bad ? 1 : 0;
}
