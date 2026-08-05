/ arem.t - Z8001 compound remainder 'AREM' (x %= y).  As adiv but the result is the
/ remainder, left in R0 (high word of RR0) after DIV; store R0 back to the lvalue.

AREM:
%	PEFFECT|PRVALUE
	UWORD	RR0	*	*	R0
		ADR|LV	WORD
		ADR|IMM	WORD
		[ZLD]	[REGNO R1],[AL]
		[ZCLR]	[REGNO R0]
		[ZDIV]	[REGNO RR0],[AR]
		[ZLD]	[AL],[REGNO R0]
%	PEFFECT|PRVALUE
	FS16	RR0	*	*	R0
		ADR|LV	WORD
		ADR|IMM	WORD
		[ZLD]	[REGNO R1],[AL]
		[ZEXTS]	[REGNO RR0]
		[ZDIV]	[REGNO RR0],[AR]
		[ZLD]	[AL],[REGNO R0]

/ 32-bit `l %= r':  as the long ADIV but DIVL leaves the remainder in the high pair
/ RR0; load lvalue into RR2, extend into RR0, DIVL RQ0,rhs, store RR0 (remainder) back.
%	PEFFECT|PRVALUE
	FU32	RQ0	*	*	RR0
		ADR|LV	LONG
		ADR|IMM	LONG
		[ZLDL]		[REGNO RR2],[AL]
		[ZSUBL]		[REGNO RR0],[REGNO RR0]
		[ZDIVL]		[REGNO RQ0],[AR]
		[ZLDL]		[AL],[REGNO RR0]
%	PEFFECT|PRVALUE
	FS32	RQ0	*	*	RR0
		ADR|LV	LONG
		ADR|IMM	LONG
		[ZLDL]		[REGNO RR2],[AL]
		[ZEXTSL]	[REGNO RR0]
		[ZDIVL]		[REGNO RQ0],[AR]
		[ZLDL]		[AL],[REGNO RR0]

/ char lvalue (word-typed node over a byte): the adiv byte dividend widening (signed
/ EXTSB+EXTS, unsigned a single zeroing SUBL), then the remainder rather than the
/ quotient -- DIV leaves it in R0, the high word of the pair.  Its sign follows the
/ dividend, so it is always in char range; store its low byte, and widen that byte
/ back for a VALUE context.
%	PEFFECT|PRVALUE
	WORD	RR0	*	*	R0
		ADR|LV	FS8
		ADR|IMM	WORD
		[ZLDB]	[LO REGNO R1],[AL]
		[ZEXTSB]	[REGNO R1]
		[ZEXTS]	[REGNO RR0]
		[ZDIV]	[REGNO RR0],[AR]
		[ZLDB]	[AL],[LO REGNO R0]
	[IFV]	[ZEXTSB]	[REGNO R0]
%	PEFFECT|PRVALUE
	WORD	RR0	*	*	R0
		ADR|LV	FU8
		ADR|IMM	WORD
		[ZSUBL]	[REGNO RR0],[REGNO RR0]
		[ZLDB]	[LO REGNO R1],[AL]
		[ZDIV]	[REGNO RR0],[AR]
		[ZLDB]	[AL],[LO REGNO R0]
	[IFV]	[ZCLRB]	[HI REGNO R0]
