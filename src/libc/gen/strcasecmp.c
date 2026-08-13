/* strcasecmp() -- K&R, for the games ports. */
static int
lc(c)
register int c;
{
	return (c >= 'A' && c <= 'Z' ? c - 'A' + 'a' : c);
}

int
strcasecmp(a, b)
register char *a, *b;
{
	register int d;

	for (;;) {
		d = lc(*a & 0xFF) - lc(*b & 0xFF);
		if (d != 0 || *a == '\0')
			return (d);
		a++, b++;
	}
}
