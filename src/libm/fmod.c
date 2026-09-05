/*
 * Copyright (c) 1977-1995 Robert Swartz.
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * Floating point remainder function, ANSI 4.5.6.4.
 * Implementation-defined behavior: issues EDOM and returns 0.0 when y == 0.0.
 */
#include <math.h>
#include <errno.h>

double
fmod(x, y)
double x, y;
{
	register int s;

	if (y == 0.0) {
		errno = EDOM;
		return (0.0);
	}
	s = (x >= 0);
	x = fabs(x);
	y = fabs(y);
	x -= y * floor(x/y);
	return (s ? x : -x);
}
