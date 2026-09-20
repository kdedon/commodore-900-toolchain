/*
 * Copyright (c) 1977-1995 Robert Swartz.
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * slgen -- build a Z8001 dynamic shared library.
 *
 *	slgen [-v] [-k] [-A as] [-L ld] [-T dir] -e exports -o library obj ...
 *
 * A library carries an export table sorted by name and a list of the places
 * its own segment numbers appear; both formats are in <shlib.h>, which the
 * kernel compiles against too.  Building one:
 *
 *   1. Read the export list -- one linker name per line, `#' comments.  A
 *	listed name the library does not define is an error; a global it
 *	defines and the list does not name is a warning.  Two names equal in
 *	their first NCPLN characters are an error, since neither the symbol
 *	table nor the kernel's binary search can tell them apart.
 *
 *   2. Write a stub .s reserving the export table -- SL_HDRLEN plus SL_EXPLEN
 *	per export, zeroes in .shri -- assemble it and link it first, so the
 *	table lands at offset 0 of the shared segment.  The size is known
 *	before the link, so one link is enough and the offsets are filled in
 *	afterwards from the linked symbol table.
 *
 *   3. Link `ld -n -r -d': -n for the shared/private segment pair, -r to keep
 *	the relocation records the fixup list is derived from, -d because -r
 *	otherwise leaves commons undefined.  The nominal pair SL_NOMSHR:
 *	SL_NOMPRV is ld's default placement for a program.
 *
 *   4. Turn every LR_LONG relocation that is not PC-relative and refers to one
 *	of the library's own six segments into a `struct slfix', checking that
 *	the byte it names really holds the nominal segment.  An unresolved
 *	(L_SYM-based) relocation is an undefined symbol and is refused, since
 *	-r suppresses ld's own report of those.
 *
 *   5. Write the library: the export table patched into the head of L_SHRI,
 *	the fixup list as L_DEBUG, LF_SLIB set, symbols and relocations kept.
 *
 * This is a host program and reads and writes the l.out byte by byte, so no
 * layout or byte order of the machine it is built for reaches the file.  The
 * header, symbols and relocation addresses are PDP-canonical as <canon.h>
 * leaves them: a short low byte first, a long as its high word first with
 * each word low byte first.  The two tables slgen adds are target memory
 * images, big-endian throughout.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

/*
 * n.out.h and shlib.h spelled out rather than included: n.out.h is a target
 * header, and every field below is read and written by byte offset anyway.
 */
#define	NCPLN		16
#define	NLSEG		9
#define	L_MAGIC		0407
#define	M_Z8001		4
#define	LF_SHR		01
#define	LF_SLIB		0100
#define	L_SHRI		0
#define	L_PRVI		1
#define	L_BSSI		2
#define	L_SHRD		3
#define	L_PRVD		4
#define	L_BSSD		5
#define	L_DEBUG		6
#define	L_SYM		7
#define	L_REL		8
#define	L_ABS		9
#define	L_REF		10
#define	L_GLOBAL	020
#define	LR_SEG		017
#define	LR_PCR		020
#define	LR_OP		0340
#define	LR_BYTE		(0<<5)
#define	LR_WORD		(1<<5)
#define	LR_LONG		(2<<5)

#define	SL_MAGIC	0x534C
#define	SL_VERSION	1
#define	SL_NOMSHR	3
#define	SL_NOMPRV	4
#define	SL_HDRLEN	16
#define	SL_EXPLEN	20
#define	SL_FIXLEN	4
#define	SE_DATA		0x0001
#define	SE_SHRD		0x0002
#define	SF_LOC_PRIVATE	0x0001
#define	SF_REF_PRIVATE	0x0100
#define	LI_LIB		013
#define	LI_IMP		014

#define	LDHLEN		48		/* struct ldheader on the target */
#define	LDSLEN		22		/* struct ldsym on the target	 */
#define	SEGLEN		0x10000L	/* one Z8001 hardware segment	 */

static char	*progname = "slgen";
static char	*expfile;		/* -e */
static char	*outfile;		/* -o */
static char	*asname = "as-z8001";	/* -A */
static char	*ldname = "ld-z8001";	/* -L */
static char	*tmproot;		/* -T */
static int	vflag;			/* -v */
static int	kflag;			/* -k: keep the temporaries */
static int	nerror;

static char	tmpdir[1024];

