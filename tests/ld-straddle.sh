#!/bin/sh
# ld-straddle.sh -- no output section crosses a hardware segment boundary.
#
# A Z8001 address is seg:offset with a 16-bit offset, so an object across a
# 64K boundary has its tail wrap to the bottom of its own segment.  A section
# after the first can start anywhere: text ending near the top of segment 3
# puts the string literals (SHRD) after it across the boundary, and the
# string there reads text from offset 0.  ld starts a section that would
# cross a boundary at the next segment, the skipped bytes leading it: they are
# counted in its header size and are zeros in the file, so a loader that lays
# the sections end to end finds the contents at the base ld gave them.
#
# Part 1 links assembler objects alone and checks the bases, header sizes and
# file bytes for the default layout, -L and -i, crossing and not.  Part 2 runs
# a C program whose text is padded so that a string literal would cross the
# boundary, and needs the guest runner.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"		# $BUILD
AS="$BUILD/as-z8001"; LD="$BUILD/ld-z8001"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

asm() {		# asm NAME SECTION SYMBOL SIZE
	printf '\t.globl\t%s\n\t.%s\n%s:\t.blkb\t%d\n' "$3" "$2" "$3" "$4" > "$T/$1.s"
	"$AS" -o "$T/$1.o" "$T/$1.s"
}
asm t30k shri t_ 30000
asm t65k shri t_ 65520
asm t1k shri t_ 1000
asm t100 shri t_ 100
asm s100 shrd s_ 100
asm s40k shrd s_ 40000
asm p2 prvd p_ 2
asm p40k prvd p_ 40000
asm b40k bssd b_ 40000

# NAME FLAGS OBJECTS -- SYMBOL=ADDRESS... SECTION=HEADER-SIZE...
check() {
	n=$1; f=$2; o=$3; shift 3
	# shellcheck disable=SC2086
	"$LD" $f -o "$T/$n.out" $(for x in $o; do echo "$T/$x.o"; done)
	python3 - "$T/$n.out" "$n" "$@" <<'PY' || fail=1
import sys
NLSEG, HDR, SYMSZ, NCPLN = 9, 48, 22, 16
NAMES = ['SHRI', 'PRVI', 'BSSI', 'SHRD', 'PRVD', 'BSSD', 'DEBUG', 'SYM', 'REL']
def pdplong(b, o):
	return (b[o] | b[o+1] << 8) << 16 | (b[o+2] | b[o+3] << 8)
path, name = sys.argv[1], sys.argv[2]
b = open(path, 'rb').read()
ss = [pdplong(b, 8 + 4*i) for i in range(NLSEG)]
off = HDR + sum(s for i, s in enumerate(ss[:7]) if i not in (2, 5))
syms = {}
for o in range(off, off + ss[7], SYMSZ):
	syms[b[o:o+NCPLN].split(b'\0')[0].decode()] = pdplong(b, o+NCPLN+2)
foff, at = {}, HDR
for i in range(7):
	if i not in (2, 5):
		foff[NAMES[i]] = at
		at += ss[i]
bad = []
for a in sys.argv[3:]:
	k, v = a.split('=')
	v = int(v, 0)
	if k in NAMES:
		if ss[NAMES.index(k)] != v:
			bad.append('%s size %d, want %d' % (k, ss[NAMES.index(k)], v))
	elif syms.get(k) != v:
		bad.append('%s at 0x%08x, want 0x%08x' % (k, syms.get(k, 0), v))
# the bytes a leading gap occupies in the file are zeros
for k in ('SHRD', 'PRVD'):
	i = NAMES.index(k)
	if ss[i] and any(b[foff[k]:foff[k] + min(ss[i], 16)]):
		bad.append('%s does not start with zeros' % k)
print('  %s %s' % ('FAIL' if bad else 'ok  ', name), '; '.join(bad))
sys.exit(1 if bad else 0)
PY
}

echo "=== 1 section bases and header sizes"
# default layout: SHRD would cross 0x40000 and starts there; PRVD follows it
check deflt "" "t65k s100 p2" s_=0x04000000 p_=0x04000064 SHRD=116 PRVD=2
check deflt-fits "" "t1k s100 p2" s_=0x030003e8 p_=0x0300044c SHRD=100 PRVD=2
# -L: PRVD smaller than a segment, crossing one, starts at the next
check large "-L" "t30k p40k" t_=0x03000000 p_=0x04000000 PRVD=75536
# -i: the data group starts at segment 4; PRVD would cross into 5
check sep "-i" "t100 s40k p40k" s_=0x04000000 p_=0x05000000 SHRD=40000 PRVD=65536
# -i: BSSD would cross; it costs no file bytes
check sep-bss "-i" "t100 p40k b40k" p_=0x04000000 b_=0x05000000 PRVD=40000 BSSD=65536
check sep-fits "-i" "t100 s100 p2" s_=0x04000000 p_=0x04000064 SHRD=100 PRVD=2

echo "=== 2 a string literal at the boundary"
N2="${N2:-$(sh "$H/host/runner.sh" 2>/dev/null || true)}"
if [ -z "$N2" ]; then
	echo "  skipped: no guest runner"
else
	cat > "$T/m.c" <<'EOF'
extern printf();
main() { printf("<a string literal across the boundary>\n"); return 0; }
EOF
	# The pad goes between crt0 and main, so the text after it keeps its
	# shape; the next tries absorb any change relaxation makes.  4K of
	# shared data ahead of the string keeps the text clear of 64K.  The
	# string is placed where it would start 8 bytes below 0x40000 if SHRD
	# followed the text directly.
	p=0; i=0; o=
	while [ $i -lt 4 ]; do
		printf '\t.shri\n\t.blkb\t%d\n\t.shrd\n\t.blkb\t4096\n' "$p" > "$T/pad.s"
		"$H/host/ccz" -o "$T/m.out" "$T/pad.s" "$T/m.c" >/dev/null 2>&1
		set -- $(python3 - "$T/m.out" "$p" "$o" <<'PY'
import sys
b = open(sys.argv[1], 'rb').read()
pdp = lambda o: (b[o] | b[o+1] << 8) << 16 | (b[o+2] | b[o+3] << 8)
si, pi = pdp(8), pdp(12)
p = int(sys.argv[2])
# the string's offset in SHRD, from the first link, which has no lead
o = int(sys.argv[3]) if sys.argv[3] else b.index(b'<a string') - 48 - si - pi
at = 0x30000 + si + pi + o
print(p + (0x3FFF8 + (o & 1) - at), o)
PY
)
		p=$1; o=$2; i=$((i + 1))
	done
	got=$("$N2" -runexec "$T/m.out" 2>/dev/null | grep -av '^\[exit' || true)
	if [ "$got" = "<a string literal across the boundary>" ]; then
		echo "  ok   printed whole (text padded by $p bytes)"
	else
		echo "  FAIL printed [$got] (text padded by $p bytes)"; fail=1
	fi
fi

[ "$fail" = 0 ] || { echo "=== ld sections vs segment boundary: FAIL ==="; exit 1; }
echo "=== ld sections vs segment boundary: PASS ==="
