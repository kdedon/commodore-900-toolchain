#!/bin/sh
# check-shims.sh - the host shims still match src/cc.
#
# Applies host/shims/*.patch to a pristine copy of the compiler source, at fuzz
# 0, and asserts the post-rename conditions.  This is the same call build-cc.sh
# makes, minus the build, so a shim that has stopped matching is a red gate in
# seconds rather than a compiler that quietly differs from the native one.
#
# Nothing here is skippable: the only inputs are src/cc and host/shims, both
# committed in this repository.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
. "$ROOT/host/shims.sh"

W=${TMPDIR:-/tmp}/c900-checkshims.$$
trap 'rm -rf "$W"' EXIT INT TERM
mkdir -p "$W"
cp -r "$ROOT"/src/cc/h "$ROOT"/src/cc/common "$ROOT"/src/cc/n0 "$ROOT"/src/cc/n1 \
      "$ROOT"/src/cc/n2 "$ROOT"/src/cc/n3 "$ROOT"/src/cc/coh "$W/"

shim_apply "$ROOT/host/shims" "$W" || { echo "check-shims: FAILED"; exit 1; }

# The two whole-file host ports replace a file rather than patch one, so they
# cannot half-apply -- but they can stop replacing anything at all if the file
# they stand in for is renamed upstream, and then the donor's own version builds.
[ -f "$W/common/diag.c" ] || { echo "check-shims: common/diag.c is gone; host/port/diag.c replaces nothing"; exit 1; }
[ -f "$ROOT/host/port/diag.c" ] || { echo "check-shims: host/port/diag.c is missing"; exit 1; }
[ -f "$ROOT/host/port/shellsort.c" ] || { echo "check-shims: host/port/shellsort.c is missing"; exit 1; }
[ -f "$ROOT/host/include/path.h" ] && [ -f "$ROOT/host/include/access.h" ] ||
	{ echo "check-shims: host/include/{path,access}.h are missing"; exit 1; }

echo "check-shims: OK"