struct	exp {
	char	e_name[NCPLN];		/* NUL-padded, as l.out holds it */
	char	*e_text;		/* as the list spelled it	 */
	long	e_off;			/* offset within its own image	 */
	int	e_flags;		/* SE_DATA if it is an object	 */
	int	e_kind;			/* the list's claim: EK_*	 */
	int	e_found;
};
static struct exp *exps;
static int	nexp;

#define	EK_FUNC	0			/* bare name: a function	*/
#define	EK_DATA	1			/* `data': an object, per client	*/
#define	EK_SHRD	2			/* `shrd': a readonly table, one copy */
static char *kindname[] = { "a function", "data", "shrd" };

struct	fix {
	unsigned short f_flags;
	unsigned short f_off;
};
static struct fix *fixes;
static int	nfix, mfix;

/* The library image, as ld left it. */
static unsigned char *img;
static long	imglen;
static long	ssize[NLSEG];		/* l_ssize[]			*/
static long	soff[NLSEG];		/* file offset of each section	*/
static long	shrlen, prvlen;		/* loaded bytes of each segment	*/

static void	fatal(char *, ...);
static void	warn(char *, ...);

/* ------------------------------------------------------------------ */
/* the canonical field forms, byte by byte				*/

static int
canw(p)					/* short: low byte first */
unsigned char *p;
{
	return (p[0] | (p[1] << 8));
}

static void
canpw(p, v)
unsigned char *p;
int v;
{
	p[0] = v & 0xFF;
	p[1] = (v >> 8) & 0xFF;
}

static long
canl(p)			/* long: high word first, each word low byte first */
unsigned char *p;
{
	return (((long)(p[0] | (p[1] << 8)) << 16) | (p[2] | (p[3] << 8)));
}

static void
canpl(p, v)
unsigned char *p;
long v;
{
	canpw(p, (int)((v >> 16) & 0xFFFF));
	canpw(p + 2, (int)(v & 0xFFFF));
}

/* the target's own order, for the two tables this program adds */
static void
putbew(p, v)
unsigned char *p;
int v;
{
	p[0] = (v >> 8) & 0xFF;
	p[1] = v & 0xFF;
}

static void
putbel(p, v)
unsigned char *p;
long v;
{
	putbew(p, (int)((v >> 16) & 0xFFFF));
	putbew(p + 2, (int)(v & 0xFFFF));
}

/* ------------------------------------------------------------------ */

static void
vmsg(tag, fmt, ap)
char *tag, *fmt;
va_list ap;
{
	fprintf(stderr, "%s: %s", progname, tag);
	vfprintf(stderr, fmt, ap);
	fputc('\n', stderr);
}

static void
fatal(char *fmt, ...)
{
	va_list ap;
	char cmd[1100];

	va_start(ap, fmt);
	vmsg("", fmt, ap);
	va_end(ap);
	if (!kflag && tmpdir[0] != '\0') {
		sprintf(cmd, "rm -rf '%s'", tmpdir);
		if (system(cmd) != 0)
			;
	}
	exit(1);
}

static void
warn(char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	vmsg("warning: ", fmt, ap);
	va_end(ap);
}

static void *
xalloc(n)
long n;
{
	void *p = calloc(1, (size_t)(n > 0 ? n : 1));

	if (p == NULL)
		fatal("out of memory");
	return (p);
}

/* ------------------------------------------------------------------ */
/* the export list							*/

static int
expcmp(a, b)
const void *a, *b;
{
	return (memcmp(((const struct exp *)a)->e_name,
		((const struct exp *)b)->e_name, NCPLN));
}

