/ div.t - Z8001 '/' (DIV:). Z8000 DIV RRd,Rs: 32-bit RRd / 16-bit Rs -> quotient
/ in the low word (Rd+1), remainder in the high word (Rd). We use the fixed pair
/ RR0; the C int result is the quotient = R1. The Z8000 DIV is SIGNED, so the
/ dividend extension depends on signedness: UNSIGNED zero-extends (CLR high word),
/ SIGNED sign-extends (EXTS). [LONG div is a runtime call (mtree2 makecall).]
/ [NOTE: unsigned via signed DIV is exact only while the divisor < 0x8000. A
/ divisor >= 0x8000 that is CONSTANT is strength-reduced in mtree2 (x/C -> x>=C);
/ a runtime divisor >= 0x8000 keeps the original backend's signed-DIV behaviour,
/ a deliberate match, not a runtime helper.]
DIV:
/ UNSIGNED first (UWORD = FU16): zero-extend the dividend.
%	PEFFECT|PRVALUE
	UWORD		RR0	R1	*	R1
		TREG		WORD
		ADR|IMM		WORD
			[ZCLR]	[REGNO R0]
			[ZDIV]	[REGNO RR0],[AR]
/ SIGNED (FS16): sign-extend the dividend.
%	PEFFECT|PRVALUE
	FS16		RR0	R1	*	R1
		TREG		WORD
		ADR|IMM		WORD
			[ZEXTS]	[REGNO RR0]
			[ZDIV]	[REGNO RR0],[AR]

/ 32-bit divide: DIVL RQ0,Rs gives the quotient in the low pair RR2.  The dividend
/ (in RR2) is widened to the 64-bit RQ0 first -- sign-extend (EXTSL) for signed, or
/ zero the high pair (SUBL) for unsigned.
%	PEFFECT|PRVALUE
	FU32		RQ0	RR2	*	RR2
		TREG		LONG
		ADR|IMM		LONG
			[ZSUBL]		[REGNO RR0],[REGNO RR0]
			[ZDIVL]		[REGNO RQ0],[AR]
%	PEFFECT|PRVALUE
	FS32		RQ0	RR2	*	RR2
		TREG		LONG
		ADR|IMM		LONG
			[ZEXTSL]	[REGNO RR0]
			[ZDIVL]		[REGNO RQ0],[AR]
