#!/bin/sh
# shlib-data.sh -- DATA imports: the compiler's -VPIC slot, slgen's SE_DATA
# export and ld's binding of one to the other.
#
# A datum has no address until exec places the library, so -VPIC reaches each
# extern object through a far pointer in the private literal pool.  ld fills
# the cell if the symbol is local, else zeroes it and emits an LI_IMP.  The
# library is built -VPIC too.
#
# Last, the same program built both ways must print the same answers.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"		# $BUILD
O="$BUILD/z8001"; AS="$BUILD/as-z8001"; LD="$BUILD/ld-z8001"
SLGEN="$BUILD/slgen"; PEEP="${PEEP:-0010}"
# VPIC is bit 43: 800000000800 -> 800000000808.
VAR="${VAR:-800000000800}"; VARP="${VARP:-800000000808}"
[ -x "$SLGEN" ] || { echo "shlib-data: slgen not built"; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cc() {		# cc <name> <variant>
	"$O/cc0-z8001" "$2" "$T/$1.c" "$T/$1.z0" > /dev/null 2>&1
	"$O/cc1-z8001" "$2" "$T/$1.z0" "$T/$1.z1" > /dev/null 2>&1
	"$O/cc2-z8001" $PEEP "$T/$1.z1" "$T/$1.o" "$T/$1.scr" 0 > /dev/null 2>&1
}
ok()   { printf '  PASS %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; fail=1; }

# ---------------------------------------------------------------- the library
# Data and accessors in separate modules, so the library's own references go
# through cells.
cat > "$T/tdata.c" <<'EOF'
struct toybox { int a; int b; };
struct toybox toy_box = { 11, 22 };
char toy_arr[8];
EOF
cat > "$T/tfun.c" <<'EOF'
struct toybox { int a; int b; };
extern struct toybox toy_box;
extern char toy_arr[];

int toy_sum()
{
	return toy_box.a + toy_box.b + toy_arr[0];
}

int toy_set(v) int v;
{
	toy_box.b = v;
	toy_arr[1] = v;
	return toy_box.a;
}
EOF
cc tdata "$VARP"; cc tfun "$VARP"
printf '\t.globl\tSS\nSS = 0\n' > "$T/ss.s"; "$AS" -o "$T/ss.o" "$T/ss.s"
printf 'toy_sum_\ntoy_set_\ntoy_box_ data\ntoy_arr_ data\n' > "$T/toy.exp"
"$SLGEN" -A "$AS" -L "$LD" -T "$T" -e "$T/toy.exp" -o "$T/libtoy.1" \
	"$T/tdata.o" "$T/tfun.o" "$T/ss.o" > /dev/null

echo "=== the library's export table"
python3 "$H/tests/shlib-data-check.py" lib "$T/libtoy.1" || fail=1

# ----------------------------------------------------------------- the client
cat > "$T/cli.c" <<'EOF'
struct toybox { int a; int b; };
extern struct toybox toy_box;
extern char toy_arr[];
extern int toy_sum(), toy_set();

main()
{
	toy_box.a = 5;
	toy_arr[0] = 3;
	return toy_sum() + toy_set(9) + toy_box.b + toy_arr[1];
}
EOF
cc cli "$VARP"
"$LD" -n -i -o "$T/cli.out" "$T/cli.o" "$T/ss.o" "$T/libtoy.1"
echo "=== a client that reads and writes the library's data"
python3 "$H/tests/shlib-data-check.py" cli "$T/cli.out" || fail=1

# ------------------------------------------------------------- the refusals
echo "=== the refusals"
cc cli "$VAR"					# same source, no -VPIC
if "$LD" -n -i -o "$T/bad.out" "$T/cli.o" "$T/ss.o" "$T/libtoy.1" \
		> "$T/err" 2>&1; then
	bad "a client compiled without -VPIC was accepted"
else
	grep -q 'far pointer in private data' "$T/err" \
		&& ok "$(sed -n 1p "$T/err")" \
		|| bad "refused, but not for the reason expected"
fi
cc cli "$VARP"
if "$LD" -n -i -s -o "$T/bad.out" "$T/cli.o" "$T/ss.o" "$T/libtoy.1" \
		> "$T/err" 2>&1; then
	bad "-s on a client with data imports was accepted"
else
	ok "$(sed -n 1p "$T/err")"
fi
# A `readonly' object is exported `shrd': one system-wide copy in the shared
# segment, as _ctype_ and sys_errlist_ are.
cat > "$T/tro.c" <<'EOF'
readonly int toy_ro = 3;
EOF
cc tro 800000020808					# +VREADONLY
echo "=== a readonly table, exported out of the shared segment"
printf 'toy_sum_\ntoy_set_\ntoy_box_ data\ntoy_arr_ data\ntoy_ro_ shrd\n' \
	> "$T/ro.exp"
if "$SLGEN" -A "$AS" -L "$LD" -T "$T" -e "$T/ro.exp" -o "$T/libro.1" \
		"$T/tdata.o" "$T/tfun.o" "$T/tro.o" "$T/ss.o" \
		> "$T/err" 2>&1; then
	python3 "$H/tests/shlib-data-check.py" shrd "$T/libro.1" || fail=1
else
	sed -n 1p "$T/err"
	bad "slgen refused a readonly export"
fi
# Listing that table as `data' is refused: the kind is checked.

printf 'toy_sum_\ntoy_set_\ntoy_box_ data\ntoy_arr_ data\ntoy_ro_ data\n' \
	> "$T/rob.exp"
if "$SLGEN" -A "$AS" -L "$LD" -T "$T" -e "$T/rob.exp" -o "$T/librob.1" \
		"$T/tdata.o" "$T/tfun.o" "$T/tro.o" "$T/ss.o" \
		> "$T/err" 2>&1; then
	bad "slgen accepted a shared table called private"
else
	grep -q 'the list calls it' "$T/err" \
		&& ok "$(sed -n 1p "$T/err")" \
		|| bad "slgen refused, but not for the reason expected"
fi

# --------------------------------------- the indirection does not change value
N2="${N2:-$(sh "$H/host/runner.sh" 2>/dev/null)}"
echo "=== the same program, both ways, linked statically and run"
if [ -z "$N2" ]; then
	echo "  SKIP no emulator"
else
	cat > "$T/run.c" <<'EOF'
#include <stdio.h>
struct toybox { int a; int b; };
extern struct toybox toy_box;
extern char toy_arr[];
extern int toy_sum(), toy_set();

main()
{
	int i, s;

	toy_box.a = 5;
	toy_arr[0] = 3;
	printf("%d %d %d\n", toy_sum(), toy_set(9), toy_box.b);
	printf("%d %d %d\n", toy_box.a, toy_arr[0], toy_arr[1]);
	/* a VARIABLE subscript: the cell is the base of an indexed access */
	for (i = 0; i < 8; i++)
		toy_arr[i] = i * 3;
	for (s = 0, i = 0; i < 8; i++)
		s += toy_arr[i];
	printf("%d %d\n", s, *(&toy_box.b));
	return 0;
}
EOF
	for v in plain pic; do
		w=800000020800; [ "$v" = pic ] && w=800000020808
		CCZ_VAR=$w "$H/host/ccz" -o "$T/r$v" "$T/run.c" "$T/tdata.c" \
			"$T/tfun.c" > /dev/null 2>&1 \
			|| bad "the $v build did not link"
	done
	a=$("$N2" -runexec "$T/rplain" 2>/dev/null)
	b=$("$N2" -runexec "$T/rpic" 2>/dev/null)
	[ -n "$a" ] || bad "the plain build printed nothing"
	[ "$a" = "$b" ] && ok "both print [$(echo "$a" | tr '\n' '/')]" \
			|| bad "plain=[$a] pic=[$b]"
	cmp -s "$T/rplain" "$T/rpic" \
		&& bad "-VPIC produced the same image: the flag did nothing" \
		|| ok "-VPIC is a different image"
fi

[ $fail -eq 0 ] || { echo "shlib-data: FAILED"; exit 1; }
echo "shlib-data: -VPIC, SE_DATA and ld's data slots agree"
