#!/bin/sh
# native-ld.sh - build ld FOR the machine, and link a program ON it.
#
# Only the unity build puts the whole linker through cc0 at once.
#
#	1. src/ld/all.c compiles and links for the Z8001
#	2. that ld links a C program against libc, byte-identical to the host's
#	3. the program runs on the guest
#
# Needs ccz and the emulator; missing either fails.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HERE="$ROOT/host"				# publish.sh reads $HERE for $BUILD
. "$HERE/publish.sh"				# $BUILD

CCZ="$HERE/ccz"
LIBC="$BUILD/libc-z8001"
[ -x "$CCZ" ] || { echo "native-ld.sh: no ccz at $CCZ; run \`make'." >&2; exit 2; }
[ -f "$LIBC/crt0.o" ] || { echo "native-ld.sh: no libc-z8001; run \`make libc'." >&2; exit 2; }
[ -x "$BUILD/ld-z8001" ] || { echo "native-ld.sh: no host ld-z8001; run \`make'." >&2; exit 2; }
N2="${N2:-$(sh "$HERE/runner.sh")}"
[ -n "$N2" ] && [ -x "$N2" ] || { echo "native-ld.sh: no emulator; see host/deps.sh." >&2; exit 2; }

W="$BUILD/native-ld"
rm -rf "$W"; mkdir -p "$W"
cd "$W"

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

# Arguments are relative to the guest root, $W.
run() { # <program> <args...>  -- echoes the GUEST's exit status, or `norun'
	prog="$1"; shift
	log="$W/$(basename "$prog").log"
	N2ROOT="$W" timeout 600 "$N2" -runexec "$prog" "$@" >"$log" 2>&1 || :
	sed -n 's/^\[exit \([0-9]*\)\]$/\1/p' "$log" | tail -1 | grep -q . \
		|| { echo norun; return; }
	sed -n 's/^\[exit \([0-9]*\)\]$/\1/p' "$log" | tail -1
}

# ---- 1. the linker.  BREADBOX, ld's in-memory output buffer, pokes target
# stdio internals.
if "$CCZ" -c -o all.o -DBREADBOX=16384 -I"$ROOT/src/ld" "$ROOT/src/ld/all.c" \
	>all.log 2>&1 && "$CCZ" -s -i -L -o ld all.o >>all.log 2>&1
then
	ok "src/ld/all.c builds for the Z8001 ($(wc -c < ld) B)"
else
	bad "src/ld/all.c does NOT build for the Z8001"
	grep -v Warning all.log | head -5 | sed 's/^/       /'
	echo "=== native-ld: $pass passed, $fail failed ==="
	exit 1
fi

# ---- 2. link a real program against the real libc.
cat > hello.c <<'EOF'
#include <stdio.h>

int
main(argc, argv)
int	argc;
char	**argv;
{
	printf("native-ld %d %s\n", argc, argv[argc - 1]);
	return 0;
}
EOF
"$CCZ" -c -o hello.o hello.c >hello.log 2>&1
cp "$LIBC/crt0.o" "$LIBC/libc-z8001.a" .
"$BUILD/ld-z8001" -n -i -L -o h.out crt0.o hello.o libc-z8001.a
st=$(run "$W/ld" -n -i -L -o t.out crt0.o hello.o libc-z8001.a)
if [ "$st" != 0 ]; then
	bad "ld exited $st: $(tail -2 ld.log | tr '\n' ' ')"
elif cmp -s t.out h.out; then
	ok "ld: image byte-identical to the host's ($(wc -c < t.out) B)"
else
	bad "ld: image DIFFERS from the host's"
	cmp -l t.out h.out 2>&1 | head -5 | sed 's/^/       /'
fi

# ---- 3. run it: agreeing linkers can both be wrong.

if [ -f t.out ]; then
	st=$(run "$W/t.out" one two)
	if [ "$st" = 0 ] && grep -q '^native-ld 3 two$' t.out.log; then
		ok "the linked program runs on the guest"
	else
		bad "the linked program exited $st: $(tail -2 t.out.log | tr '\n' ' ')"
	fi
else
	bad "the linked program was not produced"
fi

echo "=== native-ld: $pass passed, $fail failed ==="
[ "$fail" = 0 ]