static void
readexports()
{
	FILE *fp;
	char line[512], *s, *t;
	int i, n, k;

	if ((fp = fopen(expfile, "r")) == NULL)
		fatal("cannot read the export list %s", expfile);
	n = 0;
	while (fgets(line, sizeof line, fp) != NULL)
		n++;
	rewind(fp);
	exps = (struct exp *)xalloc((long)(n + 1) * sizeof(struct exp));
	while (fgets(line, sizeof line, fp) != NULL) {
		if ((s = strchr(line, '#')) != NULL)
			*s = '\0';
		for (s = line; *s == ' ' || *s == '\t'; s++)
			;
		for (t = s; *t != '\0' && *t != ' ' && *t != '\t'
		     && *t != '\n' && *t != '\r'; t++)
			;
		k = *t;
		*t = '\0';
		if (*s == '\0')
			continue;
		if ((int)strlen(s) > NCPLN)
			warn("export %s is longer than %d characters; only the first %d count",
				s, NCPLN, NCPLN);
		exps[nexp].e_text = strdup(s);
		/* NUL-padded to NCPLN, and nothing read past the name */
		for (i = 0; i < NCPLN && s[i] != '\0'; i++)
			exps[nexp].e_name[i] = s[i];
		exps[nexp].e_off = -1;
		exps[nexp].e_flags = 0;
		/*
		 * The optional second word claims what the name is, and
		 * resolve() refuses the library if the objects disagree.  Bare
		 * is a function, `data' an object in the private image (one
		 * copy per client), `shrd' a readonly table in the shared
		 * segment (one copy).  It is an ABI distinction the names
		 * themselves cannot carry: a client compiled against a
		 * function gets a stub, one compiled against an object a slot.
		 */
		exps[nexp].e_kind = EK_FUNC;
		if (k != '\0') {
			for (s = t + 1; *s == ' ' || *s == '\t'; s++)
				;
			for (t = s; *t != '\0' && *t != ' ' && *t != '\t'
			     && *t != '\n' && *t != '\r'; t++)
				;
			*t = '\0';
			if (strcmp(s, "data") == 0)
				exps[nexp].e_kind = EK_DATA;
			else if (strcmp(s, "shrd") == 0)
				exps[nexp].e_kind = EK_SHRD;
			else if (*s != '\0')
				fatal("export %s: `%s' is not a kind (want `data', `shrd', or nothing for a function)",
					exps[nexp].e_text, s);
		}
		nexp++;
	}
	fclose(fp);
	if (nexp == 0)
		fatal("the export list %s names no symbol", expfile);
	qsort(exps, (size_t)nexp, sizeof(struct exp), expcmp);
	for (i = 1; i < nexp; i++)
		if (memcmp(exps[i - 1].e_name, exps[i].e_name, NCPLN) == 0)
			fatal("exports %s and %s are one symbol in %d characters",
				exps[i - 1].e_text, exps[i].e_text, NCPLN);
	if (vflag)
		fprintf(stderr, "%s: %d exports listed in %s\n", progname,
			nexp, expfile);
}

/* ------------------------------------------------------------------ */
/* running as and ld							*/

static void
run(argv)
char **argv;
{
	pid_t pid;
	int status, i;

	if (vflag) {
		fprintf(stderr, "%s:", progname);
		for (i = 0; argv[i] != NULL; i++)
			fprintf(stderr, " %s", argv[i]);
		fputc('\n', stderr);
	}
	if ((pid = fork()) < 0)
		fatal("cannot fork");
	if (pid == 0) {
		execvp(argv[0], argv);
		fprintf(stderr, "%s: cannot execute %s\n", progname, argv[0]);
		_exit(127);
	}
	if (waitpid(pid, &status, 0) < 0)
		fatal("wait failed");
	if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
		fatal("%s failed", argv[0]);
}

static void
maketmp()
{
	char tmpl[1024];
	char *root;

	root = tmproot != NULL ? tmproot
		: (getenv("TMPDIR") != NULL ? getenv("TMPDIR") : "/tmp");
	sprintf(tmpl, "%s/slgenXXXXXX", root);
	if (mkdtemp(tmpl) == NULL)
		fatal("cannot make a temporary directory under %s", root);
	strcpy(tmpdir, tmpl);
}

/*
 * The reserved export table, as an assembler module placed first in the link:
 * `.blkb' in .shri leaves the hole the table is written into afterwards.
 */
static void
buildstub(sname, oname)
char *sname, *oname;
{
	FILE *fp;
	char *av[5];

	if ((fp = fopen(sname, "w")) == NULL)
		fatal("cannot write %s", sname);
	fprintf(fp, "/ slgen: the export table of this shared library.\n");
	fprintf(fp, "/ Reserved here so that it lands at offset 0 of the\n");
	fprintf(fp, "/ shared segment; slgen fills it in after the link.\n");
	fprintf(fp, "\t.shri\n");
	fprintf(fp, "/ A LOCAL label: a global here would be an export the list\n");
	fprintf(fp, "/ does not name, and slgen would warn about its own stub.\n");
	fprintf(fp, "_shlib_exports:\n");
	fprintf(fp, "\t.blkb\t%ld\n", (long)SL_HDRLEN + (long)SL_EXPLEN * nexp);
	if (fclose(fp) != 0)
		fatal("cannot write %s", sname);
	av[0] = asname;
	av[1] = "-o";
	av[2] = oname;
	av[3] = sname;
	av[4] = NULL;
	run(av);
}

