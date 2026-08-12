#!/bin/sh
# Legacy wrapper; delegates to build-cc.sh.
exec "$(dirname "$0")/build-cc.sh" "$@"
