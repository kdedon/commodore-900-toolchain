/ rem.t - Z8001 '%' (REM:). Same DIV as div.t but the result is the REMAINDER =
/ the high word (R0). The dividend goes in R1 (low word) -- a different register
/ than the result R0 -- so it is loaded there explicitly.
REM:
/ UNSIGNED remainder: zero-extend dividend.
%	PEFFECT|PRVALUE
	UWORD		RR0	R0	*	R0
		ADR|IMM		WORD
		ADR|IMM		WORD
			[ZLD]	[REGNO R1],[AL]
			[ZCLR]	[REGNO R0]
			[ZDIV]	[REGNO RR0],[AR]
/ SIGNED remainder: sign-extend dividend.
%	PEFFECT|PRVALUE
	FS16		RR0	R0	*	R0
		ADR|IMM		WORD
		ADR|IMM		WORD
			[ZLD]	[REGNO R1],[AL]
			[ZEXTS]	[REGNO RR0]
			[ZDIV]	[REGNO RR0],[AR]

/ 32-bit remainder: DIVL leaves the remainder in the high pair RR0.  The dividend goes
/ in RR2 (loaded explicitly, since the result RR0 differs); widen RQ0 then DIVL.
%	PEFFECT|PRVALUE
	FU32		RQ0	RR0	*	RR0
		ADR|IMM		LONG
		ADR|IMM		LONG
			[ZLDL]		[REGNO RR2],[AL]
			[ZSUBL]		[REGNO RR0],[REGNO RR0]
			[ZDIVL]		[REGNO RQ0],[AR]
%	PEFFECT|PRVALUE
	FS32		RQ0	RR0	*	RR0
		ADR|IMM		LONG
		ADR|IMM		LONG
			[ZLDL]		[REGNO RR2],[AL]
			[ZEXTSL]	[REGNO RR0]
			[ZDIVL]		[REGNO RQ0],[AR]