static void
linklib(stubo, objc, objv, lname)
char *stubo, **objv, *lname;
int objc;
{
	char **av;
	int i, n;

	av = (char **)xalloc((long)(objc + 9) * sizeof(char *));
	n = 0;
	av[n++] = ldname;
	av[n++] = "-n";			/* shared segment + private segment */
	av[n++] = "-r";			/* keep the relocation records	    */
	av[n++] = "-d";			/* -r would leave commons undefined */
	av[n++] = "-S";			/* a library MAY import from a library:
					   this -r output is a final image  */
	av[n++] = "-o";
	av[n++] = lname;
	av[n++] = stubo;		/* FIRST: the table is at offset 0  */
	for (i = 0; i < objc; i++)
		av[n++] = objv[i];
	av[n] = NULL;
	run(av);
	free(av);
}

/* ------------------------------------------------------------------ */
/* the linked image							*/

static void
readimage(name)
char *name;
{
	FILE *fp;
	long n, o;
	int i;

	if ((fp = fopen(name, "rb")) == NULL)
		fatal("cannot read %s", name);
	fseek(fp, 0L, SEEK_END);
	imglen = ftell(fp);
	rewind(fp);
	img = (unsigned char *)xalloc(imglen);
	if ((long)fread(img, 1, (size_t)imglen, fp) != imglen)
		fatal("short read on %s", name);
	fclose(fp);
	if (imglen < LDHLEN)
		fatal("%s is not an l.out", name);
	if (canw(img) != L_MAGIC)
		fatal("%s: bad magic number", name);
	if (canw(img + 4) != M_Z8001)
		fatal("%s: not a Z8001 object", name);
	if ((canw(img + 2) & LF_SHR) == 0)
		fatal("%s: not linked -n", name);
	for (i = 0; i < NLSEG; i++)
		ssize[i] = canl(img + 8 + 4 * i);
	o = LDHLEN;
	for (i = 0; i < NLSEG; i++) {
		if (i == L_BSSI || i == L_BSSD) {
			soff[i] = -1;
			continue;
		}
		soff[i] = o;
		o += ssize[i];
	}
	if (o != imglen)
		fatal("%s: the section sizes do not add up to the file size",
			name);
	if (ssize[L_DEBUG] != 0)
		fatal("%s carries a debug section, where the fixup list goes",
			name);
	n = (long)SL_HDRLEN + (long)SL_EXPLEN * nexp;
	if (ssize[L_SHRI] < n)
		fatal("the shared text is smaller than the export table");
	for (o = 0; o < n; o++)
		if (img[soff[L_SHRI] + o] != 0)
			fatal("the head of the shared segment is not the reserved export table");
	if (canl(img + 44) != ((long)SL_NOMSHR << 24))
		fatal("the library was not linked at the nominal pair %d:%d",
			SL_NOMSHR, SL_NOMPRV);
	shrlen = ssize[L_SHRI] + ssize[L_SHRD];
	prvlen = ssize[L_PRVI] + ssize[L_PRVD];
	if (shrlen > SEGLEN)
		fatal("the shared segment is %ld bytes, over one 64K segment",
			shrlen);
	if (prvlen + ssize[L_BSSI] + ssize[L_BSSD] > SEGLEN)
		fatal("the private segment is %ld bytes, over one 64K segment",
			prvlen + ssize[L_BSSI] + ssize[L_BSSD]);
}

/*
 * Is this a name the library imports from another library?  Its stub is
 * global in the library's own shared text, so it looks just like a definition
 * the export list forgot; the LI_IMP record beside it says otherwise.  ld
 * emits one record per imported symbol, so a linear scan is enough.
 */
static int
isimport(name)
char *name;
{
	long p, end;
	int type;

	end = soff[L_SYM] + ssize[L_SYM];
	for (p = soff[L_SYM]; p + LDSLEN <= end; p += LDSLEN) {
		type = canw(img + p + NCPLN);
		if (type == LI_IMP && memcmp(name, img + p, NCPLN) == 0)
			return (1);
	}
	return (0);
}

