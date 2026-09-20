#!/bin/sh
# shlib-client.sh -- a program linked against a shared library gets a stub and
# a zeroed slot per import, and the LI_LIB/LI_IMP records exec binds them with.
#
# Also: the refusals, identical stubs across clients, and reproducible links.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"		# $BUILD
O="$BUILD/z8001"; AS="$BUILD/as-z8001"; LD="$BUILD/ld-z8001"
SLGEN="$BUILD/slgen"; VAR="${VAR:-800000000800}"; PEEP="${PEEP:-0010}"
[ -x "$SLGEN" ] || { echo "shlib-client: slgen not built"; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cc() {		# cc <name>: .c -> .o through the three passes
	"$O/cc0-z8001" $VAR "$T/$1.c" "$T/$1.z0" > /dev/null 2>&1
	"$O/cc1-z8001" $VAR "$T/$1.z0" "$T/$1.z1" > /dev/null 2>&1
	"$O/cc2-z8001" $PEEP "$T/$1.z1" "$T/$1.o" "$T/$1.scr" 0 > /dev/null 2>&1
}

# ---------------------------------------------------------------- the library
cat > "$T/toy.c" <<'EOF'
int toy_count;

int toy_add(a, b) int a, b;
{
	return a + b;
}

int toy_bump(k) int k;
{
	toy_count = toy_add(toy_count, k);
	return toy_count;
}

char *toy_name()
{
	return "toy library";
}
EOF
cc toy
printf '\t.globl\tSS\nSS = 0\n' > "$T/ss.s"; "$AS" -o "$T/ss.o" "$T/ss.s"
# toy_name_ is exported and never referenced by any client below: nothing may
# be bound for it.  toy_count_ is NOT exported, and case 5 asks for it.
printf 'toy_add_\ntoy_bump_\ntoy_name_\n' > "$T/toy.exp"
"$SLGEN" -A "$AS" -L "$LD" -T "$T" -e "$T/toy.exp" -o "$T/libtoy.1" \
	"$T/toy.o" "$T/ss.o" > /dev/null

# ----------------------------------------------------------------- the client
# Two clients importing the same two symbols.  Each names etext_/edata_/end_,
# which must come from the client's link, not the library.
for c in cli1 cli2; do
	k=1; [ "$c" = cli2 ] && k=7
	cat > "$T/$c.c" <<EOF
extern int toy_add(), toy_bump();
extern char etext[], edata[], end[];

main()
{
	return toy_add($k, 2) + toy_bump($k) + (end - etext) + edata[0];
}
EOF
	cc "$c"
done

echo "=== a client linked against libtoy.1"
"$LD" -o "$T/cli1.out" "$T/cli1.o" "$T/ss.o" "$T/libtoy.1"
python3 "$H/tests/shlib-client-check.py" "$T/cli1.out" libtoy.1 \
	toy_add_ toy_bump_ || fail=1

# Also `ld -n -i', as userland links: data moves, and so do the LI_IMP slot
# addresses.
echo "=== the same client linked -n -i, the way the userland links"
"$LD" -n -i -o "$T/cli1ni.out" "$T/cli1.o" "$T/ss.o" "$T/libtoy.1"
python3 "$H/tests/shlib-client-check.py" "$T/cli1ni.out" libtoy.1 \
	toy_add_ toy_bump_ || fail=1
cmp -s "$T/cli1.out" "$T/cli1ni.out" \
	&& { echo "  FAIL -n -i produced the same image as a plain link"; fail=1; } \
	|| echo "  PASS -n -i is a different layout, and its slots check out"

# The record carries the base name, not the path.

mkdir -p "$T/lib"; cp "$T/libtoy.1" "$T/lib/libtoy.1"
LIBPATH="$T/lib" "$LD" -o "$T/cli1p.out" "$T/cli1.o" "$T/ss.o" -ltoy
echo "=== the same client through -ltoy along LIBPATH=$T/lib"
python3 "$H/tests/shlib-client-check.py" "$T/cli1p.out" libtoy.1 \
	toy_add_ toy_bump_ || fail=1
cmp -s "$T/cli1.out" "$T/cli1p.out" \
	&& echo "  PASS -ltoy found the shared library and linked it identically" \
	|| { echo "  FAIL -ltoy produced a different image"; fail=1; }

# ------------------------------------------------------------- the properties
echo "=== two different clients, and the same client twice"
"$LD" -o "$T/cli2.out" "$T/cli2.o" "$T/ss.o" "$T/libtoy.1"
python3 "$H/tests/shlib-client-check.py" "$T/cli2.out" libtoy.1 \
	toy_add_ toy_bump_ > /dev/null || fail=1
cmp -s "$T/cli1.o" "$T/cli2.o" \
	&& { echo "  FAIL the two clients are the same program"; fail=1; } \
	|| echo "  PASS the two clients are different programs"
python3 - "$T/cli1.out" "$T/cli2.out" <<'PY' || fail=1
import sys
NCPLN, LDSLEN, LI_IMP, L_GLOBAL = 16, 22, 0o14, 0o20
def stubs(f):
    b = open(f, 'rb').read()
    tb = b[6] | b[7] << 8
    size = [((b[8+4*i] | b[9+4*i] << 8) << 16) | (b[10+4*i] | b[11+4*i] << 8)
            for i in range(9)]
    off, o = {}, tb
    for i in range(9):
        if i in (2, 5):
            continue
        off[i] = o; o += size[i]
    entry = ((b[44] | b[45] << 8) << 16) | (b[46] | b[47] << 8)
    base = ((entry >> 24) & 0xFF) << 16 | (entry & 0xFFFF)
    d, imp = {}, []
    for i in range(size[7] // LDSLEN):
        o = off[7] + i * LDSLEN
        n = b[o:o+NCPLN].rstrip(b'\0').decode()
        t = b[o+NCPLN] | b[o+NCPLN+1] << 8
        a = ((b[o+18] | b[o+19] << 8) << 16) | ((b[o+20] | b[o+21] << 8))
        if t == LI_IMP: imp.append(n)
        elif t & L_GLOBAL: d[n] = a
    out = {}
    for n in imp:
        a = ((d[n] >> 24) & 0xFF) << 16 | (d[n] & 0xFFFF)
        out[n] = b[off[0] + a - base:off[0] + a - base + 8]
    return out
a, c = stubs(sys.argv[1]), stubs(sys.argv[2])
ok = 0
for n in sorted(a):
    if a[n] == c.get(n):
        print("  PASS %s: both clients carry the stub %s" % (n, a[n].hex(" ")))
    else:
        print("  FAIL %s: %s vs %s" % (n, a[n].hex(" "), c.get(n, b"").hex(" ")))
        ok = 1
sys.exit(ok)
PY
"$LD" -o "$T/again.out" "$T/cli1.o" "$T/ss.o" "$T/libtoy.1"
cmp -s "$T/cli1.out" "$T/again.out" \
	&& echo "  PASS linking the client twice gives the same bytes" \
	|| { echo "  FAIL the link is not reproducible"; fail=1; }

# -------------------------------------------------------------- the refusals
say() {		# say <what> <logfile> <grep pattern>
	if grep -q "$3" "$2"; then
		echo "  PASS refused: $(grep -m1 "$3" "$2")"
	else
		echo "  FAIL $1: wrong message"; sed -n '1,3p' "$2"; fail=1
	fi
}
echo "=== the refusals"
if "$LD" -s -o "$T/strip.out" "$T/cli1.o" "$T/ss.o" "$T/libtoy.1" \
		> "$T/strip.log" 2>&1; then
	echo "  FAIL ld -s stripped a client with imports"; fail=1
else
	say "-s" "$T/strip.log" "cannot strip"
fi

cat > "$T/cli3.c" <<'EOF'
extern int toy_count;
main() { toy_count = 3; return toy_count; }
EOF
cc cli3
if "$LD" -o "$T/noexp.out" "$T/cli3.o" "$T/ss.o" "$T/libtoy.1" \
		> "$T/noexp.log" 2>&1; then
	echo "  FAIL ld bound a symbol the library does not export"; fail=1
else
	say "unexported" "$T/noexp.log" "does not export it"
fi

python3 - "$T/libtoy.1" "$T/badmagic.1" <<'PY'
import sys
b = bytearray(open(sys.argv[1], 'rb').read())
b[(b[6] | b[7] << 8)] ^= 0xFF          # first byte of sl_magic, at l_tbase
open(sys.argv[2], 'wb').write(bytes(b))
PY
if "$LD" -o "$T/bad.out" "$T/cli1.o" "$T/ss.o" "$T/badmagic.1" \
		> "$T/bad.log" 2>&1; then
	echo "  FAIL ld linked a library with a bad export table"; fail=1
else
	say "bad magic" "$T/bad.log" "export table magic"
fi

if "$LD" -r -o "$T/rel.out" "$T/cli1.o" "$T/ss.o" "$T/libtoy.1" \
		> "$T/rel.log" 2>&1; then
	echo "  FAIL ld bound imports into a relocatable link"; fail=1
else
	say "-r" "$T/rel.log" "relocatable link"
fi

# --------------------------------------------- and nothing changes without one
echo "=== a link that names no library"
"$LD" -o "$T/plain.out" "$T/cli3.o" "$T/ss.o" -d > /dev/null 2>&1 || true
python3 - "$T/plain.out" <<'PY' || fail=1
import sys
b = open(sys.argv[1], 'rb').read()
flag = b[2] | b[3] << 8
LDSLEN = 22
tb = b[6] | b[7] << 8
size = [((b[8+4*i] | b[9+4*i] << 8) << 16) | (b[10+4*i] | b[11+4*i] << 8)
        for i in range(9)]
o = tb
for i in range(9):
    if i in (2, 5):
        continue
    if i == 7:
        break
    o += size[i]
t = [b[o+i*LDSLEN+16] | b[o+i*LDSLEN+17] << 8 for i in range(size[7]//LDSLEN)]
bad = 0
if flag & 0o40:
    print("  FAIL LF_SLREF is set on a link that names no library"); bad = 1
else:
    print("  PASS LF_SLREF is clear")
if [x for x in t if x in (0o13, 0o14)]:
    print("  FAIL import records in a link that names no library"); bad = 1
else:
    print("  PASS no LI_LIB/LI_IMP records")
sys.exit(bad)
PY

[ $fail = 0 ] && echo "shlib-client: ld binds clients as the format says"
exit $fail
