#!/bin/sh
# shlib-abi.sh -- src/libc/libc.1.exp is libc.1's ABI: additions only.
#
# exec binds imports by name, so a dropped name silently breaks installed
# binaries.  Check 1 compares the built export table with the list, by name
# and kind (a function import is a stub, a data import a slot); check 2
# compares the list with its committed predecessor.  Order is irrelevant.
#
# Needs $BUILD/libc1/libc.1 and $BUILD/slgen.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"		# $BUILD
LIB="$BUILD/libc1/libc.1"
EXP="$H/src/libc/libc.1.exp"
[ -f "$LIB" ] || { echo "shlib-abi: $LIB not built"; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
say() { echo "  $1 $2"; [ "$1" = PASS ] || fail=1; }

# The export table: at offset 0 of the shared segment, entries of
# {char se_name[16]; u16 se_flags; u16 se_off}, big-endian.
cat > "$T/exports.py" <<'PY'
import sys
b = open(sys.argv[1], 'rb').read()
sh = lambda o: b[o] | b[o+1] << 8
tb = sh(6)					# l_tbase: the shared segment
be = lambda o: (b[o] << 8) | b[o+1]
magic, vers, nexp, expoff = (be(tb+2*i) for i in range(4))
if magic != 0x534C:
    raise SystemExit("not a shared library: magic 0x%04x" % magic)
KIND = {0: "func", 1: "data", 3: "shrd"}
names, rows = [], []
for i in range(nexp):
    e = tb + expoff + 20*i
    n = b[e:e+16].split(b'\0')[0].decode('latin1')
    f = be(e+16)
    if f not in KIND:
        raise SystemExit("export %s has flags 0x%04x, which shlib.h does not define" % (n, f))
    names.append(n)
    rows.append("%s %s" % (n, KIND[f]))
if names != sorted(names):
    raise SystemExit("the export table is not sorted -- the kernel binary-searches it")
sys.stdout.write("".join(r + "\n" for r in rows))
PY
# One `name kind' line per export; bare names get `func'.
list_of() { sed 's/#.*//' "$1" |
	awk '{ if (NF == 0) next; print $1, (NF > 1 ? $2 : "func") }' | sort; }

echo "=== 1 the built library exports exactly the names libc.1.exp gives, with its kinds"
python3 "$T/exports.py" "$LIB" | sort > "$T/table"
list_of "$EXP" > "$T/list"
if cmp -s "$T/table" "$T/list"; then
	say PASS "$(wc -l < "$T/list") symbols ($(awk '$2!="func"' "$T/list" | wc -l) of them data), and the table is sorted"
else
	comm -23 "$T/list" "$T/table" | sed 's/^/    promised, not exported: /'
	comm -13 "$T/list" "$T/table" | sed 's/^/    exported, not promised: /'
	say FAIL "the export table and the export list disagree"
fi

echo "=== 2 D7: the list has lost nothing since it was committed"
if git -C "$H" rev-parse --verify HEAD >/dev/null 2>&1 &&
   git -C "$H" cat-file -e "HEAD:src/libc/libc.1.exp" 2>/dev/null; then
	git -C "$H" show HEAD:src/libc/libc.1.exp > "$T/head.exp"
	list_of "$T/head.exp" > "$T/old"
	gone=$(comm -23 "$T/old" "$T/list" | tr '\n' ' ')
	if [ -z "$gone" ]; then
		added=$(comm -13 "$T/old" "$T/list" | wc -l)
		say PASS "nothing removed since HEAD, $added added"
	else
		echo "    removed since HEAD: $gone"
		say FAIL "a removal needs a major bump -- libc.2, a new file name (D7)"
	fi
else
	say PASS "no committed predecessor here; ONLY check 1 ran"
fi

# A toy library, for what needs no whole libc.
cat > "$T/toy.s" <<'EOF'
	.globl	SS
	.globl	aa_
	.globl	bb_
	.globl	cc_
	.globl	dd_
	.globl	ee_
SS = 0
aa_:
	call	bb_
	ret
bb_:
	call	cc_
	ret
cc_:
	ret
	.shrd
ee_:
	.word	0x1234
	.prvd
dd_:
	.word	0x5678
EOF
"$BUILD/as-z8001" -o "$T/toy.o" "$T/toy.s"

echo "=== 3 reordering the list changes nothing (binding is by name)"
printf 'aa_\nbb_\ncc_\ndd_ data\nee_ shrd\n' > "$T/a.exp"
printf 'ee_ shrd\ncc_\ndd_ data\naa_\nbb_\n' > "$T/b.exp"
for o in a b; do
	"$BUILD/slgen" -A "$BUILD/as-z8001" -L "$BUILD/ld-z8001" -T "$T" \
		-e "$T/$o.exp" -o "$T/$o.1" "$T/toy.o" > "$T/$o.log" 2>&1 ||
		{ cat "$T/$o.log"; say FAIL "slgen refused the toy"; }
done
if [ -f "$T/a.1" ] && [ -f "$T/b.1" ] && cmp -s "$T/a.1" "$T/b.1"; then
	say PASS "two orders of one list give byte-identical libraries"
else
	say FAIL "the order of the export list reached the artifact"
fi

echo "=== 4 refusals, each seen to refuse"
# A name dropped from the list: check 1 must name it.
grep -v '^printf_ ' "$T/list" > "$T/cut"
if comm -13 "$T/cut" "$T/table" | grep -q '^printf_ '; then
	say PASS "a deleted line is caught: printf_ exported, not promised"
else
	say FAIL "a deleted line went unnoticed"
fi
# The same, seen by check 2.
if comm -23 "$T/list" "$T/cut" | grep -q '^printf_ '; then
	say PASS "and caught again as a removal since the committed list"
else
	say FAIL "the append-only comparison missed a removal"
fi
# A listed name the objects do not define: slgen refuses.
printf 'aa_\nbb_\ncc_\ndd_ data\nee_ shrd\nno_such_symbol_\n' > "$T/bogus.exp"
if "$BUILD/slgen" -A "$BUILD/as-z8001" -L "$BUILD/ld-z8001" -T "$T" \
	-e "$T/bogus.exp" -o "$T/bogus.1" "$T/toy.o" > "$T/bogus.log" 2>&1; then
	say FAIL "slgen accepted an export the library does not define"
else
	say PASS "slgen refuses it: $(grep -m1 "is not defined" "$T/bogus.log")"
fi
# Wrong kinds, which only slgen can see.

kindbad() {	# kindbad <list text> <what it got wrong>
	printf '%b' "$1" > "$T/k.exp"
	if "$BUILD/slgen" -A "$BUILD/as-z8001" -L "$BUILD/ld-z8001" -T "$T" \
		-e "$T/k.exp" -o "$T/k.1" "$T/toy.o" > "$T/k.log" 2>&1; then
		say FAIL "slgen accepted a list that $2"
	else
		say PASS "slgen refuses it: $(grep -m1 'the list calls it' "$T/k.log")"
	fi
}
kindbad 'aa_\nbb_\ncc_\ndd_\nee_ shrd\n'      "calls an object a function"
kindbad 'aa_\nbb_\ncc_\ndd_ data\nee_ data\n' "calls a shared table private"
kindbad 'aa_\nbb_\ncc_ data\ndd_ data\nee_ shrd\n' "calls a function an object"

[ "$fail" = 0 ] && echo "shlib-abi: ALL PASS" || echo "shlib-abi: FAILED"
exit $fail