/*
 * Look every export up in the linked symbol table, and say which globals the
 * library defines that the list does not name.
 */
static void
resolve()
{
	long p, end, addr;
	int i, type, seg, lo, hi, mid, c;
	char name[NCPLN];

	if (ssize[L_SYM] == 0)
		fatal("the link kept no symbol table");
	end = soff[L_SYM] + ssize[L_SYM];
	for (p = soff[L_SYM]; p + LDSLEN <= end; p += LDSLEN) {
		memcpy(name, img + p, NCPLN);
		type = canw(img + p + NCPLN);
		addr = canl(img + p + NCPLN + 2);
		if (type == (L_GLOBAL | L_REF)) {
			fprintf(stderr, "%s: undefined symbol %.*s\n",
				progname, NCPLN, name);
			nerror++;
			continue;
		}
		if ((type & L_GLOBAL) == 0)
			continue;
		seg = type & ~L_GLOBAL;
		lo = 0;
		hi = nexp - 1;
		mid = -1;
		while (lo <= hi) {
			mid = (lo + hi) / 2;
			c = memcmp(name, exps[mid].e_name, NCPLN);
			if (c == 0)
				break;
			else if (c < 0)
				hi = mid - 1;
			else
				lo = mid + 1;
			mid = -1;
		}
		if (mid < 0) {
			if (seg == L_SHRI
			 && !isimport(name)
			 && memcmp(name, "etext_\0", 7) != 0
			 && memcmp(name, "edata_\0", 7) != 0
			 && memcmp(name, "end_\0", 5) != 0)
				warn("%.*s is global in the library and the export list does not name it",
					NCPLN, name);
			continue;
		}
		/*
		 * A function's offset is into the shared segment.  A DATA
		 * object lives in the private image, initialized (L_PRVD) or
		 * zeroed (L_BSSD), and its offset is into the private segment
		 * each client copies -- which is what makes it per-process
		 * state.  A readonly table landed in L_SHRD instead and goes
		 * out as SE_DATA|SE_SHRD, offset into the shared segment, so
		 * every client's slot points at the one copy.  Private
		 * instructions are refused: no client's text can reach them.
		 */
		if (seg == L_SHRI)
			exps[mid].e_flags = 0;
		else if (seg == L_PRVD || seg == L_BSSD)
			exps[mid].e_flags = SE_DATA;
		else if (seg == L_SHRD)
			exps[mid].e_flags = SE_DATA|SE_SHRD;
		else
			fatal("export %s is in segment %d: neither a function in the shared text, a `readonly' table in the shared data, nor an object in the private data",
				exps[mid].e_text, seg);
		if (((addr >> 24) & 0xFF)
		    != (exps[mid].e_flags == SE_DATA ? SL_NOMPRV : SL_NOMSHR))
			fatal("export %s is not in its nominal segment",
				exps[mid].e_text);
		if (exps[mid].e_flags != (exps[mid].e_kind == EK_DATA ? SE_DATA
				: exps[mid].e_kind == EK_SHRD
				? (SE_DATA|SE_SHRD) : 0))
			fatal("export %s: the list calls it %s, the library made it %s",
				exps[mid].e_text, kindname[exps[mid].e_kind],
				exps[mid].e_flags == 0 ? "a function"
				: exps[mid].e_flags == SE_DATA ? "data" : "shrd");
		exps[mid].e_off = addr & 0xFFFFL;
		exps[mid].e_found = 1;
	}
	for (i = 0; i < nexp; i++)
		if (!exps[i].e_found) {
			fprintf(stderr,
				"%s: export %s is not defined by the library\n",
				progname, exps[i].e_text);
			nerror++;
		}
	if (nerror != 0)
		fatal("%d symbol error(s)", nerror);
}

static void
addfix(flags, off)
int flags;
long off;
{
	if (nfix >= mfix) {
		mfix = mfix != 0 ? mfix * 2 : 256;
		fixes = (struct fix *)realloc(fixes,
			(size_t)mfix * sizeof(struct fix));
		if (fixes == NULL)
			fatal("out of memory");
	}
	fixes[nfix].f_flags = (unsigned short)flags;
	fixes[nfix].f_off = (unsigned short)off;
	nfix++;
}

