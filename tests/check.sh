#!/bin/sh
# check.sh - one-shot build + test driver for the Z8001 backend, so the whole
# edit->build->test loop is a SINGLE command (one approval / allowlist entry).
#
# Usage:
#   tests/check.sh                      build cc1 + n2, run the full regression
#   tests/check.sh -q                   quick: skip cc1 rebuild, just n2 + regression
#   tests/check.sh probe '<C src>' A B WANT   build, run snippet f(A,B), assert ==WANT
#   tests/check.sh dis   '<C src>'      build, disassemble cc2's object for a snippet
#   tests/check.sh run   '<C src>' A B  build, run snippet f(A,B), print the result
#
# Env: VAR (variant flags, default VLARGE 800000000800), N2 (guest runner, default: host/runner.sh).
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)            # repo root
B="${C900_BUILD:-$HERE/host/build}"	# the lane's build dir; see host/publish.sh
O="$B/z8001"
VAR=${VAR:-800000000800}
N2=${N2:-"$(sh "$(cd "$(dirname "$0")/../host" && pwd)/runner.sh")"}

build_cc1() { ( cd "$HERE/host" && bash build-cc.sh >/tmp/check_cc1.log 2>&1 ) \
  && grep -q 'cc1-z8001: LINKED' /tmp/check_cc1.log \
  || { echo "cc1 build FAILED:"; grep -iE 'CC ERR|link FAILED|error' /tmp/check_cc1.log | head; exit 1; }; }
# The gates EXECUTE code, so a guest runner is required.  It generates nothing: it
# loads a LINKED l.out (from cc2-z8001 + ld) and runs it.  host/runner.sh resolves
# it; there is nothing to build here, which is the point of moving off the Go one.
build_n2()  { [ -x "$N2" ] \
  || { echo "no guest runner at '$N2' -- set C900_EMU (see host/runner.sh)"; exit 1; }; }

# multi-segment coverage: exercise NONZERO segments the single-segment path cannot
# reach; tests/multiseg-text.sh covers the same ground through the shipped pipeline.
run_multiseg() { N2="$N2" sh "$HERE/tests/multiseg-text.sh" >/tmp/check_seg.log 2>&1 \
  && echo "=== multiseg: PASS ===" || { echo "=== multiseg: FAIL ==="; cat /tmp/check_seg.log; exit 1; }; }

# link the .z1 through cc2 + ld and run f(A,B); echoes the signed 16-bit result.
runsnip() { # <z1> A B
  "$O/cc2-z8001" 0010 "$1" /tmp/chk.o /tmp/chk.scr 0 2>/dev/null || { echo "CC2-FAIL"; return 1; }
  printf '\t.globl\tSS\nSS = 0\n' > /tmp/chk_ss.s
  "$B/as-z8001" -o /tmp/chk_ss.o /tmp/chk_ss.s 2>/dev/null
  "$B/ld-z8001" -R 0x200 -e f_ -o /tmp/chk.out /tmp/chk.o /tmp/chk_ss.o 2>/dev/null \
    || { echo "LD-FAIL"; return 1; }
  "$N2" -runobjint /tmp/chk.out "$2" "$3" 2>/dev/null | grep -oE 'signed -?[0-9]+' | grep -oE '\-?[0-9]+'
}

# compile a C snippet through cc0 -> cc1 -> (n2 IR). echoes the .z1 path or fails.
compile() { printf '%s\n' "$1" > /tmp/chk.c
  "$O/cc0-z8001" $VAR /tmp/chk.c /tmp/chk.z0 2>/dev/null || { echo "CC0-SEGV"; return 1; }
  e=$("$O/cc1-z8001" $VAR /tmp/chk.z0 /tmp/chk.z1 2>&1); [ -z "$e" ] || { echo "CC1-ICE: $e"; return 1; }
  echo /tmp/chk.z1; }

# The gate set.  Every one of these reads cc2-z8001's own object -- compiled, linked and
# executed -- so what `check.sh' covers is the backend that ships, end to end.
run_gates() {
  N2="$N2" sh "$HERE/tests/regress.sh"                 || return 1
  N2="$N2" sh "$HERE/tests/objsweep.sh"                || return 1
  N2="$N2" sh "$HERE/tests/obj-reloc.sh"               || return 1
  N2="$N2" sh "$HERE/tests/cc2run.sh"                  || return 1
  N2="$N2" sh "$HERE/tests/segrun.sh"                  || return 1
  N2="$N2" sh "$HERE/tests/regclob.sh"                 || return 1
  run_multiseg
}

cmd=${1:-all}
case "$cmd" in
  -q|quick)   build_n2; run_gates ;;
  all|"")     build_cc1; build_n2; run_gates ;;
  probe)      build_cc1; build_n2
              z1=$(compile "$2") || { echo "[probe] $z1"; exit 1; }
              g=$(runsnip "$z1" "$3" "$4") || { echo "$g"; exit 1; }
              [ "$g" = "$5" ] && echo "PASS = $g" || { echo "FAIL = $g (want $5)"; exit 1; } ;;
  run)        build_cc1; build_n2
              z1=$(compile "$2") || { echo "$z1"; exit 1; }
              runsnip "$z1" "${3:-0}" "${4:-0}" ;;
  dis)        build_cc1; build_n2
              z1=$(compile "$2") || { echo "$z1"; exit 1; }
              "$O/cc2-z8001" 0010 "$z1" /tmp/chk.o /tmp/chk.scr 0 || { echo "cc2 FAILED"; exit 1; }
              "$(sh "$HERE/host/loutdis.sh")" -v /tmp/chk.o ;;
  *) echo "unknown: $cmd (see header)"; exit 2 ;;
esac
