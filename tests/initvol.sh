#!/bin/sh
# initvol.sh -- a structure member's initializer is volatile exactly when the
# structure or the member is.
#
# Read from the front end's output through the IR printer.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"; CC3="$BUILD/z8001/cc3-z8001"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

cat > "$T/f.c" <<'EOF'
struct s { int x; long y; char c; int z; };
struct v { int a; volatile int b; };
plain() { struct s v = {1, 2L, 'c', 4}; g(&v); }
member() { struct v u = {1, 2}; g(&u); }
whole() { volatile struct s w = {1, 2L, 'c', 4}; struct s c; c = w; g(&c); }
EOF
"$CC0" $VAR "$T/f.c" "$T/f.z0" && "$CC3" $VAR "$T/f.z0" "$T/f.z3" ||
	{ echo "  initvol: compile FAIL"; exit 1; }

# The type of each store's destination, in order; `v' marks volatile.
got=$(grep -A1 '^	= ' "$T/f.z3" | grep -v '^	= \|^--' |
	awk '{ print $2 ($3 == "volatile" ? "v" : "") }' | tr '\n' ' ')
want="S16 S32 S8 S16 S16 S16v S16v S32v S8v S16v Blk "
if [ "$got" = "$want" ]; then
	echo "=== initvol: PASS ==="
else
	echo "  initvol: got [$got] want [$want]"
	echo "=== initvol: FAIL ==="; exit 1
fi
