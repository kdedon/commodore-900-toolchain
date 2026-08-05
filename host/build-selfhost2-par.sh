#!/bin/sh
# build-selfhost2-par.sh - run build-selfhost2.sh over the full file set, N files
# at a time (each single-file invocation is independent).  Collects the per-file
# verdict lines and prints the roll-up.
HERE=$(cd "$(dirname "$0")" && pwd)
: "${N2:?set N2 to the n2z8001 simulator binary}"
J="${J:-8}"

COMMON="bget bput dget diag dput getvar iget iput lget lput makvar milnam mionam newlab newseg nput segnam sget sput talloc tcpy unbget"
N0="cc0 cc0key cc0sym cpp dbgt0 ddecl dope double etc expand expr fold gcandt gdecl get init lex locals sharp size stat"
N1="cc1 cc1sym code mtree0 mtree1 mtree3 node out pool reg0 sel0 sel1 snap0 tree0 tree1"
N1MD="altemp amd fixtop gen1 gen2 mtree2 mtree4 outmch reg1 sel2 snap1 table0 table1"
N2P="cc2 cc2sym dbgt2 emit0 getfun optim"
N2MD="afield emit1 getcod optab outcoh peep"

srcs=""
for f in $COMMON; do srcs="$srcs src/common/$f.c"; done
for f in $N0;     do srcs="$srcs src/n0/$f.c"; done
srcs="$srcs src/n0/z8001/bind.c"
for f in $N1;     do srcs="$srcs src/n1/$f.c"; done
for f in $N1MD;   do srcs="$srcs src/n1/z8001/$f.c"; done
srcs="$srcs tables/macros.c tables/patern.c"
for f in $N2P;    do srcs="$srcs src/n2/$f.c"; done
for f in $N2MD;   do srcs="$srcs src/n2/z8001/$f.c"; done

OUTD="$HERE/build/selfhost/work/verdicts"
rm -rf "$OUTD"; mkdir -p "$OUTD"
n=0
for src in $srcs; do
	b=$(basename "$src" .c)
	sh "$HERE/build-selfhost2.sh" "$src" >"$OUTD/$b.v" 2>&1 &
	n=$((n+1))
	while [ "$(jobs -p | wc -l)" -ge "$J" ]; do wait -n || true; done
done
wait || true
grep -h "^IDENT\|^DIFFER\|^FAIL\|^HOSTFAIL" "$OUTD"/*.v | sort | awk '{print}'
echo "=== roll-up: $(grep -hc '^IDENT' "$OUTD"/*.v | awk '{s+=$1}END{print s}') identical / $n files ==="
