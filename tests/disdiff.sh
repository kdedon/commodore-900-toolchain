#!/bin/bash
# disdiff.sh <util> [-at 0xADDR ...]
#
# Per-function codegen differential: compare OUR backend's output for a
# Coherent userland source against the ORIGINAL stripped Z8000 binary that the
# original (un-runnable) compiler produced.  Both sides are disassembled by the
# SAME decoder (loutdis -> cpu.Decode), so mnemonics line up.
#
# The originals carry no symbols, so functions are split by the FP-setup prologue
# (`LD R13,R15') and identified by ADDRESS; match ours (named, in source order)
# to theirs by hand using the two tables, then drill in with `-at'.
#
#   tests/disdiff.sh cat                 # print both per-function tables
#   tests/disdiff.sh cat -at 0x030e      # disassemble the original func at 0x030e
#   tests/disdiff.sh cat -ours 0x18      # disassemble OUR func at 0x18
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
. "$(dirname "$0")/donor.sh"
B="${C900_BUILD:-$HERE/host/build}"	# the lane's build dir; see host/publish.sh
O="$B/z8001"; VAR=800000000800
CMD="$Z8001_DONOR/cmd"; INC="$Z8001_DONOR/include"
BIN="${ORIG_BIN:-$Z8001_DONOR/bin}"
LD=$(sh "$(cd "$(dirname "$0")/.." && pwd)/host/loutdis.sh"); PEEP="${PEEP:-0010}"
util=$1; shift || true

src="$CMD/$util.c"; orig="$BIN/$util"
[ -f "$src" ]  || { echo "no source $src"; exit 1; }
# build OUR object
"$O/cc0-z8001" $VAR "$src" /tmp/dd.z0 -I"$INC" 2>/dev/null
"$O/cc1-z8001" $VAR /tmp/dd.z0 /tmp/dd.z1 2>/dev/null
"$O/cc2-z8001" $PEEP /tmp/dd.z1 /tmp/dd.nout /tmp/dd.scr 0 2>/dev/null

case "$1" in
  -at)    exec "$LD" -at "$2" "$orig" ;;
  -ours)  exec "$LD" -at "$2" /tmp/dd.nout ;;
  # -dump: per-instruction disassembly of OURS, by the same decoder that reads the
  # originals -- so the two sides of the differential are rendered identically.
  -dump)  exec "$LD" -v /tmp/dd.nout ;;
esac

echo "########## OURS: $util.c ##########"
"$LD" -funcs /tmp/dd.nout
echo
echo "########## ORIGINAL (stripped): $BIN/$util ##########"
[ -f "$orig" ] && "$LD" -funcs "$orig" || echo "(no original binary $orig)"
