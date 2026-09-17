/*
 * z8kdis -- decode one Z8001 instruction from the generated table.
 *
 * z8kdis() fills mnem and ops from w[0..nw-1] (big-endian instruction words,
 * nw = how many are actually available) and returns the instruction's length
 * in words.  pc is the byte address of w[0]; it is what the relative branches
 * are rendered against.  Segmented (Z8001) rendering throughout.
 */
#define	ZOPSMAX	80		/* longest operand text the table can render */

extern int z8kdis();		/* (w, nw, pc, mnem, ops) */
