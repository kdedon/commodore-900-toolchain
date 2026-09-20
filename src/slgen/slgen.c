/*
 * Copyright (c) 1977-1995 Robert Swartz.
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * slgen -- build a Z8001 shared library, in either of the two styles.
 *
 *	slgen [-v] [-k] [-A as] [-L ld] [-T dir] -e exports -o library obj ...
 *	slgen [-v] [-k] [-A as] [-L ld] [-T dir] -F base [-P privbase] -o library obj ...
 *
 * -F links at `base' for segments the kernel knows in advance, with an index
 * jump table at the head of the shared segment; clients CALL absolute
 * addresses and nothing is bound at exec.
 *
 * -e builds a dynamic library, in the format of <shlib.h>:
 *
 *   1. Read the export list.  An unknown name, or two names equal in their
 *	first NCPLN characters, is an error; an unlisted global is a warning.
 *
 *   2. Link a zeroed export table first, so it lands at shared offset 0.
 *	Its size is known up front, so one link suffices.
 *
 *   3. Link `ld -n -r -d': -r keeps the relocations, -d allocates commons.
 *
 *   4. Turn each non-PC-relative LR_LONG relocation into a library segment
 *	into a fixup.  Unresolved relocations are refused, since -r hides
 *	them.
 *
 *   5. Patch in the export table, append the fixups as L_DEBUG, set LF_SLIB.
 *
 * The l.out is handled byte by byte, so the host's layout never leaks in.
 * Header, symbols and relocations are PDP-canonical; the added tables are
 * big-endian.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#ifdef	_WIN32
#include <process.h>
#else
#include <sys/wait.h>
#endif

/* From the target's n.out.h and shlib.h; fields are accessed by offset. */
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
#define	JMPLEN		6		/* `jp' long-form DA, -F's stride */

static char	*progname = "slgen";
static char	*expfile;		/* -e */
static char	*outfile;		/* -o */
static char	*asname = "as-z8001";	/* -A */
static char	*ldname = "ld-z8001";	/* -L */
static char	*tmproot;		/* -T */
static int	vflag;			/* -v */
static int	kflag;			/* -k: keep the temporaries */
static int	fixmode;		/* -F: the fixed-address style	*/
static int	privmode;		/* -P was given			*/
static long	privbase;		/* -P: base of the private half	*/
static long	fixbase;		/* -F's argument: the link base	*/
static long	jtlen;			/* size word + one jump per entry */
static int	ncentry;		/* code globals counted		  */
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

/* Removed by name: on Windows, system() runs cmd.exe, which has no rm. */
static char	*tmpname[] = { "exports.s", "exports.o", "linked.out", NULL };

static int
cleantmp()
{
	char name[1100];
	int i;

	for (i = 0; tmpname[i] != NULL; i++) {
		sprintf(name, "%s/%s", tmpdir, tmpname[i]);
		remove(name);
	}
	return (rmdir(tmpdir));
}

static void
fatal(char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	vmsg("", fmt, ap);
	va_end(ap);
	if (!kflag && tmpdir[0] != '\0')
		cleantmp();
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
		for (i = 0; i < NCPLN && s[i] != '\0'; i++)
			exps[nexp].e_name[i] = s[i];
		exps[nexp].e_off = -1;
		exps[nexp].e_flags = 0;
		/*
		 * Optional kind, checked by resolve(): bare for a function,
		 * `data' for a per-client object, `shrd' for a shared
		 * readonly table.  Clients call functions through stubs and
		 * reach objects through slots.
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
#ifndef	_WIN32
	pid_t pid;
	int status;
#endif
	int i;

	if (vflag) {
		fprintf(stderr, "%s:", progname);
		for (i = 0; argv[i] != NULL; i++)
			fprintf(stderr, " %s", argv[i]);
		fputc('\n', stderr);
	}
#ifdef	_WIN32
	/* No fork on Windows.  _spawnvp does not quote: no argument has a space. */
	if (_spawnvp(_P_WAIT, argv[0], (const char * const *)argv) != 0)
		fatal("%s failed", argv[0]);
#else
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
#endif
}

