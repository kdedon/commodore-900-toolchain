#!/bin/sh
# lname.sh -- long external names (LF_LNAME), opted into with cc2's VLNAME
# variant (ccz -VLNAME), as -N and ld -N.
#
#   names that differ only after the 16th character are distinct symbols,
#   from cc2 and from as; short- and long-name objects link together, from
#   the command line, from an archive scanned member by member and from one
#   with a ranlib index (the native ar, run under the emulator); ld -r keeps
#   the full names; loutid, loutdis and nlist() read both forms; an object
#   with no long name is the same bytes with or without the opt-in; a name of
#   127 characters is kept and a longer one is cut there with a warning; ld
#   without -N and slgen refuse an LF_LNAME object.
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
O="$BUILD/z8001"; AS="$BUILD/as-z8001"; LD="$BUILD/ld-z8001"
LOUTID="$BUILD/tools/loutid"; LOUTDIS="$BUILD/tools/loutdis"
N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
C2=0010				# cc2: VPEEP
C2L=001000000010		# cc2: VPEEP + VLNAME
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T"
pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2] want [$3]"; fi; }

cc() {	# name variant source
	printf '%s\n' "$3" > "$1.c"
	"$O/cc0-z8001" $VAR "$1.c" "$1.z0" &&
	"$O/cc1-z8001" $VAR "$1.z0" "$1.z1" &&
	"$O/cc2-z8001" "$2" "$1.z1" "$1.o" "$1.scr" 0 2>"$1.err"
}
r1() { "$N2" -runobjint "$1" 2>/dev/null | grep -oE 'R1 = -?[0-9]+' | grep -oE '\-?[0-9]+$'; }
flags() { "$LOUTID" "$1" | sed 's/.*\[//; s/\].*//'; }
syms() { "$LOUTID" -s "$1" | sed -n 's/^  //p' | sort; }

printf '\t.globl\tSS\nSS = 0\n' > ss.s; "$AS" -o ss.o ss.s

# --- distinct names past the 16th character, from cc2 ---------------------
cc a $C2L 'int a_very_long_name_one(); int a_very_long_name_two();
int f(){ return a_very_long_name_one()*10 + a_very_long_name_two(); }'
cc b $C2L 'int a_very_long_name_one(){ return 4; } int a_very_long_name_two(){ return 2; }'
check "cc2 -VLNAME: no truncation warning" "$(cat a.err b.err)" ""
check "cc2 -VLNAME: LF_LNAME object" "$(flags a.o)" "32|relax|lname"
"$LD" -N -R 0x200 -e f_ -o ab a.o b.o ss.o && check "two long names, one prefix: distinct" "$(r1 ab)" 42 \
	|| bad "two long names: link"
check "linked image names both in full" "$(syms ab | grep -c 'a_very_long_name_[ot][nw][eo]_$')" 2

# --- the default is today's: cut to 16, warned, one symbol -----------------
cc a0 $C2 'int a_very_long_name_one(); int a_very_long_name_two();
int f(){ return a_very_long_name_one()*10 + a_very_long_name_two(); }'
check "default: plain object" "$(flags a0.o)" "32|relax"
check "default: truncation warned" "$(grep -c 'is longer than 16' a0.err)" 2

# --- the opt-in changes nothing for an object without a long name ----------
cc s0 $C2 'int short_name(){ return 1; } int abcdefghijklmno(){ return 2; }'
cc s1 $C2L 'int short_name(){ return 1; } int abcdefghijklmno(){ return 2; }'
cmp -s s0.o s1.o && ok "cc2: 16-character names, same bytes under VLNAME" \
	|| bad "cc2: VLNAME changed an object without a long name"
cat > s.s <<'EOF'
	.globl	abcdefghijklmnop, short_
	.shri
abcdefghijklmnop:
	ret
short_ = 3
EOF
"$AS" -o sa0.o s.s; "$AS" -N -o sa1.o s.s
cmp -s sa0.o sa1.o && ok "as: same bytes under -N" || bad "as: -N changed an object without a long name"
"$LD" -r -o sr0.o s0.o sa0.o; "$LD" -N -r -o sr1.o s0.o sa0.o
cmp -s sr0.o sr1.o && ok "ld -r: same bytes under -N" || bad "ld -r: -N changed the output"
"$LD" -R 0x200 -e short_name_ -o sx0 s0.o ss.o; "$LD" -N -R 0x200 -e short_name_ -o sx1 s0.o ss.o
cmp -s sx0 sx1 && ok "ld: same image under -N" || bad "ld: -N changed an image without a long name"

# --- as -N: long names from the assembler --------------------------------
cat > l.s <<'EOF'
	.globl	long_assembler_name_a_, long_assembler_name_b_
	.shri
long_assembler_name_a_:
	ld	r1, $5
	ret
long_assembler_name_b_:
	ld	r1, $7
	ret
EOF
"$AS" -N -o l.o l.s
check "as -N: LF_LNAME object" "$(flags l.o)" "32|lname"
cc c $C2L 'int long_assembler_name_a(); int long_assembler_name_b();
int f(){ return long_assembler_name_a()*10 + long_assembler_name_b(); }'
"$LD" -N -R 0x200 -e f_ -o cl c.o l.o ss.o && check "as -N names reach C callers" "$(r1 cl)" 57 \
	|| bad "as -N: link"

# --- a mix of short and long, in one link and in archives -----------------
cc m $C2L 'int a_very_long_name_one(); int short_name(); int f(){ return a_very_long_name_one()*10 + short_name(); }'
"$LD" -N -R 0x200 -e f_ -o mx m.o b.o s0.o ss.o && check "short and long objects in one link" "$(r1 mx)" 41 \
	|| bad "mixed link"
