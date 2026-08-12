#!/bin/sh
# runner.sh -- print the path of the Z8001 guest runner, or fail legibly.
#
# The runner executes a linked l.out on the host: real Z8001 CPU, syscalls
# emulated against the host filesystem.  It is how a compiler test RUNS the code
# it just compiled, so most of tests/ needs it and nothing in src/ does.
#
# This is the C emulator (commodore-900-emulator, `c900 --exec`).
#
# Resolution order (host/deps.sh holds it, with every other edge of this
# repository):
#   $C900_EMU        explicit, wins
#   external/commodore-900-emulator/bin/c900   the release `make deps' unpacks
#   c900 on $PATH    the container case
#   a sibling checkout, bounded at three parents, then repos/
#
# Callers use:  N2="${N2:-$(sh "$H/host/runner.sh")}"
# so $N2 still overrides everything, which is what the A-B against the old
# runner depended on.
HERE=$(cd "$(dirname "$0")" && pwd)

p=$(sh "$HERE/deps.sh" emu)
if [ -n "$p" ]; then
	echo "$p"
	exit 0
fi

sh "$HERE/deps.sh" -n emu
exit 1
