/*
 * Copyright (c) 1977-1995 Robert Swartz.
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * Character types table
 * for the ASCII character set.
 * The table is indexed by (c)+129.  The 129 leading entries classify as
 * nothing and cover every negative value a char or an int can hold, EOF
 * (-1) among them at index 128; the 256 entries after them are indexed by
 * the ASCII values of the characters.
 */

#include <ctype.h>

unsigned char	_ctype[_CTYPEN] = {
	/* -128 to -2: no classification */
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0,	/* EOF */
	_C, _C, _C, _C, _C, _C, _C, _C,
	_C, _S|_C, _S|_C, _S|_C, _S|_C, _S|_C, _C, _C,
	_C, _C, _C, _C, _C, _C, _C, _C,
	_C, _C, _C, _C, _C, _C, _C, _C,
	/*
	 * Space is _S|_B -- whitespace, and printable-but-nothing-else.
	 * It read _S|_X here, which is whitespace and HEX DIGIT, and got
	 * both of its classifications wrong: isprint(' ') was false and
	 * isxdigit(' ') was true.  hunt(6) draws its maze through a put_ch()
	 * that diagnoses anything !isprint(), so every space in the maze
	 * printed "r,c,ch: <row>,<col>,32" across the screen instead of a
	 * blank.  The isxdigit half is worse and quieter: it makes a space a
	 * valid hex digit to anything that scans one.
	 */
	_S|_B, _P, _P, _P, _P, _P, _P, _P,
	_P, _P, _P, _P, _P, _P, _P, _P,
	_N, _N, _N, _N, _N, _N, _N, _N,
	_N, _N, _P, _P, _P, _P, _P, _P,
	_P, _U, _U, _U, _U, _U, _U, _U,
	_U, _U, _U, _U, _U, _U, _U, _U,
	_U, _U, _U, _U, _U, _U, _U, _U,
	_U, _U, _U, _P, _P, _P, _P, _P,
	_P, _L, _L, _L, _L, _L, _L, _L,
	_L, _L, _L, _L, _L, _L, _L, _L,
	_L, _L, _L, _L, _L, _L, _L, _L,
	_L, _L, _L, _P, _P, _P, _P, _C,
	/* 0x80 to 0xFF: no classification */
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
};
