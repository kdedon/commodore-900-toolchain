/*
 * Copyright (c) 1977-1995 Robert Swartz.
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * Ceiling.
 * The first word of a double holds its sign and exponent: |x| >= 2^52 is
 * integral, and x < 0 truncates to its ceiling.
 */
#include <math.h>

double
ceil(x)
double x;
{
	double r;
	register int hi;

	hi = *(int *)&x;
	if ((hi & 0x7FF0) >= 0x4330)
		return (x);
	modf(x, &r);
	if (hi >= 0 && r != x)
		r += 1.0;
	return (r);
}
