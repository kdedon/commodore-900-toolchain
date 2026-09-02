#!/bin/sh
# ld-commons.sh -- a common must lie inside ONE hardware segment.
#
# A Z8001 address is seg:offset and its offset is 16 bits, so an object that
# starts near the top of a segment and is larger than the space left there has
# no reachable tail: the far end wraps to the bottom of the same segment and
# aliases whatever is there.  ld pads such a common up to the next segment
# boundary.  The link needs neither libc nor a compiler -- .comm alone states
# the sizes -- so this runs wherever `make check' does.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"		# $BUILD
AS="$BUILD/as-z8001"; LD="$BUILD/ld-z8001"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# straddling: 40000+40000 puts the second common across the 64K boundary
cat > "$T/big.s" <<'EOF'
	.comm	cA,40000
	.comm	cB,40000
	.comm	cC,40000
EOF
# packed: three commons that fit in one segment together
cat > "$T/small.s" <<'EOF'
	.comm	sA,100
	.comm	sB,200
	.comm	sC,64
EOF
for n in big small; do
	"$AS" -o "$T/$n.o" "$T/$n.s"
	"$LD" -L -o "$T/$n.out" "$T/$n.o"
done

python3 - "$T/big.out" "$T/small.out" <<'PY' || exit 1
import sys
SEG = 0x10000
NLSEG, HDR, SYMSZ, NCPLN = 9, 48, 22, 16
L_SYM, L_BSSD, L_GLOBAL = 7, 5, 0o20
BSSI = 2

def pdplong(b, o):		# PDP-canonical 32-bit: high word first, each LE
	return (b[o] | b[o+1] << 8) << 16 | (b[o+2] | b[o+3] << 8)

def symbols(path):
	b = open(path, 'rb').read()
	ss = [pdplong(b, 8 + 4*i) for i in range(NLSEG)]
	off = HDR + sum(s for i, s in enumerate(ss[:L_SYM]) if i not in (BSSI, L_BSSD))
	out = []
	for o in range(off, off + ss[L_SYM], SYMSZ):
		name = b[o:o+NCPLN].split(b'\0')[0].decode()
		typ = b[o+NCPLN] | b[o+NCPLN+1] << 8
		out.append((name, typ & ~L_GLOBAL, pdplong(b, o+NCPLN+2)))
	return ss, out

bad = 0
sizes = {'cA': 40000, 'cB': 40000, 'cC': 40000,
	 'sA': 100, 'sB': 200, 'sC': 64}
for path, want in ((sys.argv[1], ('cA', 'cB', 'cC')),
		   (sys.argv[2], ('sA', 'sB', 'sC'))):
	ss, syms = symbols(path)
	seen = {}
	for name, typ, addr in syms:
		if name in sizes:
			if typ != L_BSSD:
				print("  FAIL %s: type %d, not BSSD" % (name, typ))
				bad += 1
			seen[name] = addr
	for name in want:
		if name not in seen:
			print("  FAIL %s: not in the symbol table" % name)
			bad += 1
			continue
		# virtual seg<<24|offset
		off = seen[name] & 0xFFFF
		if off + sizes[name] > SEG:
			print("  FAIL %s: 0x%08x + %d straddles a segment"
			      % (name, seen[name], sizes[name]))
			bad += 1
	print("  %s: %s" % (path.rsplit('/', 1)[-1],
			    " ".join("%s=0x%08x" % (n, seen.get(n, 0)) for n in want)))

# the packed link must spend exactly the commons and nothing more
ss, syms = symbols(sys.argv[2])
if ss[L_BSSD] != 100 + 200 + 64:
	print("  FAIL packed BSSD = %d, want %d" % (ss[L_BSSD], 364))
	bad += 1
print("=== ld commons vs segment boundary: %s ==="
      % ("FAIL" if bad else "PASS"))
sys.exit(1 if bad else 0)
PY
