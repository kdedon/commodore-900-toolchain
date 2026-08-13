/* strtoul() -- K&R subset (bases 8/10/16, leading blanks, 0x prefix). */
unsigned long
strtoul(s, endp, base)
register char *s;
char **endp;
int base;
{
	register unsigned long v;
	register int c, d;

	while (*s == ' ' || *s == '\t')
		s++;
	if (base == 0) {
		base = 10;
		if (s[0] == '0')
			base = (s[1] == 'x' || s[1] == 'X') ? 16 : 8;
	}
	if (base == 16 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
		s += 2;
	v = 0;
	for (;; s++) {
		c = *s;
		if (c >= '0' && c <= '9')
			d = c - '0';
		else if (c >= 'a' && c <= 'f')
			d = c - 'a' + 10;
		else if (c >= 'A' && c <= 'F')
			d = c - 'A' + 10;
		else
			break;
		if (d >= base)
			break;
		v = v * base + d;
	}
	if (endp != (char **)0)
		*endp = s;
	return (v);
}
