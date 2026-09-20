#!/bin/sh
# fixed-mode.sh -- fixed-address shared libraries: `slgen -F base' and `ld -F',
# built, run, read back, and refused across styles.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"		# $BUILD
O="$BUILD/z8001"; AS="$BUILD/as-z8001"; LD="$BUILD/ld-z8001"
SLGEN="$BUILD/slgen"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR="${VAR:-800000000800}"; VARP="${VARP:-800000000808}"; PEEP="${PEEP:-0010}"
[ -x "$SLGEN" ] || { echo "fixed-mode: slgen not built"; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  PASS $1"; }
bad() { echo "  FAIL $1"; fail=1; }

cc() {		# cc <name> [variant]
	v="${2:-$VAR}"
	"$O/cc0-z8001" $v "$T/$1.c" "$T/$1.z0" > /dev/null 2>&1
	"$O/cc1-z8001" $v "$T/$1.z0" "$T/$1.z1" > /dev/null 2>&1
	"$O/cc2-z8001" $PEEP "$T/$1.z1" "$T/$1.o" "$T/$1.scr" 0 > /dev/null 2>&1
}

# ---------------------------------------------------------------- the library
# Only code globals are exported, so static toy_helper is not.  toy_end names
# `end', which must stay the client's.
cat > "$T/toy.c" <<'EOF'
extern char end[];
int toy_count;

static int toy_helper(a, b) int a, b;
{
	return a + b;
}

int toy_add(a, b) int a, b;
{
	return toy_helper(a, b);
}

int toy_bump(k) int k;
{
	toy_count = toy_add(toy_count, k);
	return toy_count;
}

char *toy_end()
{
	return end;
}
EOF
cc toy
printf '\t.globl\tSS\nSS = 0\n' > "$T/ss.s"; "$AS" -o "$T/ss.o" "$T/ss.s"

echo "=== a fixed-address library at 0x01000000"
"$SLGEN" -A "$AS" -L "$LD" -T "$T" -F 0x01000000 -o "$T/libtoy.1" \
	"$T/toy.o" "$T/ss.o" > /dev/null
python3 "$H/tests/fixed-check.py" "$T/libtoy.1" 0x01000000 \
	toy_add_ toy_bump_ toy_end_ || fail=1

# Byte 50 is inside the first jump entry; corrupting it must be caught.
echo "=== the same library with one jump entry corrupted"
cp "$T/libtoy.1" "$T/broken.1"
printf '\377' | dd of="$T/broken.1" bs=1 seek=51 count=1 conv=notrunc 2>/dev/null
if python3 "$H/tests/fixed-check.py" "$T/broken.1" 0x01000000 \
		toy_add_ toy_bump_ toy_end_ > "$T/err" 2>&1; then
	bad "a corrupted jump entry passed the structural check"
else
	grep -q "is \`jp'" "$T/err" \
		&& ok "refused: $(grep -m1 FAIL "$T/err" | sed 's/^ *FAIL //')" \
		|| bad "refused, but not for the reason expected"
fi

# ------------------------------------------------------------------- a client
cat > "$T/cli.c" <<'EOF'
extern int toy_add(), toy_bump();
extern int toy_count;

int f()
{
	return toy_add(1, 2) + toy_bump(7) + toy_count;
}
EOF

# Segments 5 and 6, where fixed-merge.py puts the library.
"$SLGEN" -A "$AS" -L "$LD" -T "$T" -F 0x05000000 -o "$T/lib5.1" \
	"$T/toy.o" "$T/ss.o" > /dev/null

run() {		# run <client object> -> prints R1
	"$LD" -F -R 0x03000000 -e f_ -o "$T/cli.out" "$1" "$T/ss.o" "$T/lib5.1"
	python3 "$H/tests/fixed-merge.py" "$T/cli.out" "$T/lib5.1" "$T/run.out"
	"$N2" -runobjint "$T/run.out" 2>/dev/null \
		| grep -oE 'R1 = -?[0-9]+' | grep -oE '\-?[0-9]+$'
}

echo "=== the client runs against the library, at the addresses it was linked for"
cc cli
r=$(run "$T/cli.o")
[ "$r" = 17 ] && ok "toy_add(1,2) + toy_bump(7) + toy_count = 17" \
	|| bad "the run returned [$r], want 17"

# The client CALLs the jump table directly and names nothing of the library.
echo "=== what the client does NOT carry"
python3 - "$T/cli.out" <<'PY' || fail=1
import sys
LI_LIB, LI_IMP, LDSLEN, NCPLN, LF_SLREF = 0o13, 0o14, 22, 16, 0o40
b = open(sys.argv[1], 'rb').read()
rdw = lambda o: b[o] | b[o+1] << 8
ss = [rdw(8+4*i) << 16 | rdw(8+4*i+2) for i in range(9)]
o = 48
for i in range(9):
    if i in (2, 5):
        continue
    if i == 7:
        break
    o += ss[i]
bad = [p for p in range(o, o+ss[7], LDSLEN) if rdw(p+NCPLN) in (LI_LIB, LI_IMP)]
print("  %s no LI_LIB/LI_IMP record (%d found)"
      % ("FAIL" if bad else "PASS", len(bad)))
print("  %s LF_SLREF set, as the loader expects"
      % ("PASS" if rdw(2) & LF_SLREF else "FAIL"))
sys.exit(1 if bad or not rdw(2) & LF_SLREF else 0)
PY

echo "=== the same client compiled -VPIC (the dynamic style's flag)"
cc cli "$VARP"
r=$(run "$T/cli.o")
[ "$r" = 17 ] && ok "the indirection is filled in at link time: still 17" \
	|| bad "the -VPIC run returned [$r], want 17"

# A library at a base the client was not linked against.
echo "=== a library built for a different base"
cc cli
"$SLGEN" -A "$AS" -L "$LD" -T "$T" -F 0x07000000 -o "$T/lib7.1" \
	"$T/toy.o" "$T/ss.o" > /dev/null
"$LD" -F -R 0x03000000 -e f_ -o "$T/cli7.out" "$T/cli.o" "$T/ss.o" "$T/lib7.1"
python3 "$H/tests/fixed-merge.py" "$T/cli7.out" "$T/lib7.1" "$T/run7.out"
r=$("$N2" -runobjint "$T/run7.out" 2>/dev/null \
	| grep -oE 'R1 = -?[0-9]+' | grep -oE '\-?[0-9]+$')
[ "$r" = 17 ] && bad "a library loaded away from its link base still returned 17" \
	|| ok "it does not return 17 (got [$r])"

echo "=== relinking is reproducible"
"$LD" -F -R 0x03000000 -e f_ -o "$T/clia.out" "$T/cli.o" "$T/ss.o" "$T/lib5.1"
"$LD" -F -R 0x03000000 -e f_ -o "$T/clib.out" "$T/cli.o" "$T/ss.o" "$T/lib5.1"
cmp -s "$T/clia.out" "$T/clib.out" && ok "the same link twice, the same bytes" \
	|| bad "two links of the same client differ"
"$SLGEN" -A "$AS" -L "$LD" -T "$T" -F 0x05000000 -o "$T/lib5b.1" \
	"$T/toy.o" "$T/ss.o" > /dev/null
cmp -s "$T/lib5.1" "$T/lib5b.1" && ok "the same library twice, the same bytes" \
	|| bad "two builds of the same library differ"

# ------------------------------------------------------------- the refusals
echo "=== the refusals"
printf 'toy_add_\n' > "$T/toy.exp"
if "$SLGEN" -A "$AS" -L "$LD" -T "$T" -F 0x01000000 -e "$T/toy.exp" \
		-o "$T/bad.1" "$T/toy.o" "$T/ss.o" > "$T/err" 2>&1; then
	bad "slgen took both styles at once"
else
	grep -q 'the two styles' "$T/err" && ok "$(sed -n 1p "$T/err")" \
		|| bad "refused, but not for the reason expected"
fi
if "$SLGEN" -A "$AS" -L "$LD" -T "$T" -F 0x01000200 \
		-o "$T/bad.1" "$T/toy.o" "$T/ss.o" > "$T/err" 2>&1; then
	bad "slgen took a base that is not a segment boundary"
else
	grep -q 'not the base of a hardware segment' "$T/err" \
		&& ok "$(sed -n 1p "$T/err")" \
		|| bad "refused, but not for the reason expected"
fi

# The two styles, each offered to the other's ld mode.
printf 'toy_add_\ntoy_bump_\ntoy_end_\n' > "$T/dyn.exp"
"$SLGEN" -A "$AS" -L "$LD" -T "$T" -e "$T/dyn.exp" -o "$T/libdyn.1" \
	"$T/toy.o" "$T/ss.o" > /dev/null
if "$LD" -F -n -i -o "$T/bad.out" "$T/cli.o" "$T/ss.o" "$T/libdyn.1" \
		> "$T/err" 2>&1; then
	bad "a dynamic library was linked as a fixed-address one"
else
	grep -q 'link it without -F' "$T/err" && ok "$(sed -n 1p "$T/err")" \
		|| bad "refused, but not for the reason expected"
fi
if "$LD" -n -i -o "$T/bad.out" "$T/cli.o" "$T/ss.o" "$T/lib5.1" \
		> "$T/err" 2>&1; then
	bad "a fixed-address library was linked as a dynamic one"
else
	grep -q 'links with -F' "$T/err" && ok "$(sed -n 1p "$T/err")" \
		|| bad "refused, but not for the reason expected"
fi

# A dynamic library's data needs -VPIC; ld names the flag.
cat > "$T/dcli.c" <<'EOF'
extern int toy_count;

int f()
{
	return toy_count;
}
EOF
printf 'toy_add_\ntoy_bump_\ntoy_end_\ntoy_count_ data\n' > "$T/dyn2.exp"
"$SLGEN" -A "$AS" -L "$LD" -T "$T" -e "$T/dyn2.exp" -o "$T/libdyn2.1" \
	"$T/toy.o" "$T/ss.o" > /dev/null
cc dcli "$VARP"
"$LD" -n -i -o "$T/dcli.out" "$T/dcli.o" "$T/ss.o" "$T/libdyn2.1"
ok "the -VPIC client of a dynamic library links"
cc dcli "$VAR"
if "$LD" -n -i -o "$T/bad.out" "$T/dcli.o" "$T/ss.o" "$T/libdyn2.1" \
		> "$T/err" 2>&1; then
	bad "a client without -VPIC read a dynamic library's data"
else
	grep -q '\-VPIC' "$T/err" && ok "$(sed -n 1p "$T/err")" \
		|| bad "refused, but the message does not name -VPIC"
fi
# ... which the fixed library does not.
"$LD" -F -R 0x03000000 -e f_ -o "$T/dcli5.out" "$T/dcli.o" "$T/ss.o" "$T/lib5.1"
ok "the same client, no -VPIC, links against the fixed-address library"

# ------------------------------------------------------ the loader's contract
# Shared half at segment L_SLSEG0+slot, private half at 1+slot, attached by the
# per-slot flag bit.  `slgen -F base -P priv' places the halves apart; `ld -F'
# sets the bit.
echo "=== the fixed library slot 0 wants: shared at 0x34, private at 0x01"
"$SLGEN" -A "$AS" -L "$LD" -T "$T" -F 0x34000000 -P 0x01000000 \
	-o "$T/slot0.1" "$T/toy.o" "$T/ss.o" > /dev/null || bad "slgen -P"
segof() {	# segof <l.out> <symbol> -- the hardware segment it was linked at
	python3 - "$T/slot0.1" "$1" <<'EOF'
import struct, sys
d = open(sys.argv[1], 'rb').read()
canl = lambda w: (lambda a: a[0] << 16 | a[1])(struct.unpack('<HH', w))
sz = [canl(d[8 + 4 * i:12 + 4 * i]) for i in range(9)]
off = 48 + sz[0] + sz[1] + sz[3] + sz[4]
want = sys.argv[2].encode()
for i in range(sz[7] // 22):
	e = d[off + 22 * i:off + 22 * (i + 1)]
	if e[:16].split(b'\0')[0] == want:
		print('0x%02x' % (canl(e[18:22]) >> 24)); break
else:
	print('none')
EOF
}
[ "$(segof toy_add_)" = 0x34 ] \
	&& ok "the jump table is at the segment the loader maps the text at" \
	|| bad "the jump table is at segment $(segof toy_add_), not 0x34"
[ "$(segof toy_count_)" = 0x01 ] \
	&& ok "the private half is at the segment the loader attaches it at" \
	|| bad "the private half is at segment $(segof toy_count_), not 0x01"

echo "=== a client of it names the slot"
lflag() {	# lflag <l.out> -- l_flag, octal
	python3 -c 'import struct,sys;print("%o"%struct.unpack("<H",open(sys.argv[1],"rb").read(4)[2:4])[0])' "$1"
}
"$LD" -F -o "$T/slot0.out" "$T/cli.o" "$T/ss.o" "$T/slot0.1" > "$T/err" 2>&1
f=$(lflag "$T/slot0.out")
case " $f " in
*" 264 "*)	ok "l_flag 0$f: LF_SLREF and LF_SLREF0, the bit the loader attaches on";;
*)		bad "l_flag 0$f: the per-slot bit is not set";;
esac
# A library outside the slot window gets no bit, and the link says so.
"$SLGEN" -A "$AS" -L "$LD" -T "$T" -F 0x05000000 -P 0x01000000 \
	-o "$T/noslot.1" "$T/toy.o" "$T/ss.o" > /dev/null
