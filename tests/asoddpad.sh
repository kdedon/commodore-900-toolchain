#!/bin/sh
# asoddpad.sh -- as rounds each section to even length in the header and
# the file holds every byte of it, so ld reads the next module's data in
# place.  Each section ends odd with .blkb, .byte and .ascii, with no
# symbols, with symbols and with a long name; then odd-ended objects are
# linked ahead of others.
H="$(cd "$(dirname "$0")/.." && pwd)"
B="${C900_TC_BUILD:-$H/host/build}"
AS="$B/as-z8001"; LD="$B/ld-z8001"; DIS="$B/tools/loutdis"
for t in "$AS" "$LD" "$DIS"; do
	[ -x "$t" ] || { echo "asoddpad: $t not built"; exit 2; }
done
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T"
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then echo "  PASS $1"; pass=$((pass+1));
	else echo "  FAIL $1: got [$2] want [$3]"; fail=$((fail+1)); fi; }
size() { "$DIS" "$1" -hdr | sed -n "s/^  l_ssize\[$2 *\] = //p"; }
byte() { od -An -tu1 -j "$2" -N1 "$1" | tr -d ' '; }
# header + SHRI PRVI SHRD PRVD DEBUG SYM REL + the long-name table
want() {
	n=48
	for s in SHRI PRVI SHRD PRVD DEBUG SYM REL; do n=$((n + $(size $1 $s))); done
	flag=$("$DIS" "$1" -hdr | sed -n 's/^flag=0*\([0-7]*\) .*/\1/p')
	if [ $(( 0${flag:-0} & 02000 )) != 0 ]; then
		set -- $(od -An -tu1 -j $n -N4 "$1")
		n=$((n + ($2<<24) + ($1<<16) + ($4<<8) + $3))
	fi
	echo $n
}
long=l_$(printf '%060d' 0)

for sec in shri prvi shrd prvd; do
	S=$(echo $sec | tr a-z A-Z)
	for tail in 'blkb	3' 'byte	1,2,3' 'ascii	"abc"'; do
		for sy in none sym lname; do
			f=$sec-${tail%%	*}-$sy
			{
				case $sy in
				sym)	printf '\t.shri\n\t.globl\tg_\ng_:\n' ;;
				lname)	printf '\t.shri\n\t.globl\t%s\n%s:\n' $long $long ;;
				esac
				printf '\t.%s\n\t.%s\n' $sec "$tail"
			} > $f.s
			fl=; [ $sy = lname ] && fl=-N
			"$AS" $fl -o $f.o $f.s || { echo "asoddpad: as $f FAIL"; exit 1; }
			check "$f $S size" "$(size $f.o $S)" 4
			check "$f length" "$(wc -c < $f.o | tr -d ' ')" "$(want $f.o)"
		done
	done
done

# odd .blkb inside a section, then data
printf '\t.prvd\n\t.blkb\t1\n\t.byte\t5,6\n' > mid.s
"$AS" -o mid.o mid.s || { echo "asoddpad: as mid FAIL"; exit 1; }
check "mid length" "$(wc -c < mid.o | tr -d ' ')" "$(want mid.o)"
check "mid data" "$(byte mid.o 48) $(byte mid.o 49) $(byte mid.o 50)" "0 5 6"

# an odd last section ahead of the next module's code and data
printf '\t.shri\n\t.byte\t1\n' > a.s
printf '\t.shri\n\t.globl\tf_\nf_:\n\tnop\n\tret\n\t.prvd\n\t.byte\t9\n' > b.s
printf '\t.prvd\n\t.ascii\t"abc"\n' > c.s
for f in a b c; do "$AS" -o $f.o $f.s || { echo "asoddpad: as $f FAIL"; exit 1; }; done
"$LD" -o x a.o b.o && "$LD" -r -o r c.o b.o || { echo "asoddpad: ld FAIL"; exit 1; }
check "x length" "$(wc -c < x | tr -d ' ')" "$(want x)"
check "x f_" "$(od -An -tx1 -j $((48 + 2)) -N4 x | tr -d ' ')" 8d079e08
check "r length" "$(wc -c < r | tr -d ' ')" "$(want r)"
check "r -fn f_" "$("$DIS" r -fn f_ | awk 'NR > 1 { printf "%s ", $2 }')" "NOP RET "
d=$((48 + $(size r SHRI) + $(size r PRVI) + $(size r SHRD)))
check "r PRVD" "$(byte r $d) $(byte r $((d+3))) $(byte r $((d+4)))" "97 0 9"

echo "=== asoddpad: $pass passed, $fail failed ==="
[ "$fail" = 0 ]
