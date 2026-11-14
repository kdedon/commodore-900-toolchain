#!/bin/sh
# symlen.sh -- an l.out symbol keeps 16 bytes of its name, the appended `_'
# included.  cc2 names every external it truncates and every pair the
# truncation makes one symbol; a name that fits says nothing.
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
O="$BUILD/z8001"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cc() { # <source>: compile, cc2's stderr into $T/err
	printf '%s\n' "$1" > "$T/s.c"
	"$O/cc0-z8001" $VAR "$T/s.c" "$T/s.z0" &&
	"$O/cc1-z8001" $VAR "$T/s.z0" "$T/s.z1" &&
	"$O/cc2-z8001" 0012 "$T/s.z1" "$T/s.o" "$T/s.scr" 0 2>"$T/err"
}
want() { # <label> <regex> yes|no
	if grep -Eq "$2" "$T/err"; then got=yes; else got=no; fi
	if [ "$got" = "$3" ]; then
		echo "  $1 PASS"
	else
		echo "  $1 FAIL: [$2] present=$got want=$3"; sed 's/^/      /' "$T/err"; fail=1
	fi
}

cc 'int fifteen_chars_x; int f() { return fifteen_chars_x; }' || { echo "  compile FAIL"; exit 1; }
want "15 characters fit" 'Warning' no
cc 'int abcdefghijklmnopA; int abcdefghijklmnopB; int f() { return abcdefghijklmnopA + abcdefghijklmnopB; }' ||
	{ echo "  compile FAIL"; exit 1; }
want "truncated definition" '"abcdefghijklmnopA_" is longer than 16 characters; the linker sees "abcdefghijklmnop"' yes
want "merged definitions" '"abcdefghijklmnopA_" and "abcdefghijklmnopB_" are one symbol' yes
cc 'int abcdefghijklmno; extern int abcdefghijklmno_x(); int f() { return abcdefghijklmno + abcdefghijklmno_x(); }' ||
	{ echo "  compile FAIL"; exit 1; }
want "truncated reference" '"abcdefghijklmno_x_" is longer' yes
want "merged with a short name" '"abcdefghijklmno_" and "abcdefghijklmno_x_" are one symbol' yes

[ "$fail" = 0 ] || { echo "=== symlen: FAIL ==="; exit 1; }
echo "=== symlen: PASS ==="
