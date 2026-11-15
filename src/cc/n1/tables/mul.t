/ Copyright (c) 2026 Kevin Dedon.
/ SPDX-License-Identifier: MIT
/ mul.t - Z8001 '*' (MUL:).
/ The Z8000 MULT RRd,Rs multiplies the LOW word of the destination pair RRd by the
/ source Rs and leaves the 32-bit product in RRd; the C `int` result is that low
/ word. We use the fixed pair RR0 (= R0:R1): the multiplicand + result live in R1
/ (the low half) and R0 (the high half) is clobbered -- exactly the i8086 DXAX/AX
/ shape, since the Z8000 MULT (like x86 MUL) ties the result to a register pair.
/ [A flexible pair allocation would avoid always clobbering RR0.]
MUL:
%	PEFFECT|PRVALUE
	WORD		RR0	R1	*	R1
		TREG		WORD
		ADR|IMM		WORD
			[ZMULT]	[REGNO RR0],[AR]

/ Long product of two words: MULT's 32-bit product is the result.  An
/ unsigned word times a non-negative word reads the first as signed; when it has
/ bit 15 set the product is negative, and adding the second factor to the high
/ word corrects it.
%	PEFFECT|PRVALUE
	LONG		RR0	R1	*	RR0
		TREG		FS16
		ADR|IMM		FS16
			[ZMULT]	[REGNO RR0],[AR]
%	PEFFECT|PRVALUE
	LONG		RR0	R1	*	RR0
		TREG		FU16
		ADR|IMM		FS16
			[ZMULT]	[REGNO RR0],[AR]
			[ZJRPL]	[LAB0]
			[ZADD]	[REGNO R0],[AR]
		[DLAB0]:
%	PEFFECT|PRVALUE
	LONG		RR0	*	*	RR0
		ADR|IMM		FS16
		ADR		FU16
			[ZLD]	[REGNO R1],[AR]
			[ZMULT]	[REGNO RR0],[AL]
			[ZJRPL]	[LAB0]
			[ZADD]	[REGNO R0],[AL]
		[DLAB0]:

/ Two unsigned words: each one with bit 15 set adds the other to the high word.
/ A zero product needs neither, and skipping both keeps a zero multiplier as
/ quick as MULTL's.
%	PEFFECT|PRVALUE
	LONG		RQ0	R1	*	RR0
		TREG		FU16
		ADR		FU16
			[ZLD]	[REGNO R2],[AR]
			[ZLD]	[REGNO R3],[REGNO R1]
			[ZMULT]	[REGNO RR0],[REGNO R2]
			[ZJREQ]	[LAB1]
			[ZTEST]	[REGNO R3]
			[ZJRPL]	[LAB0]
			[ZADD]	[REGNO R0],[REGNO R2]
		[DLAB0]:[ZTEST]	[REGNO R2]
			[ZJRPL]	[LAB1]
			[ZADD]	[REGNO R0],[REGNO R3]
		[DLAB1]:
/ An unsigned word, still widened in RR2, times a signed one: only the unsigned
/ factor needs the correction, and the sign of the product does not tell it.
/ The unsigned factor is an unsigned long, and modswap leaves no other long
/ times a short whose widening the selector could drop to reach these rules.
%	PEFFECT|PRVALUE
	LONG		RQ0	RR2	*	RR0
		TREG		FU32
		IMM|MMX		FS16
			[ZLD]	[REGNO R1],[REGNO R3]
			[ZMULT]	[REGNO RR0],[AR]
			[ZTEST]	[REGNO R3]
			[ZJRPL]	[LAB0]
			[ZADD]	[REGNO R0],[AR]
		[DLAB0]:
%	PEFFECT|PRVALUE
	LONG		RQ0	RR2	*	RR0
		TREG		FU32
		ADR		FS16
			[ZLD]	[REGNO R2],[AR]
			[ZLD]	[REGNO R1],[REGNO R3]
			[ZMULT]	[REGNO RR0],[REGNO R2]
			[ZTEST]	[REGNO R3]
			[ZJRPL]	[LAB0]
			[ZADD]	[REGNO R0],[REGNO R2]
		[DLAB0]:

/ 32-bit multiply: MULTL RQ0,Rs gives the 64-bit product in RQ0; the long result is
/ its low pair RR2.  Signed and unsigned agree in the low 32 bits, so one rule.
%	PEFFECT|PRVALUE
	LONG		RQ0	RR2	*	RR2
		TREG		LONG
		ADR|IMM		LONG
			[ZMULTL]	[REGNO RQ0],[AR]