static int
fixcmp(a, b)
const void *a, *b;
{
	const struct fix *x = (const struct fix *)a;
	const struct fix *y = (const struct fix *)b;

	if ((x->f_flags & SF_LOC_PRIVATE) != (y->f_flags & SF_LOC_PRIVATE))
		return ((x->f_flags & SF_LOC_PRIVATE) != 0 ? 1 : -1);
	if (x->f_off != y->f_off)
		return (x->f_off < y->f_off ? -1 : 1);
	return (0);
}

/*
 * The file offset of a byte at loaded offset `off' in the shared (locpriv 0)
 * or private (locpriv 1) segment.  A loaded segment is instructions followed
 * by data, but the file holds the sections in canonical l.out order -- SHRI,
 * PRVI, SHRD, PRVD -- so neither segment's data half is contiguous with its
 * instruction half on disk.
 */
static long
filoff(locpriv, off)
long off;
{
	long ilen;

	ilen = ssize[locpriv ? L_PRVI : L_SHRI];
	if (off < ilen)
		return (soff[locpriv ? L_PRVI : L_SHRI] + off);
	return (soff[locpriv ? L_PRVD : L_SHRD] + (off - ilen));
}

/*
 * The fixup list, out of the linker's relocation records.  A record is an
 * opcode byte, a 4-byte address, and, only when its segment field is L_SYM
 * (an unresolved symbol), a symbol number.  The addresses are linear: `ld -n'
 * puts the shared segment at SL_NOMSHR<<16, the private at SL_NOMPRV<<16.
 */
static void
scanrel()
{
	long p, end, addr, shrbase, prvbase, off, where;
	int op, seg, kind, locpriv, refpriv, b;

	shrbase = (long)SL_NOMSHR << 16;
	prvbase = (long)SL_NOMPRV << 16;
	if (ssize[L_REL] == 0)
		fatal("the link kept no relocation records (ld -r)");
	end = soff[L_REL] + ssize[L_REL];
	for (p = soff[L_REL]; p < end; ) {
		if (p + 5 > end)
			fatal("the relocation stream ends inside a record");
		op = img[p];
		addr = canl(img + p + 1);
		p += 5;
		seg = op & LR_SEG;
		kind = op & LR_OP;
		if (seg == L_SYM)
			fatal("an unresolved relocation is left at %#lx: the library has an undefined symbol",
				addr);
		if (seg == L_ABS || seg == L_REF)
			continue;	/* an absolute; no segment of ours */
		if (seg > L_BSSD)
			fatal("bad relocation segment %d at %#lx", seg, addr);
		if (addr >= shrbase && addr < shrbase + shrlen) {
			locpriv = 0;
			off = addr - shrbase;
		} else if (addr >= prvbase && addr < prvbase + prvlen) {
			locpriv = 1;
			off = addr - prvbase;
		} else
			fatal("the relocation at %#lx is outside the library's loaded segments",
				addr);
		refpriv = (seg == L_SHRI || seg == L_SHRD) ? 0 : 1;
		if (kind == LR_WORD)
			continue;	/* an offset; it carries no segment */
		if (kind != LR_LONG)
			fatal("relocation kind %#o at %#lx carries a segment in a form the loader cannot move",
				kind, addr);
		if ((op & LR_PCR) != 0)
			continue;	/* self-relative; no segment in it  */
		where = filoff(locpriv, off);
		if (where + 4 > imglen)
			fatal("the relocation at %#lx runs off the end of the file",
				addr);
		b = img[where] & 0x7F;
		if (b != (refpriv ? SL_NOMPRV : SL_NOMSHR))
			fatal("the address at %s+%#lx holds segment %d, not the nominal %d",
				locpriv ? "private" : "shared", off, b,
				refpriv ? SL_NOMPRV : SL_NOMSHR);
		addfix((locpriv ? SF_LOC_PRIVATE : 0)
		     | (refpriv ? SF_REF_PRIVATE : 0), off);
	}
	qsort(fixes, (size_t)nfix, sizeof(struct fix), fixcmp);
	if (vflag)
		fprintf(stderr, "%s: %d segment fixups\n", progname, nfix);
}

/*
 * Write the library: the header with LF_SLIB, the sections as ld left them
 * with the export table patched into the head of L_SHRI, and the fixup list as
 * the L_DEBUG section.
 */
