#!/bin/sh
# as-locptr.sh -- the assembler holds a pointer in a pointer, on every host.
#
# `address' (src/as/z8001/asmch.h) is the TARGET's address type, and its width on
# the host is whatever `long' is there: 64 bits where long is 64 bits, 32 bits on
# an LLP64 host (Windows/MinGW, which the CI builds).  A host pointer parked in
# one therefore survives on the first host and is truncated on the second, where
# reading it back dereferences a 32-bit stump -- so a defect of that shape is
# invisible to a Linux run, ASAN and valgrind included, and is a segfault on
# Windows the first time crts0.s names a location counter (.prvd).
#
# This gate reproduces the narrow host on any host: it rebuilds the assembler
# from the staged sources with `address' narrowed to `int', and assembles
# crts0.s with it.  The object must be the one the ordinary assembler writes.
# Nothing here needs Windows, a cross-compiler or an emulator.
H="$(cd "$(dirname "$0")/.." && pwd)"
B="${C900_TC_BUILD:-$H/host/build}"
AS="$B/as-z8001"
SRC="$B/as"
[ -x "$AS" ] && [ -d "$SRC" ] || { echo "as-locptr: as-z8001 not built (make as)"; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

cp -RL "$SRC"/. "$T/src" || exit 2
rm -f "$T"/src/*.o "$T"/src/as-z8001
sed -i 's/^typedef[ \t][ \t]*long[ \t][ \t]*address;/typedef int address;/' "$T/src/asmch.h"
grep -q '^typedef int address;' "$T/src/asmch.h" || {
	echo "as-locptr: asmch.h no longer declares \`typedef long address'"; exit 2; }
( cd "$T/src" && gcc -std=gnu89 -w -DLADDR=1 -DZ8001 -I. -o "$T/as-narrow" *.c ) || {
	echo "as-locptr: FAIL -- the assembler does not build with a 32-bit address"; exit 1; }

S="$H/src/csu/crts0.s"
"$AS" -o "$T/wide.o" "$S" || { echo "as-locptr: as-z8001 rejected $S"; exit 2; }
"$T/as-narrow" -o "$T/narrow.o" "$S" 2>"$T/err"; rc=$?
if [ $rc -ne 0 ]; then
	sed 's/^/           /' "$T/err"
	echo "as-locptr: FAIL -- as with a 32-bit address died on $S (rc $rc):"
	echo "           a host pointer is being kept in an \`address'."
	exit 1
fi
if ! cmp -s "$T/wide.o" "$T/narrow.o"; then
	echo "as-locptr: FAIL -- the object differs from the one as-z8001 writes"
	exit 1
fi
echo "=== as-locptr: crt0 assembles identically with a 32-bit address ==="
