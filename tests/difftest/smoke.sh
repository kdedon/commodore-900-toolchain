#!/bin/sh
# smoke.sh - differential-fuzzer smoke test across ALL generators.
# Compiles+runs N random programs/generator through the shipped pipeline
# (cc0->cc1->cc2->ld->execute) and through host gcc, comparing the 16-bit result.  Exits
# non-zero on ANY mismatch or pipeline error.  Deterministic (fixed seed range 0..N-1), so
# a regression is reproducible.  Run on demand or in CI; the fast unit regression
# (regress.sh) stays separate.
#   usage: tests/difftest/smoke.sh [seeds_per_generator]   (default 60)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
N=${1:-60}

# run.py needs a Z8001 guest runner: it executes the LINKED binary cc2-z8001 and
# ld produced, and generates nothing itself.  That used to be a Go program built
# here from tools/go/n2z8001, a directory this repository no longer has -- the
# runner is the C emulator now, host/runner.sh resolves it, and it takes the same
# -runobjint.  With `set -e' the dead `go build' aborted the script on its fourth
# line, so `make -C host fuzz' and `make -C host check' could not run at all.
N2=${N2:-$(sh "$ROOT/host/runner.sh")}
export N2

# GEN unset => the default gen.py (U16 expressions)
GENS="
:base
gen_ctrl.py:ctrl
gen_arr.py:arr
gen_mix.py:mix
gen_signed.py:signed
gen_i32.py:i32
gen_char.py:char
gen_call.py:call
gen_struct.py:struct
gen_global.py:global
gen_torture.py:torture
gen_switch.py:switch
gen_bitfield.py:bitfield
gen_funcptr.py:funcptr
gen_strptr.py:strptr
gen_2darr.py:2darr
gen_ctrl2.py:ctrl2
gen_pressure.py:pressure
"
rc=0
for entry in $GENS; do
  g=${entry%%:*}; lbl=${entry##*:}
  if [ -n "$g" ]; then out=$(GEN="$HERE/$g" python3 "$HERE/run.py" "$N" 2>&1 | tail -1)
  else out=$(python3 "$HERE/run.py" "$N" 2>&1 | tail -1); fi
  printf '  %-8s %s\n' "$lbl" "$out"
  echo "$out" | grep -q '0 MISMATCH, 0 pipeline-err' || rc=1
  # ... and something has to have MATCHED.  run.py's summary for zero seeds is
  # "0 match, 0 MISMATCH, 0 pipeline-err (of 0 seeds)", which satisfies the line
  # above, so `smoke.sh 0' reported ALL GREEN across eighteen generators having
  # compiled nothing.  A generator whose every seed fell out before the compare
  # reads the same way.
  echo "$out" | grep -qE '=== [1-9][0-9]* match,' || {
    printf '  %-8s %s\n' "$lbl" "NOTHING MATCHED -- the generator produced no compared seed"
    rc=1; }
done
if [ $rc = 0 ]; then echo "=== fuzz smoke: ALL GREEN ($N seeds x all generators) ==="
else echo "=== fuzz smoke: FAILURES (see above) ==="; fi
exit $rc
