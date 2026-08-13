/* strchr/strrchr -- ANSI names for the V7 index/rindex (games/elvis/rogue). */
char *strchr(s, c) char *s; int c; { char *index(); return (index(s, c)); }
char *strrchr(s, c) char *s; int c; { char *rindex(); return (rindex(s, c)); }
