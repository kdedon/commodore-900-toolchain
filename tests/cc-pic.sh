#!/bin/sh
# cc-pic.sh -- the driver works out -VPIC for itself.
#
# A client reaches library data through a far-pointer slot, emitted under
# -VPIC; ld refuses a client without it.  A command that compiles and links
# against a shared library sets the flag; a `-c' compile must name it.  An
# implied flag must give the image the explicit two-step build does:
#
#	1  one step, dynamic library	the flag is implied
#	2  one step, static		it is not
#	3  two steps, no flag		ld refuses, naming the flag
#	4  two steps, the flag named	the image of case 1
#
# Then the static default runs, and the native driver's -V output is checked.
#
# Needs libc.1 (`make libc1').  The native case needs `make native' and the
# emulator, and is skipped without them.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"		# $BUILD
CCZ="$H/host/ccz"
LIB="$BUILD/libc1/libc.1"
[ -f "$LIB" ] || { echo "cc-pic: $LIB not built -- run \`make libc1'"; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
ok()  { printf '  PASS %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

# Only data needs a slot, so the program names environ and optind.
cat > "$T/prog.c" <<'EOF'
#include <stdio.h>
extern char **environ;
extern int optind;

main(argc, argv) int argc; char **argv;
{
	printf("pic %d %d %s\n", argc, optind,
		environ[0] == 0 ? "noenv" : "env");
	return 0;
}
EOF

echo "=== 1 one command that compiles and links against libc.1"
if "$CCZ" -i -o "$T/one.sl" "$T/prog.c" -lc.1 > "$T/log" 2>&1; then
	ok "\`ccz prog.c -lc.1' links with no flag named"
else
	bad "$(sed -n 1p "$T/log")"
fi
"$CCZ" -i -o "$T/slibc.sl" "$T/prog.c" -slibc > /dev/null 2>&1 || true
cmp -s "$T/one.sl" "$T/slibc.sl" \
	&& ok "-lc.1 and -slibc are one link" \
	|| bad "-lc.1 and -slibc produced different images"

echo "=== 2 one command that compiles and links statically"
"$CCZ" -c -o "$T/plain.o" "$T/prog.c" > /dev/null 2>&1
"$CCZ" -c -VPIC -o "$T/pic.o" "$T/prog.c" > /dev/null 2>&1
cmp -s "$T/plain.o" "$T/pic.o" \
	&& bad "-VPIC changed nothing: the comparison below proves nothing" \
	|| ok "-VPIC is a different object, so the images below can be told apart"
"$CCZ" -i -o "$T/one.st" "$T/prog.c" > /dev/null 2>&1
"$CCZ" -i -o "$T/two.st" "$T/plain.o" > /dev/null 2>&1
cmp -s "$T/one.st" "$T/two.st" \
	&& ok "a static link is the link of an ordinary object: no flag implied" \
	|| bad "a static link did not come out static"

echo "=== 3 two steps, the flag not named"
if "$CCZ" -i -o "$T/bad.sl" "$T/plain.o" -lc.1 > "$T/err" 2>&1; then
	bad "a client compiled without -VPIC was accepted"
else
	grep -q -- '-VPIC' "$T/err" \
		&& ok "$(sed -n 1p "$T/err")" \
		|| bad "refused, but the message does not name the flag"
fi

echo "=== 4 two steps, the flag named"
if "$CCZ" -i -o "$T/two.sl" "$T/pic.o" -lc.1 > "$T/log" 2>&1; then
	cmp -s "$T/one.sl" "$T/two.sl" \
		&& ok "the same image the one-step link produced" \
		|| bad "the two-step image differs from the implied one"
else
	bad "$(sed -n 1p "$T/log")"
fi

# ------------------------------------------------------------------ it runs
# Static: the runner has no library loader.
N2="${N2:-$(sh "$HERE/runner.sh" 2>/dev/null || true)}"
echo "=== 5 the static default runs"
if [ -n "$N2" ] && [ -x "$N2" ]; then
	"$CCZ" -o "$T/run.out" "$T/prog.c" > /dev/null 2>&1
	N2ROOT="$T" "$N2" -runexec "$T/run.out" > "$T/run.log" 2>&1 || true
	grep -q '^pic 1 1 ' "$T/run.log" \
		&& ok "$(sed -n 1p "$T/run.log")" \
		|| bad "the static program did not print what it should"
else
	echo "  SKIP no emulator"
fi

# --------------------------------------------------------- the native driver
# The guest cannot fork, so only the -V line is read.  VPIC is the 8 in the
# variant word's last digit.

echo "=== 6 the driver on the machine"
if [ -n "$N2" ] && [ -x "$N2" ] && [ -f "$BUILD/native/cc" ]; then
	R="$T/root"; mkdir -p "$R/bin" "$R/lib" "$R/work"
	cp "$BUILD/native/cc" "$R/bin/cc"
	cp "$LIB" "$R/lib/libc.1"
	cp "$T/prog.c" "$R/work/prog.c"
	nat() {	# nat <args...> -- the variant word the driver hands cc0
		N2ROOT="$R" timeout 20 "$N2" -runexec "$R/bin/cc" -V "$@" \
			> "$T/nat.log" 2>&1 || true
		sed -n 's/^cc0 \([0-9A-F]*\) .*/\1/p' "$T/nat.log" | sed -n 1p
	}
	case "$(nat -i /work/prog.c -lc.1)" in
	*[89ABCDEF]) ok "cc x.c -lc.1 compiles with VPIC set";;
	"") bad "the native driver printed no pass line";;
	*) bad "the native driver did not imply the flag";;
	esac
	case "$(nat -c /work/prog.c)" in
	*[0-7]) ok "cc -c x.c compiles without it";;
	"") bad "the native driver printed no pass line";;
	*) bad "the native driver set the flag for a compile";;
	esac
else
	echo "  SKIP no emulator or no build/native/cc (\`make native')"
fi

[ "$fail" = 0 ] || { echo "cc-pic: FAILED"; exit 1; }
echo "cc-pic: the driver implies -VPIC where it can know, and nowhere else"
exit 0