"$LD" -F -w -o "$T/noslot.out" "$T/cli.o" "$T/ss.o" "$T/noslot.1" \
	> "$T/err" 2>&1
case " $(lflag "$T/noslot.out") " in
*" 64 "*)	grep -q 'outside the 2 slots' "$T/err" \
		&& ok "outside the window: no slot bit, and -w says which segment" \
		|| bad "no slot bit, but -w did not say why";;
*)		bad "a library outside the slot window was given a slot bit";;
esac

# Flags refused where they mean nothing.

if "$SLGEN" -A "$AS" -L "$LD" -T "$T" -e "$T/toy.exp" -P 0x01000000 \
		-o "$T/bad.1" "$T/toy.o" "$T/ss.o" > "$T/err" 2>&1; then
	bad "slgen took -P without -F"
else
	grep -q 'use it with -F' "$T/err" && ok "$(sed -n 1p "$T/err")" \
		|| bad "refused, but not for the reason expected"
fi
if "$SLGEN" -A "$AS" -L "$LD" -T "$T" -F 0x34000000 -P 0x34000000 \
		-o "$T/bad.1" "$T/toy.o" "$T/ss.o" > "$T/err" 2>&1; then
	bad "slgen took a private base equal to the shared one"
else
	grep -q "the shared half's own base" "$T/err" && ok "$(sed -n 1p "$T/err")" \
		|| bad "refused, but not for the reason expected"
fi
if "$LD" -P 0x01000000 -o "$T/bad.out" "$T/cli.o" "$T/ss.o" \
		> "$T/err" 2>&1; then
	bad "ld placed a private half in an image that has none of its own"
else
	grep -q 'use it with -n' "$T/err" && ok "$(sed -n 1p "$T/err")" \
		|| bad "refused, but not for the reason expected"
fi

[ $fail -eq 0 ] && echo "fixed-mode: PASS" || echo "fixed-mode: FAIL"
exit $fail
