#!/bin/sh
# blkmove-variant.sh -- an aggregate copy must compile under EVERY variant.
#
# BLKMOVE is the Z8001 LDIRB, and blkmv.t states it for LPTX/PAIR operands
# only: LDIRB always takes its dst and src as a full segment:offset PAIR, so
# there is no near-address form of the rule to select.  modsasg() nevertheless
# chose SPTR unless VLARGE was set, which under a variant that leaves VLARGE
# unset -- VTPA, whose ordinary pointers are the 16-bit TPA-segment offset --
# left selection with nothing to match and aborted cc1 with EDFA75.  The CP/M
# tree builds every user command with VTPA (its UVAR), so a single struct
# assignment anywhere in a command was an internal compiler error.
#
# Both sizes matter: a small aggregate can be copied inline word by word, so
# only the large one is certain to reach the BLKMOVE rule at all.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"		# $BUILD
CC0="$BUILD/z8001/cc0-z8001"
CC1="$BUILD/z8001/cc1-z8001"
CC2="$BUILD/z8001/cc2-z8001"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

cat > "$T/small.c" <<'EOF'
struct s { char a[8]; int b; };
struct s g1, g2;
blk() { g1 = g2; }
EOF
cat > "$T/large.c" <<'EOF'
struct s { char a[200]; int b; };
struct s g1, g2;
blk() { g1 = g2; }
EOF

# the system variant, then the user variant the CP/M commands are built with
fail=0
for var in 800000020800 001000000004; do
	for n in small large; do
		if "$CC0" "$var" "$T/$n.c" "$T/$n.z0" >"$T/out" 2>&1 &&
		   "$CC1" "$var" "$T/$n.z0" "$T/$n.z1" >>"$T/out" 2>&1 &&
		   "$CC2" "$var" "$T/$n.z1" "$T/$n.o" "$T/$n.scr" 0 >>"$T/out" 2>&1
		then
			echo "  $var $n aggregate copy: ok"
		else
			echo "  $var $n aggregate copy: FAIL"
			sed 's/^/    /' "$T/out"
			fail=1
		fi
	done
done
[ $fail -eq 0 ] || { echo "blkmove-variant: FAILED"; exit 1; }
echo "blkmove-variant: OK -- every variant copies an aggregate"
