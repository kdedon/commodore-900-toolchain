#!/bin/sh
# asan_frontend.sh - build cc0-z8001 + cc1-z8001 under AddressSanitizer and run the
# fuzzer corpus + the real userland ($Z8001_DONOR/cmd/*.c) through them, failing
# on any heap/global memory error.  The front end is a host-ported (LP64) K&R compiler,
# so latent pointer-width / buffer bugs that glibc only sometimes detects become
# DETERMINISTIC under ASAN.  This gate has already caught: the get() double-fclose past
# EOF (SIGABRT on bad input), the setfname strncpy-no-NUL OOB (every userland file), and
# a latent ramode[NONE] over-read in the Z8001 coder (contrived-only).
#   usage: tests/asan_frontend.sh [seeds_per_generator]   (default 30)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
. "$(dirname "$0")/donor.sh"
B=$(cd "$HERE/.." && pwd)                       # repo root
HB="$B/host"; W="$HB/build/cc"
CMD="$Z8001_DONOR/cmd"; UINC="$Z8001_DONOR/include"
VAR="${VAR:-800000000800}"; N=${1:-30}
INC="-I $W/n1/z8001 -I $W/n0/z8001 -I $W/h/z8001 -I $W/generated -I $W/n0 -I $W/n1 -I $W/h -I $W/shim -I $W/common"
[ -d "$W/n0" ] || { echo "run build-cc.sh first (need the shimmed src/cc scratch copy)"; exit 1; }

A=$(mktemp -d); trap 'rm -rf "$A"' EXIT; mkdir -p "$A/c0" "$A/c1"
echo "--- building ASAN cc0-z8001 + cc1-z8001 ---"
for f in "$W"/n0/*.c "$W"/n0/z8001/*.c "$W"/common/*.c; do
  gcc -std=gnu89 -g -O0 -fsanitize=address -w -c -DCOHERENT $INC "$f" -o "$A/c0/$(basename ${f%.c}).o" 2>/dev/null; done
for f in "$W"/n1/*.c "$W"/n1/z8001/*.c "$W"/n1/tables/macros.c "$W"/n1/tables/patern.c "$W"/common/*.c; do
  gcc -std=gnu89 -g -O0 -fsanitize=address -w -c -DCOHERENT $INC "$f" -o "$A/c1/$(basename ${f%.c}).o" 2>/dev/null; done
gcc -g -fsanitize=address -o "$A/cc0" "$A"/c0/*.o 2>/dev/null || { echo "ASAN cc0 link FAIL"; exit 1; }
gcc -g -fsanitize=address -o "$A/cc1" "$A"/c1/*.o 2>/dev/null || { echo "ASAN cc1 link FAIL"; exit 1; }
export ASAN_OPTIONS=detect_leaks=0:abort_on_error=0
T=$(mktemp -d); trap 'rm -rf "$A" "$T"' EXIT
bad=0; known=0
# A report whose top frame is `genadr' is the KNOWN ramode[NONE] over-read
# (a real but separately-tracked cc1 regalloc gap); count it but do NOT fail the gate.
# Any OTHER AddressSanitizer report is a NEW memory bug and fails the gate.
classify() { # $1=label $2=asan-output  -> increments bad (new) or known (genadr)
  echo "$2" | grep -q 'AddressSanitizer:' || return 0
  if echo "$2" | grep -q 'in genadr '; then known=$((known+1));
  else echo "  NEW ASAN: $1"; echo "$2" | grep -m1 'AddressSanitizer:' | sed 's/^/    /'; bad=$((bad+1)); fi
}
chk() { # $1=label  (compiles $T/f.c; classifies cc0/cc1 ASAN reports)
  classify "cc0 $1" "$("$A/cc0" $VAR "$T/f.c" "$T/z0" ${2:+-I"$2"} 2>&1)"
  [ -s "$T/z0" ] || return 0
  classify "cc1 $1" "$("$A/cc1" $VAR "$T/z0" "$T/z1" 2>&1)"
  return 0   # never let chk's last test trip `set -e' at the call site
}
echo "--- fuzzer corpus ($N seeds x 11 generators) ---"
PRE='#define U16 unsigned
#define U32 unsigned long
#define I16 int
#define I32 long
#define I8 char
'
for g in gen_global gen gen_arr gen_struct gen_call gen_mix gen_signed gen_i32 gen_char gen_ctrl gen_torture gen_switch gen_bitfield gen_funcptr gen_strptr gen_2darr gen_ctrl2 gen_pressure; do
  i=0; while [ $i -lt $N ]; do
    if python3 "$HERE/difftest/$g.py" $i > "$T/b.c" 2>/dev/null; then
      { printf '%s' "$PRE"; cat "$T/b.c"; } > "$T/f.c"; chk "$g/$i"
    fi; i=$((i+1)); done
done
echo "--- real userland (cmd/*.c) ---"
if [ -d "$CMD" ]; then
  for f in "$CMD"/*.c; do cp "$f" "$T/f.c"; chk "$(basename "$f")" "$UINC"; done
else echo "  (userland tree $CMD not present -- skipped)"; fi
echo "=== ASAN front-end sweep: $bad NEW error(s), $known known (genadr ramode[NONE]) ==="
[ $bad = 0 ] && echo "=== CLEAN (no new memory errors) ===" || echo "=== NEW MEMORY ERRORS FOUND ==="
exit $bad
