#!/bin/sh
# peepstamp.sh -- a function's code does not depend on the functions before it.
#
# The copy-deletion liveness walk marks the nodes it has visited in i_pc.  A
# node reused from an earlier function still held that function's code address,
# which could read as a mark of the current walk and stop it early.  _doprnt in
# libc's printf.c lost the copy `LDL RR0,RR8' when printf, fprintf, sprintf and
# xprintf were compiled before it, and kept it when they were not.
#
# _doprnt_ is compiled with and without the functions before it, and the two
# bodies must match (absolute addresses masked, CALR/CALL folded).

set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"; CC1="$BUILD/z8001/cc1-z8001"
CC2="$BUILD/z8001/cc2-z8001"; DIS="$BUILD/tools/loutdis"
VAR=800000020800; INC="-I$H/src/include -I$H/src/include/sys"
SRC="$H/src/libc/stdio/printf.c"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

cp "$SRC" "$T/all.c"
awk '/^printf\(/ { drop = 1 } /^_doprnt\(/ { drop = 0 } !drop' "$SRC" > "$T/one.c"
grep -q '^printf(' "$T/all.c" && ! grep -q '^printf(' "$T/one.c" &&
	grep -q '^_doprnt(' "$T/one.c" || { echo "  peepstamp: printf.c layout changed"; exit 1; }

body() { # <name>
	"$CC0" $VAR "$T/$1.c" "$T/$1.z0" $INC 2>/dev/null && "$CC1" $VAR "$T/$1.z0" "$T/$1.z1" &&
	"$CC2" 0010 "$T/$1.z1" "$T/$1.o" "$T/$1.scr" 0 || { echo "  peepstamp: compile FAIL"; exit 1; }
	"$DIS" -v -fn _doprnt_ "$T/$1.o" | sed 1d |
		sed -E 's/^ *[0-9a-f]+: //; s/0x[0-9A-F]{2}:0x[0-9A-F]{4}/m/g; s/^CALR /CALL /' > "$T/$1.dis"
}
body all
body one
[ -s "$T/all.dis" ] || { echo "  peepstamp: no _doprnt_"; exit 1; }
if cmp -s "$T/all.dis" "$T/one.dis"; then
	echo "  _doprnt_ alone = after printf..xprintf  PASS"
else
	echo "  _doprnt_ alone = after printf..xprintf  FAIL"
	diff "$T/all.dis" "$T/one.dis" | sed 's/^/      /'
	echo "=== peepstamp: FAIL ==="; exit 1
fi
echo "=== peepstamp: PASS ==="
