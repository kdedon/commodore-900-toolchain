#!/bin/sh
# n2run.sh - run one target binary from build/selfhost under the n2z8001
# guest-exec harness, with the selfhost fake root (/usr/include, /work) mapped.
#     n2run.sh BIN ARGS...
HERE=$(cd "$(dirname "$0")" && pwd)
SH="$HERE/build/selfhost"
: "${N2:?set N2 to the n2z8001 simulator binary}"
bin="$SH/$1"; shift
N2ROOT="$SH/root" exec "$N2" -runexec "$bin" "$@"
