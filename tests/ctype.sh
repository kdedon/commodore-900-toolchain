#!/bin/sh
# ctype.sh -- the _ctype table is indexed safely over the whole char range.
#
# The is*() macros index _ctype[(c)+129].  The 129 leading entries exist so
# that every negative value a caller can pass -- EOF, and any of 0x80..0xFF
# held in a signed char and promoted to int -- lands inside the table and
# classifies as nothing, rather than reading before it.
#
# The cases are checked twice: once against the host build of the same
# sources, and once through ccz (cc0/cc1/cc2 + ld + crt0 + libc-z8001.a) and
# the guest runner, so the answers come from the archive a program on the
# machine links against.
H="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

cat > "$T/t.c" <<'EOF'
#include <ctype.h>

extern int printf();

/* Reference classification, ASCII, independent of the table. */
int r_upper(c) int c; { return c >= 'A' && c <= 'Z'; }
int r_lower(c) int c; { return c >= 'a' && c <= 'z'; }
int r_digit(c) int c; { return c >= '0' && c <= '9'; }
int r_alpha(c) int c; { return r_upper(c) || r_lower(c); }
int r_cntrl(c) int c; { return (c >= 0 && c <= 0x1F) || c == 0x7F; }
int r_space(c) int c; { return c == ' ' || (c >= 0x09 && c <= 0x0D); }
int r_print(c) int c; { return c >= 0x20 && c <= 0x7E; }
int r_punct(c) int c; { return r_print(c) && c != ' ' && !r_alpha(c) && !r_digit(c); }

int bad = 0;

one(c, e_al, e_di, e_sp, e_up, e_lo, e_pu, e_cn, e_pr, tag)
	int c, e_al, e_di, e_sp, e_up, e_lo, e_pu, e_cn, e_pr; char *tag;
{
	if (!!isalpha(c) != e_al) { printf("FAIL %s %d isalpha\n", tag, c); bad++; }
	if (!!isdigit(c) != e_di) { printf("FAIL %s %d isdigit\n", tag, c); bad++; }
	if (!!isspace(c) != e_sp) { printf("FAIL %s %d isspace\n", tag, c); bad++; }
	if (!!isupper(c) != e_up) { printf("FAIL %s %d isupper\n", tag, c); bad++; }
	if (!!islower(c) != e_lo) { printf("FAIL %s %d islower\n", tag, c); bad++; }
	if (!!ispunct(c) != e_pu) { printf("FAIL %s %d ispunct\n", tag, c); bad++; }
	if (!!iscntrl(c) != e_cn) { printf("FAIL %s %d iscntrl\n", tag, c); bad++; }
	if (!!isprint(c) != e_pr) { printf("FAIL %s %d isprint\n", tag, c); bad++; }
}

/* Every entry the table can be asked for, so a short initialiser shows up. */
int tablen()
{
	int i, n;
	n = 0;
	for (i = 0; i < _CTYPEN; i++)
		n += _ctype[i] ? 1 : 0;
	return n;
}

main()
{
	int i;
	char sc;

	printf("_CTYPEN = %d, classified entries = %d\n", _CTYPEN, tablen());

	/* EOF classifies as nothing. */
	one(EOFVAL, 0,0,0,0,0,0,0,0, "EOF");

	/* 0..127: the ASCII half, checked against the reference. */
	for (i = 0; i <= 127; i++)
		one(i, r_alpha(i), r_digit(i), r_space(i), r_upper(i),
		    r_lower(i), r_punct(i), r_cntrl(i), r_print(i), "int");

	/* 128..255 as a positive int: nothing. */
	for (i = 128; i <= 255; i++)
		one(i, 0,0,0,0,0,0,0,0, "int-high");

	/* 128..255 through a signed char: promotes to -128..-1, and must
	   still answer nothing instead of reading before the table. */
	for (i = 128; i <= 255; i++) {
		sc = (char)i;
		one((int)sc, 0,0,0,0,0,0,0,0, "signed-char");
	}

	/* Spot values, printed so the high half is visible in the log. */
	printf("isalpha('A')=%d isalpha('z')=%d isdigit('7')=%d isspace(' ')=%d\n",
		!!isalpha('A'), !!isalpha('z'), !!isdigit('7'), !!isspace(' '));
	sc = (char)0xE9;			/* e-acute in Latin-1 */
	printf("0xE9 as int: isalpha=%d isprint=%d  as signed char (%d): isalpha=%d isprint=%d\n",
		!!isalpha(0xE9), !!isprint(0xE9), (int)sc, !!isalpha((int)sc), !!isprint((int)sc));
	sc = (char)0x80;
	printf("0x80 as signed char (%d): isalpha=%d iscntrl=%d ispunct=%d\n",
		(int)sc, !!isalpha((int)sc), !!iscntrl((int)sc), !!ispunct((int)sc));

	printf(bad ? "FAILED %d checks\n" : "all checks passed\n", bad);
	return bad ? 1 : 0;
}
EOF

rc=0

# The initialiser must fill the declared size exactly.  Too many entries is a
# compile error; too few is silently zero-filled, which is the same class of
# defect the leading entries exist to prevent, so it is measured rather than
# assumed.
echo "== table length =="
sed 's|unsigned char\t_ctype\[_CTYPEN\]|unsigned char probe[]|' \
	"$H/src/libc/gen/ctype.c" > "$T/probe.c"
cat >> "$T/probe.c" <<'EOF'
#include <stdio.h>
int main(void){ printf("initialiser elements = %zu, _CTYPEN = %d, %s\n",
	sizeof(probe), _CTYPEN,
	sizeof(probe)==_CTYPEN ? "match" : "MISMATCH"); 
	return sizeof(probe)!=_CTYPEN; }
EOF
gcc -w -I"$H/src/include" -o "$T/probe" "$T/probe.c" || exit 2
"$T/probe" || rc=1

echo "== host =="
gcc -w -DEOFVAL=-1 -I"$H/src/include" -o "$T/hostt" "$T/t.c" "$H/src/libc/gen/ctype.c" || exit 2
"$T/hostt" || rc=1

N2="${N2:-$(sh "$H/host/runner.sh" 2>/dev/null)}"
if [ -n "$N2" ] && [ -x "$H/host/ccz" ]; then
	echo "== z8001 target =="
	sed 's/EOFVAL/(-1)/' "$T/t.c" > "$T/g.c"
	if "$H/host/ccz" -o "$T/g.out" "$T/g.c" >"$T/ccz.log" 2>&1; then
		"$N2" --exec "$T/g.out" || rc=1
	else
		echo "SKIP: ccz failed"; sed -n '1,10p' "$T/ccz.log"
	fi
else
	echo "SKIP z8001 target: no runner"
fi
exit $rc
