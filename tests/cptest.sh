#!/bin/sh
# cptest.sh -- a word register compared with 0 is a TEST, and a TEST after an op
# that set the same flags goes.
#
# `CP Rn,#0' becomes `TEST Rn' when the branches after it read only Z and S (LT and
# GE become MI and PL) and nothing later reads its V or C; a `TEST Rn' right after a
# word op that wrote Rn is dropped.  Values of every comparison with 0, chains, loops
# and quotients over the signed edges, against host C; then shapes.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
DIS="$BUILD/tools/loutdis"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/c.c" <<'EOF'
extern printf();
int g;
id(x) int x; { g = x; return x; }
lt(x, y) int x, y; { register int r; r = id(x) - y; if (r < 0) return 1; return 2; }
ge(x, y) int x, y; { register int r; r = id(x) - y; if (r >= 0) return 1; return 2; }
gt(x, y) int x, y; { register int r; r = id(x) - y; if (r > 0) return 1; return 2; }
le(x, y) int x, y; { register int r; r = id(x) - y; if (r <= 0) return 1; return 2; }
sg(x) int x; { register int r; r = id(x); if (r < 0) return -1; if (r == 0) return 0; return 1; }
ab(x) int x; { register int r; r = id(x); return r < 0 ? -r : r; }
cnt(x) int x; { register int r, n; n = 0; for (r = id(x) & 7; --r >= 0; ) n++; return n; }
mid(x, y) int x, y; { return (x - y) / 2; }
up(x) int x; { return (x + 15) / 16; }
uns(x, y) unsigned x, y; { register unsigned r; r = x - y; if (r < 1) return 1; return 2; }
int v[] = { -32768, -32767, -16, -15, -2, -1, 0, 1, 2, 15, 16, 32766, 32767 };
main()
{
	int i, j;
	for (i = 0; i < sizeof v / sizeof v[0]; i++)
		for (j = 0; j < sizeof v / sizeof v[0]; j += 4)
			printf("%d %d %d %d %d %d %d %d %d %d\n", lt(v[i], v[j]), ge(v[i], v[j]),
			    gt(v[i], v[j]), le(v[i], v[j]), sg(v[i]), ab(v[i]), cnt(v[i]),
			    mid(v[i], v[j]), up(v[i]), uns(v[i], v[j]));
	return 0;
}
EOF
python3 -c '
def s16(n):
	n &= 0xFFFF
	return n - 65536 if n & 0x8000 else n
def td(a, b):
	q = abs(a) // abs(b)
	return q if (a < 0) == (b < 0) else -q
v = [-32768, -32767, -16, -15, -2, -1, 0, 1, 2, 15, 16, 32766, 32767]
for x in v:
	for y in v[::4]:
		r = s16(x - y)
		print(" ".join(str(n) for n in [1 if r < 0 else 2, 1 if r >= 0 else 2,
		    1 if r > 0 else 2, 1 if r <= 0 else 2, -1 if x < 0 else (0 if x == 0 else 1),
		    s16(-x) if x < 0 else x, (x & 7), td(r, 2), td(s16(x + 15), 16),
		    1 if (x - y) & 0xFFFF < 1 else 2]))
' > "$T/want"
[ -n "$N2" ] || { echo "  cptest: no guest runner"; exit 2; }
if (cd "$T" && "$CCZ" -o "$T/p" c.c >/dev/null 2>&1); then
	"$N2" -runexec "$T/p" > "$T/got" 2>/dev/null || true
	if cmp -s "$T/got" "$T/want"; then
		echo "  values ($(wc -l < "$T/want") pairs x 10 forms) PASS"
	else
		echo "  values FAIL:"; diff "$T/want" "$T/got" | sed 5q | sed 's/^/      /'; fail=1
	fi
else
	echo "  cptest: compile FAIL"; fail=1
fi

(cd "$T" && "$CCZ" -c -o "$T/c.o" c.c >/dev/null 2>&1) || { echo "  cptest: shapes compile FAIL"; exit 1; }
shape() { # <fn> <pattern that must not appear> <what>
	d=$("$DIS" -v -fn "$1" "$T/c.o" 2>/dev/null) || true
	if printf '%s\n' "$d" | grep -qE "$2"; then
		printf '  %-5s FAIL: %s\n' "$1" "$3"; printf '%s\n' "$d" | sed 's/^/      /'; fail=1
	else
		printf '  %-5s PASS  (%s)\n' "$1" "$3"
	fi
}
shape lt_ 'CP +R[0-9]+,#0x0000' "TEST, JR MI"
shape ge_ 'CP +R[0-9]+,#0x0000' "TEST, JR PL"
shape sg_ 'CP +R[0-9]+,#0x0000' "TEST, JR MI, JR EQ"
shape mid_ 'TEST' "SUB sets the flags the bias tests"
shape up_ 'TEST' "INC sets them"

[ "$fail" = 0 ] || { echo "=== cptest: FAIL ==="; exit 1; }
echo "=== cptest: PASS ==="