static void
writelib()
{
	FILE *fp;
	unsigned char hdr[LDHLEN], ent[SL_EXPLEN], fx[SL_FIXLEN];
	long fixoff, sz;
	int i, j;

	fixoff = LDHLEN + ssize[L_SHRI] + ssize[L_PRVI] + ssize[L_SHRD]
		+ ssize[L_PRVD];
	putbew(img + soff[L_SHRI] + 0, SL_MAGIC);
	putbew(img + soff[L_SHRI] + 2, SL_VERSION);
	putbew(img + soff[L_SHRI] + 4, nexp);
	putbew(img + soff[L_SHRI] + 6, SL_HDRLEN);
	putbew(img + soff[L_SHRI] + 8, nfix);
	putbew(img + soff[L_SHRI] + 10, L_DEBUG);
	putbel(img + soff[L_SHRI] + 12, fixoff);
	for (i = 0; i < nexp; i++) {
		memset(ent, 0, sizeof ent);
		memcpy(ent, exps[i].e_name, NCPLN);
		putbew(ent + NCPLN, exps[i].e_flags);
		putbew(ent + NCPLN + 2, (int)exps[i].e_off);
		memcpy(img + soff[L_SHRI] + SL_HDRLEN + (long)SL_EXPLEN * i,
			ent, SL_EXPLEN);
	}

	memcpy(hdr, img, LDHLEN);
	canpw(hdr + 2, canw(hdr + 2) | LF_SLIB);
	canpl(hdr + 8 + 4 * L_DEBUG, (long)SL_FIXLEN * nfix);

	if ((fp = fopen(outfile, "wb")) == NULL)
		fatal("cannot create %s", outfile);
	fwrite(hdr, 1, LDHLEN, fp);
	for (i = 0; i < NLSEG; i++) {
		if (i == L_BSSI || i == L_BSSD)
			continue;
		if (i == L_DEBUG) {
			for (j = 0; j < nfix; j++) {
				putbew(fx, fixes[j].f_flags);
				putbew(fx + 2, fixes[j].f_off);
				fwrite(fx, 1, SL_FIXLEN, fp);
			}
			continue;
		}
		if ((sz = ssize[i]) != 0)
			fwrite(img + soff[i], 1, (size_t)sz, fp);
	}
	if (fclose(fp) != 0)
		fatal("write error on %s", outfile);
	if (vflag)
		fprintf(stderr,
			"%s: %s: shared %ld B, private %ld B (+%ld bss), %d exports, %d fixups\n",
			progname, outfile, shrlen, prvlen,
			ssize[L_BSSI] + ssize[L_BSSD], nexp, nfix);
}

static void
usage()
{
	fprintf(stderr,
"Usage: slgen [-v] [-k] [-A as] [-L ld] [-T dir] -e exports -o library obj ...\n");
	exit(2);
}

int
main(argc, argv)
int argc;
char **argv;
{
	char sname[1100], oname[1100], lname[1100], cmd[1200];
	int i;

	for (i = 1; i < argc && argv[i][0] == '-' && argv[i][1] != '\0'; i++) {
		switch (argv[i][1]) {
		case 'e':
			if (++i >= argc)
				usage();
			expfile = argv[i];
			break;
		case 'o':
			if (++i >= argc)
				usage();
			outfile = argv[i];
			break;
		case 'A':
			if (++i >= argc)
				usage();
			asname = argv[i];
			break;
		case 'L':
			if (++i >= argc)
				usage();
			ldname = argv[i];
			break;
		case 'T':
			if (++i >= argc)
				usage();
			tmproot = argv[i];
			break;
		case 'v':
			vflag++;
			break;
		case 'k':
			kflag++;
			break;
		default:
			usage();
		}
	}
	if (expfile == NULL || outfile == NULL || i >= argc)
		usage();

	readexports();
	maketmp();
	sprintf(sname, "%s/exports.s", tmpdir);
	sprintf(oname, "%s/exports.o", tmpdir);
	sprintf(lname, "%s/linked.out", tmpdir);
	buildstub(sname, oname);
	linklib(oname, argc - i, &argv[i], lname);
	readimage(lname);
	resolve();
	scanrel();
	writelib();
	if (kflag)
		fprintf(stderr, "%s: temporaries kept in %s\n", progname,
			tmpdir);
	else {
		sprintf(cmd, "rm -rf '%s'", tmpdir);
		if (system(cmd) != 0)
			warn("cannot remove %s", tmpdir);
	}
	return (0);
}
