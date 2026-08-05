/*
 * coff2elf -- convert a Coherent i386 COFF object (the output of the MWC
 * `cc --target x86` back end, n2/i386/outcoff.c) into an ELF32 relocatable
 * object the host gnu `ld` can link.  The bridge that lets the x86 target
 * self-host on the development machine (CROSS_COMPILATION_METHODS.md).
 *
 * Reads COFF (magic 0x14C) by explicit little-endian byte offsets -- never by
 * struct overlay -- so the same source is correct under the LP64 host gcc that
 * bootstraps it and under the ILP32 MWC compiler that later builds it.  Emits
 * ELF32 (ET_REL, EM_386) with .text/.data/.bss, a .symtab/.strtab, and
 * .rel.text/.rel.data using the i386 REL form.
 *
 *	usage:  coff2elf [-u] in.o out.o
 *	  -u	strip one leading underscore from symbol names
 *
 * K&R C; host tool, distributed and self-hosted with the toolchain.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* COFF on-disk sizes (i386, #pragma align 2 -- packed to 2 bytes). */
#define	FILHSZ	20		/* sizeof(FILHDR)		*/
#define	SCNHSZ	40		/* sizeof(SCNHDR)		*/
#define	SYMESZ	18		/* sizeof(SYMENT)		*/
#define	RELSZ	10		/* sizeof(RELOC)		*/

#define	C386MAGIC 0x14C
#define	SYMNMLEN 8

/* COFF storage classes used here. */
#define	C_EXT	2		/* external (global)		*/
#define	C_STAT	3		/* static  (local)		*/
#define	C_FILE	103		/* file name (skip)		*/

/* COFF section numbers. */
#define	N_UNDEF	0
#define	N_ABS	(-1)

/* COFF relocation types we translate. */
#define	R_DIR32		0x06	/* 32-bit absolute	-> R_386_32	*/
#define	R_PCRLONG	0x14	/* 32-bit pc-relative	-> R_386_PC32	*/

/* ELF32 constants. */
#define	ET_REL		1
#define	EM_386		3
#define	EV_CURRENT	1
#define	SHT_PROGBITS	1
#define	SHT_SYMTAB	2
#define	SHT_STRTAB	3
#define	SHT_NOBITS	8
#define	SHT_REL		9
#define	SHF_WRITE	0x1
#define	SHF_ALLOC	0x2
#define	SHF_EXEC	0x4
#define	STB_LOCAL	0
#define	STB_GLOBAL	1
#define	STT_NOTYPE	0
#define	STT_SECTION	3
#define	SHN_UNDEF	0
#define	SHN_ABS	0xFFF1
#define	R_386_32	1
#define	R_386_PC32	2

#define	EHSZ	52		/* ELF32 header size		*/
#define	SHSZ	40		/* ELF32 section header size	*/
#define	SYMSZ	16		/* ELF32 symbol size		*/

/* ELF section indices we lay down (fixed order). */
#define	S_NULL	0
#define	S_TEXT	1
#define	S_DATA	2
#define	S_BSS	3
#define	S_RTEXT	4		/* .rel.text	*/
#define	S_RDATA	5		/* .rel.data	*/
#define	S_SYM	6		/* .symtab	*/
#define	S_STR	7		/* .strtab	*/
#define	S_SHSTR	8		/* .shstrtab	*/
#define	NSECT	9

char	*progname;
int	uflag;			/* -u: strip leading underscore */

/* The whole input COFF file, slurped. */
unsigned char	*cf;
long		cflen;

/*
 * MWC COFF uses absolute "image offsets": a section symbol's value is that
 * section's base in the combined text+data+bss image, and reloc fields /
 * defined-symbol values are image offsets.  ELF wants section-relative values
 * (section symbols are 0).  secimg[1..3] = the .text/.data/.bss image bases;
 * coffval[i] = COFF symbol i's value.  We subtract these to convert.
 */
unsigned	secimg[4];	/* indexed by COFF section number 1/2/3 */
unsigned	*coffval;	/* per COFF symbol */

/*
 * Little-endian field readers over the input image.
 */