sh "$H/host/arz" r lib.a s0.o b.o sa0.o >/dev/null
"$LD" -N -R 0x200 -e f_ -o ma m.o lib.a ss.o && check "archive without an index: both kinds pulled" "$(r1 ma)" 41 \
	|| bad "archive link"

# the native ar builds the ranlib index, under the emulator
mkdir -p g/tmp
if CCZ_VAR=$VAR sh "$H/host/ccz" -s -i -L -o g/ar "$H/src/ar/ar.c" >ar.log 2>&1; then
	cp s0.o b.o sa0.o g/
	(cd g && N2ROOT="$T/g" timeout 300 "$N2" -runexec ar rs ix.a s0.o b.o sa0.o >ar.run 2>&1)
	if [ -s g/ix.a ] && grep -q '__.SYMDEF' g/ix.a; then
		"$LD" -w -N -R 0x200 -e f_ -o mi m.o g/ix.a ss.o >ld.w 2>&1
		check "ranlib index: read" "$(grep -c 'ix.a: ranlib' ld.w)" 1
		check "ranlib index: long and short entries resolve" "$(r1 mi)" 41
		check "ranlib index: marker entry" \
		    "$(od -A n -t x1 -j 30 -N 2 g/ix.a | tr -d ' ')" 0001
		(cd g && N2ROOT="$T/g" timeout 300 "$N2" -runexec ar rs is.a s0.o sa0.o >ar.run 2>&1)
		check "ranlib index without long names: first entry a name" \
		    "$(od -A n -c -j 30 -N 2 g/is.a | tr -d ' ')" sh
	else
		bad "native ar did not write an index: $(tail -2 g/ar.run)"
	fi
else
	bad "native ar does not build: $(tail -2 ar.log)"
fi

# --- ld -r of flagged objects ---------------------------------------------
"$LD" -N -r -R 0 -o r.o a.o b.o && check "ld -N -r: LF_LNAME output" "$(flags r.o)" "32|lname"
check "ld -N -r: full names kept" "$(syms r.o | grep -c 'a_very_long_name_[ot][nw][eo]_$')" 2
"$LD" -N -R 0x200 -e f_ -o rr r.o ss.o && check "the -r output links and runs" "$(r1 rr)" 42 \
	|| bad "link of the -r output"
"$LD" -N -s -R 0x200 -e f_ -o rs r.o ss.o && check "ld -s: no symbols, no LF_LNAME" "$(flags rs)" "nrb|32"

# --- readers on both forms -------------------------------------------------
check "loutdis on LF_LNAME" "$("$LOUTDIS" ab -syms | grep -c 'a_very_long_name_[ot][nw][eo]_$')" 2
check "loutdis on the plain form" "$("$LOUTDIS" sx0 -syms | grep -c ' short_name_$')" 1
cat > nl.c <<'EOF'
#include <stdio.h>
#include <l.out.h>
struct nlist nl[] = { { "f_" }, { "SS" }, { "a_very_long_name" }, { "" } };
main(argc, argv)
char *argv[];
{
	int i;

	nlist(argv[1], nl);
	for (i = 0; nl[i].n_name[0] != '\0'; i++)
		printf("%d %lx\n", nl[i].n_type, nl[i].n_value);
	return (0);
}
EOF
if CCZ_VAR=$VAR sh "$H/host/ccz" -o g/nl nl.c >nl.log 2>&1; then
	cp ab sx0 g/
	(cd g && N2ROOT="$T/g" timeout 300 "$N2" -runexec nl ab >nl.ab 2>&1)
	(cd g && N2ROOT="$T/g" timeout 300 "$N2" -runexec nl sx0 >nl.sx 2>&1)
	want=$("$LOUTID" -s ab | sed -n 's/^  SHRI 0x\([0-9a-f]*\) f_$/16 \1/p')
	check "nlist on LF_LNAME: f_" "$(sed -n 1p g/nl.ab)" "$want"
	check "nlist on LF_LNAME: SS" "$(sed -n 2p g/nl.ab)" "25 0"
	check "nlist on LF_LNAME: a long name's head is not a name" "$(sed -n 3p g/nl.ab)" "0 0"
	check "nlist on the plain form: SS" "$(sed -n 2p g/nl.sx)" "25 0"
else
	bad "nlist program does not build: $(tail -2 nl.log)"
fi

# --- the limit: 127 characters ---------------------------------------------
n126=$(printf 'n%.0s' $(seq 126)); n127=$(printf 'n%.0s' $(seq 127))
cc k $C2L "int $n126(){ return 1; } int ${n127}x(){ return 2; }"
check "a 127-character name is not warned" "$(grep -c "\"${n126}_\" is longer" k.err)" 0
check "a 129-character name is warned" \
    "$(grep -c "\"${n127}x_\" is longer than 127 characters; the linker sees \"${n127}\"" k.err)" 1
check "the 127-character name is kept" "$(syms k.o | grep -c " ${n126}_\$")" 1
check "the longer one is cut to 127" "$(syms k.o | grep -c " ${n127}\$")" 1

# --- refusals --------------------------------------------------------------
if "$LD" -R 0x200 -e f_ -o no a.o b.o ss.o 2>no.err; then
	bad "ld without -N linked an LF_LNAME object"
else
	check "ld without -N refuses" "$(grep -c 'names a symbol over 16 characters: link with -N' no.err)" 2
fi
if "$BUILD/slgen" -o lib.1 a.o 2>sl.err; then bad "slgen took an LF_LNAME object"
else check "slgen refuses" "$(grep -c 'which a shared library cannot' sl.err)" 1; fi

echo "=== lname: $pass passed, $fail failed ==="
[ "$fail" = 0 ]
