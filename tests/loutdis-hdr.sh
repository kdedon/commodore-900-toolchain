#!/bin/sh
# loutdis-hdr.sh -- loutdis reads the header in the order l_magic gives, so
# objects and images whose sections fit the file length under another field
# order are not misread, and it disassembles code in both SHRI and PRVI.
#
#   tie.o: no symbols, SHRI 0x0204 and PRVD 0x0402 bytes, so byte-swapped
#     sizes sum to the same file length;
#   tie.x: tie.o linked and stripped;
#   ln.o, ln.r: long names (as -N, ld -r -N); the string table after the
#     sections leaves big-endian sizes nearer the file length;
#   sym.o, sym.x: symbols, unstripped, -syms and -fn;
#   two.o: code in SHRI and PRVI.
H="$(cd "$(dirname "$0")/.." && pwd)"
B="${C900_TC_BUILD:-$H/host/build}"
AS="$B/as-z8001"; LD="$B/ld-z8001"; DIS="$B/tools/loutdis"
for t in "$AS" "$LD" "$DIS"; do
	[ -x "$t" ] || { echo "loutdis-hdr: $t not built"; exit 2; }
done
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T"
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then echo "  PASS $1"; pass=$((pass+1));
	else echo "  FAIL $1: got [$2] want [$3]"; fail=$((fail+1)); fi; }
nops() { i=0; while [ $i -lt $1 ]; do printf '\tnop\n'; i=$((i+1)); done; }
insns() { "$DIS" "$1" | sed -n '1s/.*text=\([A-Z+]*\) \([0-9]*\) insns.*/\1 \2/p'; }
enc() { "$DIS" "$1" -hdr | sed -n 's/^field encoding: //p'; }
size() { "$DIS" "$1" -hdr | sed -n "s/^  l_ssize\[$2 *\] = //p"; }

{ printf '\t.shri\n'; nops 258; printf '\t.prvd\n\t.blkb\t1026\n'; } > tie.s
"$AS" -o tie.o tie.s && "$LD" -s -o tie.x tie.o || { echo "loutdis-hdr: build FAIL"; exit 1; }
for f in tie.o tie.x; do
	check "$f encoding" "$(enc $f)" "16-bit=LE 32-bit=PDPLE"
	check "$f SHRI size" "$(size $f SHRI)" 516
	check "$f PRVD size" "$(size $f PRVD)" 1026
	check "$f insns" "$(insns $f)" "SHRI 258"
done

{
	printf '\t.shri\n'
	k=10; while [ $k -lt 45 ]; do
		printf '\t.globl\ts%d_%0100d\ns%d_%0100d:\n' $k 0 $k 0; k=$((k+1))
	done
	nops 1
	printf '\t.prvd\n\t.blkb\t2\n'
} > ln.s
"$AS" -N -o ln.o ln.s && "$LD" -r -N -o ln.r ln.o || { echo "loutdis-hdr: build FAIL"; exit 1; }
for f in ln.o ln.r; do
	check "$f encoding" "$(enc $f)" "16-bit=LE 32-bit=PDPLE"
	check "$f SYM size" "$(size $f SYM)" 770
	check "$f insns" "$(insns $f)" "SHRI 1"
	check "$f long names" "$("$DIS" $f -syms | grep -c ' s[0-9]*_0\{100\}$')" 35
done

{ printf '\t.shri\n\t.globl\tf_, g_\nf_:\n'; nops 5; printf 'g_:\n'; nops 2; printf '\tret\n'; } > sym.s
"$AS" -o sym.o sym.s && "$LD" -o sym.x sym.o || { echo "loutdis-hdr: build FAIL"; exit 1; }
for f in sym.o sym.x; do
	check "$f insns" "$(insns $f)" "SHRI 8"
	check "$f -syms" "$("$DIS" $f -syms | grep -c ' SHRI   [fg]_$')" 2
	check "$f -fn g_" "$("$DIS" $f -fn g_ | awk 'NR > 1 { printf "%s ", $2 }')" "NOP NOP RET "
done

{ printf '\t.shri\n'; nops 3; printf '\t.prvi\n\t.globl\th_\nh_:\n'; nops 1; printf '\tret\n'; } > two.s
"$AS" -o two.o two.s || { echo "loutdis-hdr: build FAIL"; exit 1; }
check "two.o insns" "$(insns two.o)" "SHRI+PRVI 5"
check "two.o -fn h_" "$("$DIS" two.o -fn h_ | awk 'NR > 1 { printf "%s ", $2 }')" "NOP RET "

echo "=== loutdis-hdr: $pass passed, $fail failed ==="
[ "$fail" = 0 ]