unsigned
u16(o)
long	o;
{
	return (cf[o] | (cf[o+1]<<8));
}

unsigned
u32(o)
long	o;
{
	return ((unsigned)cf[o] | (cf[o+1]<<8) | (cf[o+2]<<16)
		| ((unsigned)cf[o+3]<<24));
}

/*
 * Growable little-endian output buffer.
 */
unsigned char	*ob;
long		oblen, obcap;

grow(n)
long	n;
{
	if (oblen+n > obcap) {
		obcap = (oblen+n)*2 + 1024;
		ob = (unsigned char *)realloc((char *)ob, obcap);
		if (ob == NULL)
			fatal("out of memory");
	}
}

ob8(v)
{
	grow(1L);
	ob[oblen++] = v;
}

ob16(v)
{
	grow(2L);
	ob[oblen++] = v;
	ob[oblen++] = v>>8;
}

ob32(v)
unsigned	v;
{
	grow(4L);
	ob[oblen++] = v;
	ob[oblen++] = v>>8;
	ob[oblen++] = v>>16;
	ob[oblen++] = v>>24;
}

/* Append n raw bytes from the input image at offset o. */
obraw(o, n)
long	o, n;
{
	grow(n);
	memcpy((char *)ob+oblen, (char *)cf+o, (int)n);
	oblen += n;
}

/* Pad the output to a 4-byte boundary. */
obalign()
{
	while ((oblen & 3) != 0)
		ob8(0);
}

fatal(s)
char	*s;
{
	fprintf(stderr, "%s: %s\n", progname, s);
	exit(1);
}

/*
 * The ELF string table is built up incrementally; index 0 is the empty string.
 */
char	*strtab;
long	strlen0, strcap;

long
stradd(s)
char	*s;
{
	long	at;
	int	n;

	n = strlen(s) + 1;
	if (strlen0+n > strcap) {
		strcap = (strlen0+n)*2 + 256;
		strtab = realloc(strtab, strcap);
		if (strtab == NULL)
			fatal("out of memory");
	}
	at = strlen0;
	memcpy(strtab+at, s, n);
	strlen0 += n;
	return (at);
}

/*
 * The ELF symbol table, accumulated as a flat byte image (each entry SYMSZ).
 * We collect locals first, then globals; sh_info is the first global index.
 */
unsigned char	*esym;
long		esymlen, esymcap;
int		nesym;

esyment(name, value, shndx, bind, type)
char		*name;		/* explicit: implicit-int would truncate on LP64 */
unsigned	value;
{
	long	no;

	if (esymlen+SYMSZ > esymcap) {
		esymcap = (esymlen+SYMSZ)*2 + 256;
		esym = (unsigned char *)realloc((char *)esym, esymcap);
		if (esym == NULL)
			fatal("out of memory");
	}
	no = name ? stradd(name) : 0;
	esym[esymlen+0] = no;
	esym[esymlen+1] = no>>8;
	esym[esymlen+2] = no>>16;
	esym[esymlen+3] = no>>24;
	esym[esymlen+4] = value;
	esym[esymlen+5] = value>>8;
	esym[esymlen+6] = value>>16;
	esym[esymlen+7] = value>>24;
	esym[esymlen+8] = 0;		/* st_size  */
	esym[esymlen+9] = 0;
	esym[esymlen+10] = 0;
	esym[esymlen+11] = 0;
	esym[esymlen+12] = (bind<<4) | (type&0xF);	/* st_info */
	esym[esymlen+13] = 0;				/* st_other */
	esym[esymlen+14] = shndx;
	esym[esymlen+15] = shndx>>8;
	esymlen += SYMSZ;
	return (nesym++);
}

/*
 * Read the 8-byte COFF symbol name at image offset `o` into buf.  COFF uses
 * either an inline 8-char name, or (if the first 4 bytes are zero) a 4-byte
 * offset into the COFF string table.  Optionally strip one leading underscore.
 */
