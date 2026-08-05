#!/bin/sh
# SUPERSEDED (consolidation stage 3): the Z8001 compiler builds from the native
# source of record src/cc via build-cc.sh (tabgen + tables + cc0/cc1/cc2 in
# one pass).  This wrapper remains so older docs/invocations keep working.
exec "$(dirname "$0")/build-cc.sh" "$@"
