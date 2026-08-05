#!/bin/sh
# runner.sh -- print the path of the Z8001 guest runner, or fail legibly.
#
# The runner executes a linked l.out on the host: real Z8001 CPU, syscalls
# emulated against the host filesystem.  It is how a compiler test RUNS the code
# it just compiled, so most of tests/ needs it and nothing in src/ does.
#
# This is the C emulator (commodore-900-emulator, `c900 --exec`).  It replaced a
# Go program that reached into two sibling simulator checkouts for a decoder --
# a dependency this repository should not have, and a POSITIONAL one, so it broke
# whenever the checkout moved.  Hence the search ends in an error naming the
# variable to set, rather than in another guess about directory layout.
#
# Resolution order (host/deps.sh holds it, with every other edge of this
# repository):
#   $C900_EMU        explicit, wins
#   deps/commodore-900-emulator/bin/c900   the release `make deps' unpacks
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
