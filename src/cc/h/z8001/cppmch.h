/*
 * h/z8001/cppmch.h -- preprocessor machine definitions, Segmented Z8001 (== i386 base).
 * i386.
 */

/*
 * n0/cc0.c defines MACHINE, SYSTEM, LOCATION and FPFORMAT for cpp by default.
 * It also defines ISO-compatible versions, e.g. "__COHERENT__".
 * The code in n0/cc0.c knows that MACHINE and FPFORMAT defined below
 * have leading '_' but SYSTEM and LOCATION do not,
 * it must change if the definitions here change.
 */

#define	MACHINE	 "_Z8001"

/*
 * OLDMACHINE is the same target under the spelling the June 1985 compiler's
 * standalone cpp predefines: unprefixed `Z8001'.  The COHERENT 3.2 sources
 * select on it -- <l.out.h> takes the n.out object layout under `#ifdef Z8001',
 * sbrk() its segment-crossing arithmetic, exec() its shared-library arms -- so
 * a compiler that defines only the ISO-reserved spellings silently builds the
 * wrong layout.  Both spellings are live: the toolchain's own vendored headers
 * (host/include/l.out.h, canon.h) select on `_Z8001'.
 */
#define	OLDMACHINE	"Z8001"

#if	IEEE
#define	FPFORMAT	"_IEEE"
#endif
#if	DECVAX
#define	FPFORMAT	"_DECVAX"
#endif

#ifdef	UDI
#define	LOCATION	"SERIESIII"
#define	SYSTEM		"UDI"
#define	DEFDISK		""
#endif

#ifdef	COHERENT
#define	LOCATION	"MWC"
#define	SYSTEM		"COHERENT"
#ifdef	FLOPPY
#define	DEFDISK		"/lib/include"
#else
#define	DEFDISK		"/usr/include"
#endif
#endif

#ifdef	vax
#define	LOCATION	"VAX"
#define	SYSTEM		"UDI"
#define	DEFDISK		"CC86$INCLUDE:"
#endif

#ifdef	MSDOS
#define	LOCATION	"MWC86"
#define	SYSTEM		"MSDOS"
#define	DEFDISK		""
#endif

/* end of h/i386/cppmch.h */