static void
maketmp()
{
	char tmpl[1024];
	char *root;

	if ((root = tmproot) == NULL && (root = getenv("TMPDIR")) == NULL)
#ifdef	_WIN32
		if ((root = getenv("TEMP")) == NULL)
#endif
			root = "/tmp";
	sprintf(tmpl, "%s/slgenXXXXXX", root);
#ifdef	_WIN32
	/* MinGW has no mkdtemp. */
	if (_mktemp(tmpl) == NULL || mkdir(tmpl) != 0)
#else
	if (mkdtemp(tmpl) == NULL)
#endif
		fatal("cannot make a temporary directory under %s", root);
	strcpy(tmpdir, tmpl);
}

/* A zeroed export table, linked first and filled in afterwards. */
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
	av[n++] = "-S";			/* final image; may import from a library */
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
	if (!fixmode && ssize[L_DEBUG] != 0)
		fatal("%s carries a debug section, where the fixup list goes",
			name);
	n = fixmode ? jtlen : (long)SL_HDRLEN + (long)SL_EXPLEN * nexp;
	if (ssize[L_SHRI] < n)
		fatal("the shared text is smaller than the %s", fixmode
			? "jump table" : "export table");
	for (o = 0; o < n; o++)
		if (img[soff[L_SHRI] + o] != 0)
			fatal("the head of the shared segment is not the reserved %s",
				fixmode ? "jump table" : "export table");
	if (canl(img + 44) != (fixmode ? fixbase : ((long)SL_NOMSHR << 24))) {
		if (fixmode)
			fatal("the library was not linked at 0x%08lx", fixbase);
		fatal("the library was not linked at the nominal pair %d:%d",
			SL_NOMSHR, SL_NOMPRV);
	}
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
 * An import's stub is global in the shared text, so it looks like an
 * unlisted definition; its LI_IMP record says otherwise.
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

