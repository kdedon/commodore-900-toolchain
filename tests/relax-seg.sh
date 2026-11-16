#!/bin/sh
# relax-seg.sh -- under -L, calls from a module at the bottom of a text
# segment become CALR.
#
# p.o follows a filler that leaves it 2 to 8 bytes short of fitting in
# segment 3 with its two CALLs long.  With them CALR it fits, where q1_ in
# segment 4 is out of reach, so ld barred them and left both long once p.o
# went back to segment 4 beside q1_.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"; CC1="$BUILD/z8001/cc1-z8001"
CC2="$BUILD/z8001/cc2-z8001"; AS="$BUILD/as-z8001"; LD="$BUILD/ld-z8001"
DIS="$BUILD/tools/loutdis"; LIBC="$BUILD/libc-z8001"
N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/p.c" <<'EOF'
extern int q1();
p1(x) { return q1(x) + q1(x + 1); }
EOF
# q1_ lies past offset 256 of segment 4, beyond the short CALL's reach.
{
	echo "q2(x) {"
	i=0
	while [ $i -lt 100 ]; do echo "	x = x ^ $i;"; i=$((i+1)); done
	echo "	return x;"
	echo "}"
	echo "q1(x) { return x * 3 + 1; }"
} > "$T/q.c"
cat > "$T/m.c" <<'EOF'
#include <stdio.h>
extern int p1(), q2();
main() { printf("%d %d\n", p1(4), q2(6)); return 0; }
EOF
for s in p q m; do
	"$CC0" $VAR "$T/$s.c" "$T/$s.z0" -I"$H/src/include" && "$CC1" $VAR "$T/$s.z0" "$T/$s.z1" &&
	"$CC2" 0012 "$T/$s.z1" "$T/$s.o" "$T/$s.scr" 0 ||
		{ echo "  relax-seg: compile FAIL"; exit 1; }
done

link() {	# link FILLER-BYTES: out, and p1_'s address
	printf '\t.globl\tfill_\n\t.shri\nfill_:\t.blkb\t%d\n' "$1" > "$T/f.s"
	"$AS" -o "$T/f.o" "$T/f.s"
	"$LD" -n -i -L -o "$T/out" "$LIBC/crt0.o" "$T/f.o" "$T/p.o" "$T/q.o" "$T/m.o" \
		"$LIBC/libc-z8001.a" >/dev/null
	python3 - "$T/out" <<'PY'
import sys
b = open(sys.argv[1], 'rb').read()
pdp = lambda o: (b[o] | b[o+1] << 8) << 16 | (b[o+2] | b[o+3] << 8)
ss = [pdp(8 + 4*i) for i in range(9)]
o = 48 + sum(s for i, s in enumerate(ss[:7]) if i not in (2, 5))
for e in range(o, o + ss[7], 22):
	if b[e:e+16].split(b'\0')[0] == b'p1_':
		print(pdp(e + 18))
PY
}

# p.o's text size with both CALLs long, and where it lands after 60000 bytes.
psize=$(python3 -c "
b = open('$T/p.o', 'rb').read()
print((b[8] | b[9] << 8) << 16 | (b[10] | b[11] << 8))")
a=$(link 60000)
base=$((60000 + 65536 - (a & 65535)))
for over in 2 4 6 8; do
	a=$(link $((base - psize + over)))
	n=$("$DIS" -v "$T/out" 2>/dev/null | awk -v lo=$(((a >> 24) - 3 << 16 | a & 65535)) \
		-v n="$psize" '$1 ~ /^[0-9a-f]+:$/ { o = 0; h = substr($1, 1, length($1) - 1)
		for (i = 1; i <= length(h); i++) o = o * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1
		if (o >= lo && o < lo + n && $2 == "CALR") c++ } END { print c + 0 }')
	what="p.o $over bytes over segment 3: 2 CALR"
	if [ $((a >> 24)) = 4 ] && [ $((a & 65535)) = 0 ] && [ "$n" = 2 ]; then
		printf '  %-46s PASS\n' "$what"
	else
		printf '  %-46s FAIL p1_=%x calr=%s\n' "$what" "$a" "$n"; fail=1
	fi
done
got=$("$N2" -runexec "$T/out" 2>/dev/null | grep -E '^[0-9]+ [0-9]+$') || true
if [ "$got" = "29 6" ]; then
	printf '  %-46s PASS\n' "values"
else
	printf '  %-46s FAIL got=[%s]\n' "values" "$got"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== relax-seg: FAIL ==="; exit 1; }
echo "=== relax-seg: PASS ==="
