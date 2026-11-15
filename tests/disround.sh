#!/bin/sh
# disround.sh -- every instruction form as-z8001 writes, through loutdis and
# back to the same bytes (tests/disround.py).
H="$(cd "$(dirname "$0")/.." && pwd)"
B="${C900_TC_BUILD:-$H/host/build}"
AS="$B/as-z8001"
DIS="$B/tools/loutdis"
[ -x "$AS" ] || { echo "disround: as-z8001 not built"; exit 2; }
[ -x "$DIS" ] || { echo "disround: loutdis not built"; exit 2; }
exec python3 "$H/tests/disround.py" "$AS" "$DIS"