/* Locate each export, and warn of unlisted globals. */
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
		 * Functions and readonly tables are in the shared segment;
		 * other data is in the private one, copied per client.
		 * Private instructions are unreachable from a client.
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
 * File offset of loaded offset `off' in the shared or private segment.
 * The file orders sections SHRI, PRVI, SHRD, PRVD, so a segment's halves
 * are apart on disk.
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
 * Build the fixup list.  A relocation record is an opcode byte, a 4-byte
 * linear address and, for L_SYM, a symbol number.
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
			continue;
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

/* ------------------------------------------------------------------ */
/* the fixed-address style: an index jump table at a known address	*/

/* Linker-defined per program, so never exported: end_ is the library's break. */
static int
isperprog(id)
char id[];
{
	static char *perprog[] = { "etext_", "edata_", "end_", NULL };
	char **pp;
	int n;

	for (pp = perprog; *pp != NULL; pp++) {
		n = strlen(*pp) + 1;		/* with its NUL */
		if (n <= NCPLN && memcmp(id, *pp, n) == 0)
			return (1);
	}
	return (0);
}

/*
 * Size the jump table from the input objects' code globals, since it is
 * linked first.  The linked count can differ (promoted commons), so
 * writefixed() checks for room.
 */
static void
countcode(objc, objv)
int objc;
char **objv;
{
	FILE *fp;
	unsigned char hdr[LDHLEN], sym[LDSLEN];
	long sz[NLSEG], o;
	int i, j, type;

	ncentry = 0;
	for (i = 0; i < objc; i++) {
		if ((fp = fopen(objv[i], "rb")) == NULL)
			fatal("cannot read %s", objv[i]);
		if (fread(hdr, 1, LDHLEN, fp) != LDHLEN)
			fatal("%s is not an l.out", objv[i]);
		if (canw(hdr) != L_MAGIC)
			fatal("%s: bad magic number", objv[i]);
		if (canw(hdr + 4) != M_Z8001)
			fatal("%s: not a Z8001 object", objv[i]);
		for (j = 0; j < NLSEG; j++)
			sz[j] = canl(hdr + 8 + 4 * j);
		o = LDHLEN;
		for (j = 0; j < L_SYM; j++)
			if (j != L_BSSI && j != L_BSSD)
				o += sz[j];
		if (fseek(fp, o, SEEK_SET) != 0)
			fatal("%s: cannot seek to the symbol table", objv[i]);
		for (o = sz[L_SYM]; o >= LDSLEN; o -= LDSLEN) {
			if (fread(sym, 1, LDSLEN, fp) != LDSLEN)
				fatal("%s: bad symbol segment", objv[i]);
			type = canw(sym + NCPLN);
			if ((type & L_GLOBAL) == 0 || isperprog((char *)sym))
				continue;
			switch (type & ~L_GLOBAL) {
			case L_SHRI:
			case L_PRVI:
			case L_BSSI:
				ncentry++;
			}
		}
		fclose(fp);
	}
	if (ncentry == 0)
		fatal("no object defines a global function: there is nothing to export");
	jtlen = 2 + (long)JMPLEN * ncentry;
}

/* A zeroed jump table, linked first: a length word, then the jumps. */
static void
buildjstub(sname, oname)
char *sname, *oname;
{
	FILE *fp;
	char *av[5];

	if ((fp = fopen(sname, "w")) == NULL)
		fatal("cannot write %s", sname);
	fprintf(fp, "/ slgen: the index jump table of this shared library.\n");
	fprintf(fp, "/ Reserved here so that it lands at offset 0 of the\n");
	fprintf(fp, "/ shared segment; slgen fills it in after the link.\n");
	fprintf(fp, "\t.shri\n");
	fprintf(fp, "_shlib_jumps:\n");
	fprintf(fp, "\t.blkb\t%ld\n", jtlen);
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
linkfixed(stubo, objc, objv, lname)
char *stubo, **objv, *lname;
int objc;
{
	char **av, base[32], priv[32];
	int i, n;

	sprintf(base, "0x%08lx", fixbase);
	av = (char **)xalloc((long)(objc + 12) * sizeof(char *));
	n = 0;
	av[n++] = ldname;
	av[n++] = "-n";			/* shared segment + private segment */
	av[n++] = "-R";
	av[n++] = base;
	av[n++] = "-e";			/* loaders take the segment from   */
	av[n++] = base;			/* l_entry			    */
	if (privmode) {
		/* Where the loader maps it, not always the next segment. */
		sprintf(priv, "0x%08lx", privbase);
		av[n++] = "-P";
		av[n++] = priv;
	}
	av[n++] = "-o";
	av[n++] = lname;
	av[n++] = stubo;		/* FIRST: the table is at offset 0  */
	for (i = 0; i < objc; i++)
		av[n++] = objv[i];
	av[n] = NULL;
	run(av);
	free(av);
}

/*
 * Fill the jump table and move each code global to its slot, so a rebuilt
 * library keeps the addresses clients linked against.  Data globals keep
 * their linked addresses.
 */
static void
writefixed()
{
	long p, end, addr, jaddr, jfoff, room;
	int type, seg, ndata = 0;

	if (ssize[L_SYM] == 0)
		fatal("the link kept no symbol table");
	putbew(img + soff[L_SHRI], (int)jtlen);
	jfoff = soff[L_SHRI] + 2;
	jaddr = fixbase + 2;
	room = jtlen - 2;
	end = soff[L_SYM] + ssize[L_SYM];
	for (p = soff[L_SYM]; p + LDSLEN <= end; p += LDSLEN) {
		type = canw(img + p + NCPLN);
		addr = canl(img + p + NCPLN + 2);
		if (type == (L_GLOBAL | L_REF)) {
			fprintf(stderr, "%s: undefined symbol %.*s\n",
				progname, NCPLN, (char *)(img + p));
			nerror++;
			continue;
		}
		if ((type & L_GLOBAL) == 0)
			continue;
		if (isperprog((char *)(img + p))) {
			canpw(img + p + NCPLN, type & ~L_GLOBAL);
			continue;
		}
		seg = type & ~L_GLOBAL;
		if (seg != L_SHRI && seg != L_PRVI && seg != L_BSSI) {
			ndata++;
			continue;
		}
		if ((room -= JMPLEN) < 0)
			fatal("jump table overflow at %.*s: the link defines more code globals than the objects did (%d slots)",
				NCPLN, (char *)(img + p), ncentry);
		/* `jp addr', long-form segmented DA: 5E 08, 0x80|seg, 0, off */
		img[jfoff + 0] = 0x5E;
		img[jfoff + 1] = 0x08;
		img[jfoff + 2] = 0x80 | ((addr >> 24) & 0x7F);
		img[jfoff + 3] = 0x00;
		img[jfoff + 4] = (addr >> 8) & 0xFF;
		img[jfoff + 5] = addr & 0xFF;
		canpw(img + p + NCPLN, L_SHRI | L_GLOBAL);
		canpl(img + p + NCPLN + 2, jaddr);
		jfoff += JMPLEN;
		jaddr += JMPLEN;
	}
	if (nerror != 0)
		exit(1);
	canpw(img + 2, canw(img + 2) | LF_SLIB);
	if (room != 0)
		warn("the jump table has %ld unused bytes: the passes counted differently",
			room);
	if (vflag)
		fprintf(stderr,
			"%s: %s: shared %ld B, private %ld B (+%ld bss), %d jump slots, %d data globals\n",
			progname, outfile, shrlen, prvlen,
			ssize[L_BSSI] + ssize[L_BSSD], ncentry, ndata);
}

