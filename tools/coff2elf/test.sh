#!/bin/sh
# test.sh -- prove the x86-target host-link bridge end to end:
#   COFF fixture -> coff2elf -> ELF32 -> gnu ld + libcoh crt0 -> run on host.
# Two cases: (1) `_main` returns 42, no relocs; (2) a R_DIR32 reloc to .data.
#
# Run it as `make check-coff2elf', which builds what it needs into $C900_BUILD.
# Work happens in a scratch directory, so nothing is written into the source
# tree.
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=${C900_BUILD:-$ROOT/host/build}/tools
for f in coff2elf mkfix crt0.o libcoh.a; do
	[ -f "$T/$f" ] || {
		echo "test.sh: no $T/$f -- run \`make check-coff2elf'" >&2
		exit 2
	}
done

W=$T/t.$$
mkdir -p "$W"
trap 'rm -rf "$W"' EXIT INT TERM
cd "$W"

fail=0
chk() {	# chk <label> <got> <want>
	if [ "$2" = "$3" ]; then echo "PASS  $1 (=$2)"
	else echo "FAIL  $1: got '$2' want '$3'"; fail=1; fi
}

echo "== case 1: _main returns 42, no relocations =="
"$T/mkfix" t1.coff
"$T/coff2elf" -u t1.coff t1.elf.o
readelf -h t1.elf.o >/dev/null && echo "  ELF header OK"
readelf -s t1.elf.o | grep -q ' main$' && echo "  symbol 'main' present (underscore stripped)"
ld -m elf_i386 -e _start -o t1.prog "$T/crt0.o" t1.elf.o "$T/libcoh.a"
set +e; ./t1.prog; rc=$?; set -e
chk "case1 exit code" "$rc" "42"

echo "== case 2: R_DIR32 reloc to a .data symbol =="
"$T/mkfix" -r t2.coff
"$T/coff2elf" -u t2.coff t2.elf.o
readelf -r t2.elf.o | grep -qi 'R_386_32' && echo "  R_386_32 relocation emitted"
ld -m elf_i386 -e _start -o t2.prog "$T/crt0.o" t2.elf.o "$T/libcoh.a" 2>/dev/null
# main loads the first 4 bytes of "Hi\0" = 'H'|'i'<<8 = 0x6948 = 26952
set +e; ./t2.prog; rc=$?; set -e
chk "case2 exit code (low byte of 0x6948)" "$rc" "$((0x6948 & 0xff))"

exit $fail
