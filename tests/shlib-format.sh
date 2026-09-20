#!/bin/sh
# shlib-format.sh -- slgen builds a shared library in the format
# src/include/shlib.h publishes, read back by tests/shlib-check.py.
#
# The toy has every fixup shape: a call into the shared segment, a private
# variable, and a string reached through a far pointer in private data.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"		# $BUILD
O="$BUILD/z8001"; AS="$BUILD/as-z8001"; LD="$BUILD/ld-z8001"
SLGEN="$BUILD/slgen"; VAR="${VAR:-800000000800}"; PEEP="${PEEP:-0010}"
[ -x "$SLGEN" ] || { echo "shlib-format: slgen not built"; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/toy.c" <<'EOF'
int toy_count;

int toy_add(a, b) int a, b;
{
	return a + b;
}

int toy_bump(k) int k;
{
	toy_count = toy_add(toy_count, k);	/* private data + inner call */
	return toy_count;
}

char *toy_name()
{
	return "toy library";			/* a constant, through a pool */
}
EOF
"$O/cc0-z8001" $VAR "$T/toy.c" "$T/toy.z0" > /dev/null 2>&1
"$O/cc1-z8001" $VAR "$T/toy.z0" "$T/toy.z1" > /dev/null 2>&1
"$O/cc2-z8001" $PEEP "$T/toy.z1" "$T/toy.o" "$T/toy.scr" 0 > /dev/null 2>&1
# SS relocations are L_ABS and must not become fixups.
printf '\t.globl\tSS\nSS = 0\n' > "$T/ss.s"; "$AS" -o "$T/ss.o" "$T/ss.s"
printf 'toy_name_\ntoy_add_\t# order does not matter: slgen sorts\ntoy_bump_\n' \
	> "$T/toy.exp"

"$SLGEN" -A "$AS" -L "$LD" -T "$T" -e "$T/toy.exp" -o "$T/toy.1" \
	"$T/toy.o" "$T/ss.o"
python3 "$H/tests/shlib-check.py" "$T/toy.1" "$T/toy.exp" || fail=1

# Negative control: drop the last fixup, keeping counts consistent.  The
# checker must notice.
python3 - "$T/toy.1" "$T/broken.1" <<'PY'
import sys
b = bytearray(open(sys.argv[1], 'rb').read())
size = [((b[8+4*i] | b[9+4*i] << 8) << 16) | (b[10+4*i] | b[11+4*i] << 8)
        for i in range(9)]
off, o = {}, 48
for i in range(9):
    if i in (2, 5):
        continue
    off[i] = o; o += size[i]
s = off[0]
n = (b[s+8] << 8 | b[s+9]) - 1                  # sl_nfix
b[s+8], b[s+9] = n >> 8, n & 0xFF
d = off[6] + n * 4                              # drop the last entry
del b[d:d+4]
b[8+4*6], b[9+4*6] = 0, 0                       # l_ssize[L_DEBUG] = 4*n,
b[10+4*6], b[11+4*6] = (n*4) & 0xFF, (n*4) >> 8 & 0xFF   # low byte first
open(sys.argv[2], 'wb').write(bytes(b))
PY
echo "  -- the same library with one fixup removed:"
if python3 "$H/tests/shlib-check.py" "$T/broken.1" "$T/toy.exp" \
	> "$T/broken.log" 2>&1; then
	echo "  FAIL the checker passed a library with a missing fixup"
	fail=1
else
	echo "  PASS refused: $(grep -m1 '^  FAIL' "$T/broken.log" | \
		sed 's/^  FAIL //')"
fi

# slgen refuses an undefined listed name, and two names equal in 16 characters.

printf 'toy_add_\ntoy_missing_\n' > "$T/bad.exp"
if "$SLGEN" -A "$AS" -L "$LD" -T "$T" -e "$T/bad.exp" -o "$T/bad.1" \
	"$T/toy.o" "$T/ss.o" > "$T/bad.log" 2>&1; then
	echo "  FAIL slgen exported a symbol the library does not define"
	fail=1
else
	echo "  PASS $(grep -m1 'not defined' "$T/bad.log")"
fi
printf 'toy_a_very_long_name_one\ntoy_a_very_long_name_two\n' > "$T/coll.exp"
if "$SLGEN" -A "$AS" -L "$LD" -T "$T" -e "$T/coll.exp" -o "$T/coll.1" \
	"$T/toy.o" "$T/ss.o" > "$T/coll.log" 2>&1; then
	echo "  FAIL slgen accepted two exports that collide in 16 characters"
	fail=1
else
	echo "  PASS $(grep -m1 'one symbol in' "$T/coll.log")"
fi

[ $fail = 0 ] && echo "shlib-format: slgen and the library format agree"
exit $fail