static void
writeimg()
{
	FILE *fp;

	if ((fp = fopen(outfile, "wb")) == NULL)
		fatal("cannot create %s", outfile);
	fwrite(img, 1, (size_t)imglen, fp);
	if (fclose(fp) != 0)
		fatal("write error on %s", outfile);
}

/* A segment base, spelled as ld's -R accepts it. */
static long
number(s)
char *s;
{
	char *e;
	long v;

	v = strtol(s, &e, 0);
	if (e == s || *e != '\0' || v < 0 || v > 0x7FFFFFFFL)
		fatal("-F: %s is not an address", s);
	if ((v & 0x00FFFFFFL) != 0)
		fatal("-F: 0x%08lx is not the base of a hardware segment", v);
	return (v);
}

static void
usage()
{
	fprintf(stderr,
"Usage: slgen [-v] [-k] [-A as] [-L ld] [-T dir] -e exports -o library obj ...\n");
	fprintf(stderr,
"       slgen [-v] [-k] [-A as] [-L ld] [-T dir] -F base [-P privbase] -o library obj ...\n");
	exit(2);
}

int
main(argc, argv)
int argc;
char **argv;
{
	char sname[1100], oname[1100], lname[1100];
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
		case 'F':
			if (++i >= argc)
				usage();
			fixmode++;
			fixbase = number(argv[i]);
			break;
		case 'P':
			if (++i >= argc)
				usage();
			privmode++;
			privbase = number(argv[i]);
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
	if (outfile == NULL || i >= argc)
		usage();
	if (privmode && !fixmode)
		fatal("-P places a fixed-address library's private half: use it with -F");
	if (privmode && privbase == fixbase)
		fatal("-P 0x%08lx is the shared half's own base", privbase);
	if (fixmode && expfile != NULL)
		fatal("-F and -e are the two styles: the fixed-address library exports every code global and has no export list");
	if (!fixmode && expfile == NULL)
		usage();

	if (!fixmode)
		readexports();
	maketmp();
	sprintf(sname, "%s/%s", tmpdir, tmpname[0]);
	sprintf(oname, "%s/%s", tmpdir, tmpname[1]);
	sprintf(lname, "%s/%s", tmpdir, tmpname[2]);
	if (fixmode) {
		countcode(argc - i, &argv[i]);
		buildjstub(sname, oname);
		linkfixed(oname, argc - i, &argv[i], lname);
		readimage(lname);
		writefixed();
		writeimg();
	} else {
		buildstub(sname, oname);
		linklib(oname, argc - i, &argv[i], lname);
		readimage(lname);
		resolve();
		scanrel();
		writelib();
	}
	if (kflag)
		fprintf(stderr, "%s: temporaries kept in %s\n", progname,
			tmpdir);
	else if (cleantmp() != 0)
		warn("cannot remove %s", tmpdir);
	return (0);
}
