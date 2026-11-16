#!/bin/sh
# loadreuse.sh -- a load is taken from a register only while nothing can have changed
# the memory.
#
# Volatile reads, a polled flag, and a global around a store through a pointer stay
# loads; a frame slot read back after its store comes from the register.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/r.c" <<'EOF2'
extern printf();
int g, h; long gl; volatile int vg;
vp(p) int *p; { return *(volatile int *)p + *(volatile int *)p; }
vv() { int a; a = vg; h = a; return a + vg; }
poll() { while (!(vg & 1)) ; return vg; }
gp(p) int *p; { int a; a = g; h = a; *p = 5; return a + g; }
lc(x) int x; { int a[2]; a[0] = x + 7; return a[0] + a[0]; }
long ll(x) long x; { long b[2]; b[0] = x + 1; return b[0] + b[0]; }
main() { int i, a, b; g = 7; a = vp(&g); b = gp(&g); printf("%d %d %d\n", a, b, g); vg = 3; printf("%d %d\n", vv(), poll());
 for (i = -2; i < 3; i++) printf("%d %ld\n", lc(i), ll((long)i * 70000L)); return 0; }
EOF2
cat > "$T/want" <<'EOF2'
14 12 5
6 3
10 -279998
12 -139998
14 2
16 140002
18 280002
EOF2
if (cd "$T" && "$CCZ" -o "$T/p" r.c >/dev/null 2>&1); then
	"$N2" -runexec "$T/p" 2>/dev/null | grep -v '^\[exit' > "$T/got" || true
	if cmp -s "$T/got" "$T/want"; then echo "  values PASS"
	else echo "  values FAIL:"; diff "$T/want" "$T/got" | sed 's/^/      /'; fail=1; fi
else
	echo "  loadreuse: compile FAIL"; fail=1
fi

# The listing, one function per `epilog', in source order.
(cd "$T" && CC2LIST=1 "$CCZ" -c -o "$T/r.o" r.c > "$T/lst" 2>/dev/null) || { echo "  loadreuse: listing FAIL"; exit 1; }
fn() { awk -v n="$1" '/epilog/ { k++; next } k == n' "$T/lst"; }
count() { # <fn index> <name> <pattern> <want> <what>
	c=$(fn "$1" | grep -cE "$3" || true)
	if [ "$c" = "$4" ]; then printf '  %-5s PASS  (%s)\n' "$2" "$5"
	else printf '  %-5s FAIL: %s matches %s, want %s (%s)\n' "$2" "$c" "$3" "$4" "$5"; fn "$1" | sed 's/^/      /'; fail=1; fi
}
count 0 vp '@rr[0-9]+$' 2 "two volatile reads through the pointer"
count 1 vv 'vg_$' 2 "a volatile global read twice"
count 2 poll 'vg_$' 2 "the polled flag in the loop and after"
count 3 gp 'g_$' 2 "a global around a store through a pointer"
count 4 lc ', -[0-9]+\(r13\)$' 0 "a frame slot read back from the register"
count 5 ll ', -[0-9]+\(r13\)$' 0 "a long frame slot read back from the pair"

[ "$fail" = 0 ] || { echo "=== loadreuse: FAIL ==="; exit 1; }
echo "=== loadreuse: PASS ==="