symname(o, strbase, buf)
long	o, strbase;
char	*buf;
{
	char	*p;
	long	so;
	int	i;

	if (u32(o) == 0) {			/* long name in string table */
		so = strbase + u32(o+4);
		p = (char *)cf + so;
		strncpy(buf, p, 255);
		buf[255] = 0;
	} else {
		for (i = 0; i < SYMNMLEN; i++)
			buf[i] = cf[o+i];
		buf[SYMNMLEN] = 0;		/* may be exactly 8, NUL-cap */
	}
	if (uflag && buf[0] == '_') {
		for (p = buf; (p[0] = p[1]) != 0; p++)
			;
	}
}

/*
 * Map a COFF section number (1=.text 2=.data 3=.bss) to an ELF section index.
 */
int
mapscn(coffscn)
{
	switch (coffscn) {
	case 1:	return (S_TEXT);
	case 2:	return (S_DATA);
	case 3:	return (S_BSS);
	case N_UNDEF:	return (SHN_UNDEF);
	case N_ABS:	return (SHN_ABS);
	}
	return (SHN_UNDEF);
}

main(argc, argv)
char	**argv;
{
	char	*inf, *outf;
	FILE	*fp;
	int	i, a;

	long	symptr, nsyms, strbase;
	long	scnoff, txtoff, datoff, txtrel, datrel;
	unsigned txtsz, datsz, bsssz;
	int	ntxtrel, ndatrel;

	/* per-COFF-symbol -> ELF-symbol-index map (built in pass 1) */
	int	*symmap;

	long	eshoff, secdata[NSECT], secsize[NSECT];
	int	firstglobal;
	long	o;

	progname = argv[0];
	a = 1;
	if (a < argc && strcmp(argv[a], "-u") == 0) {
		uflag = 1;
		a++;
	}
	if (argc - a != 2) {
		fprintf(stderr, "usage: %s [-u] in.o out.o\n", progname);
		exit(2);
	}
	inf = argv[a];
	outf = argv[a+1];

	/* slurp the input */
	fp = fopen(inf, "rb");
	if (fp == NULL)
		fatal("cannot open input");
	fseek(fp, 0L, 2);
	cflen = ftell(fp);
	fseek(fp, 0L, 0);
	cf = (unsigned char *)malloc((int)cflen);
	if (cf == NULL || fread((char *)cf, 1, (int)cflen, fp) != cflen)
		fatal("read error");
	fclose(fp);

	if (u16(0) != C386MAGIC)
		fatal("not an i386 COFF object (bad magic)");

	symptr = u32(8);		/* f_symptr  */
	nsyms = u32(12);		/* f_nsyms   */

	strbase = symptr + nsyms*SYMESZ;	/* COFF string table follows */

	/*
	 * Locate the .text/.data/.bss section headers and their data/reloc.
	 * cc2 always emits exactly sections 1,2,3 in that order; an optional
	 * header (f_opthdr, only in executables) is skipped if present.
	 */
	scnoff = FILHSZ + u16(16);	/* past FILHDR + optional header */
	txtsz = datsz = bsssz = 0;
	txtoff = datoff = txtrel = datrel = 0;
	ntxtrel = ndatrel = 0;
	for (i = 0; i < u16(2); i++) {	/* f_nscns */
		o = scnoff + (long)i*SCNHSZ;
		/* s_name at o; s_size at o+16; s_scnptr o+20; s_relptr o+24;
		   s_nreloc o+32 (ushort) */
		if (i == 0) {		/* .text */
			txtsz = u32(o+16);
			txtoff = u32(o+20);
			txtrel = u32(o+24);
			ntxtrel = u16(o+32);
		} else if (i == 1) {	/* .data */
			datsz = u32(o+16);
			datoff = u32(o+20);
			datrel = u32(o+24);
			ndatrel = u16(o+32);
		} else if (i == 2) {	/* .bss */
			bsssz = u32(o+16);
		}
	}

	/*
	 * PASS 1 -- build the ELF symbol table.  Order: null(0),
	 * section symbols .text/.data/.bss (local), then COFF locals,
	 * then COFF globals.  Record each COFF slot's ELF index in symmap.
	 */
	symmap = (int *)malloc((nsyms ? (int)nsyms : 1) * sizeof(int));
	if (symmap == NULL)
		fatal("out of memory");
	for (i = 0; i < nsyms; i++)
		symmap[i] = 0;

	/*
	 * Pre-scan: record every COFF symbol's value, and the .text/.data/.bss
	 * image bases (the section symbols' values).  Needed to convert image
	 * offsets to section-relative values below.
	 */
	coffval = (unsigned *)malloc((nsyms ? (int)nsyms : 1) * sizeof(unsigned));
	if (coffval == NULL)
		fatal("out of memory");
	secimg[1] = secimg[2] = secimg[3] = 0;
	for (i = 0; i < nsyms; ) {
		char	nm[260];
		int	scnum, naux;

		o = symptr + (long)i*SYMESZ;
		coffval[i] = u32(o+8);
		scnum = (short)u16(o+12);
		naux = cf[o+17];
		symname(o, strbase, nm);
		if (cf[o+16] == C_STAT && scnum >= 1 && scnum <= 3 &&
		    (strcmp(nm, ".text")==0 || strcmp(nm, ".data")==0 ||
		     strcmp(nm, ".bss")==0))
			secimg[scnum] = coffval[i];
		i += 1 + naux;
	}

	stradd("");		/* .strtab index 0 = "" (before any named sym) */
	esyment((char *)0, 0, SHN_UNDEF, STB_LOCAL, STT_NOTYPE);	/* 0 */
	esyment((char *)0, 0, S_TEXT, STB_LOCAL, STT_SECTION);
	esyment((char *)0, 0, S_DATA, STB_LOCAL, STT_SECTION);
	esyment((char *)0, 0, S_BSS,  STB_LOCAL, STT_SECTION);

	/* locals pass */
	for (i = 0; i < nsyms; ) {
		char	nm[260];
		int	sclass, scnum, naux;
		unsigned val;

		o = symptr + (long)i*SYMESZ;
		val = u32(o+8);
		scnum = (short)u16(o+12);
		sclass = (signed char)cf[o+16];
		naux = cf[o+17];

		symname(o, strbase, nm);
		if (sclass == C_STAT &&
		    (strcmp(nm, ".text")==0 || strcmp(nm, ".data")==0 ||
		     strcmp(nm, ".bss")==0)) {
			/* COFF section symbol -> reuse the ELF section symbol */
			symmap[i] = mapscn(scnum);
		} else if (sclass == C_STAT && scnum > 0) {
			if (scnum >= 1 && scnum <= 3)
				val -= secimg[scnum];	/* image -> sect-rel */
			symmap[i] = esyment(nm, val, mapscn(scnum),
				STB_LOCAL, STT_NOTYPE);
		}
		i += 1 + naux;
	}
	firstglobal = nesym;
	/* globals pass */
	for (i = 0; i < nsyms; ) {
		char	nm[260];
		int	sclass, scnum, naux;
		unsigned val;

		o = symptr + (long)i*SYMESZ;
		val = u32(o+8);
		scnum = (short)u16(o+12);
		sclass = (signed char)cf[o+16];
		naux = cf[o+17];

		if (sclass == C_EXT) {
			symname(o, strbase, nm);
			if (scnum >= 1 && scnum <= 3)
				val -= secimg[scnum];	/* image -> sect-rel */
			symmap[i] = esyment(nm, val, mapscn(scnum),
				STB_GLOBAL, STT_NOTYPE);
		}
		i += 1 + naux;
	}

	/*
	 * PASS 2 -- assemble the ELF image.  Layout:
	 *   [ehdr][.text][.data][.rel.text][.rel.data][.symtab][.strtab]
	 *   [.shstrtab][section headers]
	 */
	/* --- ELF header (filled now, shoff patched after) --- */
	ob8(0x7f); ob8('E'); ob8('L'); ob8('F');
	ob8(1);				/* ELFCLASS32 */
	ob8(1);				/* ELFDATA2LSB */
	ob8(1);				/* EV_CURRENT */
	for (i = 7; i < 16; i++)
		ob8(0);			/* EI_PAD */
	ob16(ET_REL);
	ob16(EM_386);
	ob32(EV_CURRENT);
	ob32(0);			/* e_entry */
	ob32(0);			/* e_phoff */
	ob32(0);			/* e_shoff -- patched */
	ob32(0);			/* e_flags */
	ob16(EHSZ);
	ob16(0);			/* e_phentsize */
	ob16(0);			/* e_phnum */
	ob16(SHSZ);
	ob16(NSECT);
	ob16(S_SHSTR);

	for (i = 0; i < NSECT; i++) {
		secdata[i] = 0;
		secsize[i] = 0;
	}

	/* .text */
	obalign();
	secdata[S_TEXT] = oblen;
	secsize[S_TEXT] = txtsz;
	if (txtsz)
		obraw(txtoff, (long)txtsz);

	/* .data */
	obalign();
	secdata[S_DATA] = oblen;
	secsize[S_DATA] = datsz;
	if (datsz)
		obraw(datoff, (long)datsz);

	/* .bss has no file data; record its size for the section header */
	secsize[S_BSS] = bsssz;

	/* .rel.text and .rel.data (ELF32 Rel: r_offset, r_info).  secdata[]
	   gives each section's base in the output image so PC-relative addends
	   can be fixed up in place (see emitrel). */
	obalign();
	secdata[S_RTEXT] = oblen;
	emitrel(txtrel, ntxtrel, symmap, secdata[S_TEXT], secimg[1]);
	secsize[S_RTEXT] = oblen - secdata[S_RTEXT];

	obalign();
	secdata[S_RDATA] = oblen;
	emitrel(datrel, ndatrel, symmap, secdata[S_DATA], secimg[2]);
	secsize[S_RDATA] = oblen - secdata[S_RDATA];

	/* .symtab */
	obalign();
	secdata[S_SYM] = oblen;
	secsize[S_SYM] = esymlen;
	grow(esymlen);
	memcpy((char *)ob+oblen, (char *)esym, (int)esymlen);
	oblen += esymlen;

	/* .strtab */
	secdata[S_STR] = oblen;
	secsize[S_STR] = strlen0;
	grow(strlen0);
	memcpy((char *)ob+oblen, strtab, (int)strlen0);
	oblen += strlen0;

	/* .shstrtab -- section name string table */
	{
	long	n_text, n_data, n_bss, n_rtext, n_rdata, n_sym, n_str, n_shstr;
	long	shstrbase;

	secdata[S_SHSTR] = oblen;
	shstrbase = strlen0;	/* reuse stradd against the SAME strtab? no. */
	/* build a dedicated shstrtab inline */
	{
	static char sh[] = "\0.text\0.data\0.bss\0.rel.text\0.rel.data\0"
		".symtab\0.strtab\0.shstrtab\0";
	n_text  = 1;
	n_data  = 7;
	n_bss   = 13;
	n_rtext = 18;
	n_rdata = 28;
	n_sym   = 38;
	n_str   = 46;
	n_shstr = 54;
	grow((long)sizeof(sh)-1);
	memcpy((char *)ob+oblen, sh, (int)sizeof(sh)-1);
	oblen += (long)sizeof(sh)-1;
	secsize[S_SHSTR] = (long)sizeof(sh)-1;
	}

	/* --- section header table --- */
	obalign();
	eshoff = oblen;

	/* [0] NULL */
	shdr(0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
	/* [1] .text */
	shdr(n_text, SHT_PROGBITS, SHF_ALLOC|SHF_EXEC, 0,
		secdata[S_TEXT], secsize[S_TEXT], 0, 0, 4, 0);
	/* [2] .data */
	shdr(n_data, SHT_PROGBITS, SHF_ALLOC|SHF_WRITE, 0,
		secdata[S_DATA], secsize[S_DATA], 0, 0, 4, 0);
	/* [3] .bss */
	shdr(n_bss, SHT_NOBITS, SHF_ALLOC|SHF_WRITE, 0,
		0, secsize[S_BSS], 0, 0, 4, 0);
	/* [4] .rel.text (link=symtab, info=.text) */
	shdr(n_rtext, SHT_REL, 0, 0,
		secdata[S_RTEXT], secsize[S_RTEXT], S_SYM, S_TEXT, 4, 8);
	/* [5] .rel.data */
	shdr(n_rdata, SHT_REL, 0, 0,
		secdata[S_RDATA], secsize[S_RDATA], S_SYM, S_DATA, 4, 8);
	/* [6] .symtab (link=strtab, info=first global) */
	shdr(n_sym, SHT_SYMTAB, 0, 0,
		secdata[S_SYM], secsize[S_SYM], S_STR, firstglobal, 4, SYMSZ);
	/* [7] .strtab */
	shdr(n_str, SHT_STRTAB, 0, 0,
		secdata[S_STR], secsize[S_STR], 0, 0, 1, 0);
	/* [8] .shstrtab */
	shdr(n_shstr, SHT_STRTAB, 0, 0,
		secdata[S_SHSTR], secsize[S_SHSTR], 0, 0, 1, 0);
	}

	/* patch e_shoff (offset 32 in the ELF header) */
	ob[32] = eshoff;
	ob[33] = eshoff>>8;
	ob[34] = eshoff>>16;
	ob[35] = eshoff>>24;

	/* write it out */
	fp = fopen(outf, "wb");
	if (fp == NULL)
		fatal("cannot open output");
	if (fwrite((char *)ob, 1, (int)oblen, fp) != oblen)
		fatal("write error");
	fclose(fp);
	return (0);
}

/*
 * Translate `n` COFF relocations starting at image offset `rp` into ELF32
 * Rel records (r_offset, r_info=(sym<<8)|type), appended to the output.
 */
emitrel(rp, n, symmap, secbase, secimgbase)
long	rp;
int	*symmap;
long	secbase;
unsigned secimgbase;
{
	int	i, ctype, etype, esym;
	unsigned vaddr, roff, fld;
	long	sidx, o, f;

	for (i = 0; i < n; i++) {
		o = rp + (long)i*RELSZ;
		vaddr = u32(o);			/* r_vaddr (an IMAGE offset) */
		sidx = u32(o+4);		/* r_symndx */
		ctype = u16(o+8);		/* r_type   */

		switch (ctype) {
		case R_DIR32:	etype = R_386_32; break;
		case R_PCRLONG:	etype = R_386_PC32; break;
		default:	fatal("unsupported COFF reloc type");
		}
		/*
		 * COFF r_vaddr is an absolute image offset; ELF r_offset is
		 * relative to the section being relocated, so subtract that
		 * section's image base.  (.text's base is 0, so .text relocs
		 * are unaffected; .data/.bss need the adjustment.)
		 */
		roff = vaddr - secimgbase;
		/*
		 * Rewrite the in-place addend to ELF conventions:
		 *  - subtract the referenced symbol's COFF value (image base
		 *    for a section symbol) so the addend is section-relative,
		 *    since the ELF section symbol's value is 0;
		 *  - for PC-relative, add the field offset back (ELF REL
		 *    recomputes S + A - P, subtracting the PC the COFF field
		 *    already removed).
		 */
		f = secbase + roff;
		fld = ob[f] | (ob[f+1]<<8) | (ob[f+2]<<16)
			| ((unsigned)ob[f+3]<<24);
		fld -= coffval[sidx];
		if (etype == R_386_PC32)
			fld += roff;
		ob[f] = fld; ob[f+1] = fld>>8;
		ob[f+2] = fld>>16; ob[f+3] = fld>>24;

		esym = symmap[sidx];
		ob32(roff);
		ob32(((unsigned)esym<<8) | (etype&0xFF));
	}
}

/*
 * Emit one ELF32 section header (40 bytes).
 */
shdr(name, type, flags, addr, off, size, link, info, align, entsz)
unsigned	addr;
long		off, size;
{
	ob32(name);
	ob32(type);
	ob32(flags);
	ob32(addr);
	ob32((unsigned)off);
	ob32((unsigned)size);
	ob32(link);
	ob32(info);
	ob32(align);
	ob32(entsz);
}

/* end of coff2elf.c */
