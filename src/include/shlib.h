/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * Z8001 shared-library format, written by slgen and ld, read by the kernel.
 *
 * A library is an l.out with LF_SLIB, linked `ld -n' into two segments:
 *
 *	shared	L_SHRI, L_SHRD; mapped read-only into every client
 *	private	L_PRVI, L_PRVD, L_BSSI, L_BSSD; copied per client
 *
 * It is linked at SL_NOMSHR/SL_NOMPRV and relocated by the kernel at first
 * load.  Offsets are from the base of the named segment.  Tables are target
 * memory images (high byte first), since the kernel reads them in place:
 *
 *	struct slhead		at shared offset 0
 *	struct slexp[sl_nexp]	at sl_expoff, sorted by memcmp of se_name
 *
 * The fixup list, in L_DEBUG so it costs no RAM, names the segment byte of
 * every segmented address in the library: shared fixups first, then
 * private, each by rising sf_off.  Bit 7 of that byte is the long-address
 * marker, so the kernel keeps it:
 *
 *	b = (SF_LOC_PRIVATE & f.sf_flags ? privbase : shrbase) + f.sf_off;
 *	s = (SF_REF_PRIVATE & f.sf_flags ? privseg  : shrseg);
 *	*b = (*b & 0x80) | (s & 0x7F);
 *
 * slgen builds it from the non-PC-relative LR_LONG records into the six
 * library segments.  Those records stay in the file so a checker can
 * prove the list complete.
 */
#ifndef	SHLIB_H
#define	SHLIB_H	SHLIB_H

#ifndef	L_OUT_H
#include <n.out.h>			/* NCPLN, L_DEBUG, LF_SLIB, LF_SLREF */
#endif

#define	SL_MAGIC	0x534C		/* `SL'				*/
#define	SL_VERSION	1		/* this format			*/

#define	SL_NOMSHR	3		/* nominal shared segment	*/
#define	SL_NOMPRV	4		/* nominal private segment	*/

/*
 * The header at offset 0 of the shared segment.
 *	off  0	short	sl_magic	SL_MAGIC
 *	off  2	short	sl_vers		SL_VERSION
 *	off  4	short	sl_nexp		number of export entries
 *	off  6	short	sl_expoff	offset of entry 0 (= 16)
 *	off  8	short	sl_nfix		number of fixup entries
 *	off 10	short	sl_fixsec	l.out section holding them (L_DEBUG)
 *	off 12	long	sl_fixoff	their offset from the start of the file
 */
struct	slhead {
	unsigned short	sl_magic;
	unsigned short	sl_vers;
	unsigned short	sl_nexp;
	unsigned short	sl_expoff;
	unsigned short	sl_nfix;
	unsigned short	sl_fixsec;
	long		sl_fixoff;
};
#define	SL_HDRLEN	16		/* sizeof(struct slhead) on target */

/*
 * One export.  20 bytes.
 *	off  0	char[16] se_name	NUL-padded linker name, e.g. "printf_"
 *	off 16	short	 se_flags	SE_* below; 0 for a function
 *	off 18	short	 se_off		private offset for plain SE_DATA,
 *					else shared offset
 */
struct	slexp {
	char		se_name[NCPLN];
	unsigned short	se_flags;
	unsigned short	se_off;
};
#define	SL_EXPLEN	20		/* sizeof(struct slexp) on target */

#define	SE_DATA		0x0001		/* per-client data object	*/
#define	SE_SHRD		0x0002		/* with SE_DATA: readonly, in L_SHRD */

/*
 * One fixup.  4 bytes.
 *	off 0	short	sf_flags	SF_* below
 *	off 2	short	sf_off		offset of the segment byte
 */
struct	slfix {
	unsigned short	sf_flags;
	unsigned short	sf_off;
};
#define	SL_FIXLEN	4		/* sizeof(struct slfix) on target */

#define	SF_LOC_PRIVATE	0x0001		/* byte is in the private image	*/
#define	SF_REF_PRIVATE	0x0100		/* it addresses the private one	*/

/*
 * A client (LF_SLREF) keeps L_SYM even under `ld -s', holding ldsym records:
 *
 *	LI_LIB	ls_id	library file name searched along LIBPATH, e.g. "libc.1"
 *		ls_addr	0
 *	LI_IMP	ls_id	imported linker name, matched against se_name
 *		ls_addr	4-byte slot in client data that exec fills with a far
 *			pointer: into the shared segment for a function, into
 *			the client's private copy for SE_DATA
 *
 * LI_IMPs belong to the preceding LI_LIB.  A data object has one LI_IMP per
 * pointer cell the client holds, so every module sees one object.
 */
#define	LI_LIB		013		/* 11: names a library		*/
#define	LI_IMP		014		/* 12: names an import from it	*/

#endif	/* SHLIB_H */
