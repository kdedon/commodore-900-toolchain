/*
 * strrchr - ANSI name for rindex(): last occurrence of c.
 * libc/gen/rindex.c holds the code; this is an alias for it.
 */
char *
strrchr(s, c)
char	*s;
{
	char	*rindex();

	return (rindex(s, c));
}
