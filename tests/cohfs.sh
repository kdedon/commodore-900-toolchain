#!/bin/sh
# cohfs.sh -- cohfs makes the filesystem it is meant to, and reads and writes it.
#
# The tree below is built fresh on every run and is the same bytes every time,
# so the filesystem mkfs makes of it is too.  Its md5 is pinned: it is the
# image commodore-900-dist's mkimage.py wrote for the same tree when cohfs
# replaced it, and every dist that release packed came out byte-identical
# under both.  A change to the format or to the allocation order moves it.
#
# The tree is shaped at the edges: files of 10 and 11 blocks (the last direct
# address and the first indirect one), 138 and 139 (the last single-indirect
# block and the first double-indirect one), an empty file and directory, a
# hard link across directories, a name longer than a directory entry holds,
# and both manifests with a repeated line.  The partition is placed at block 7
# of an image filled with a pattern, so a write outside it shows and `parts'
# has to find a filesystem off an eight-block boundary, as hd42-coh.media's
# /usr at 44105 is.
#
# MSYS2 rewrites an argument that starts with `/' into a Windows path before a
# native program sees it, which would turn every guest path here into a host
# one.  So the rewriting is switched off, and the test runs in its own
# directory and names every host file relatively.
#
# COHFS_KEEP=<dir> leaves the tree there, to regenerate the pin from.
# COHFS=<command> tests another build of it, such as a Windows one under wine.
set -eu
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"		# $BUILD
COHFS=${COHFS:-$BUILD/tools/cohfs}
[ -x "$COHFS" ] || { echo "cohfs.sh: $COHFS is missing -- run \`make tools'" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
MSYS2_ARG_CONV_EXCL='*'; export MSYS2_ARG_CONV_EXCL
case $COHFS in /*) ;; *) COHFS=$PWD/$COHFS ;; esac
cd "$T"
PIN=8803d4c410104835f1f93ee70e2506fc

bad=0
fail() { echo "  FAIL $*"; bad=$((bad + 1)); }

# ---- the tree ----
S=stage
mkdir -p "$S/a/b/c" "$S/empty" "$S/dev/sub"
fill() { yes "cohfs $1 0123456789abcdefghijklmnopqrstuvwxyz" | head -c "$2" > "$3"; }
: > "$S/zero"
for n in 1 5120 5121 70656 70657; do fill $n $n "$S/f$n"; done
fill deep 3000 "$S/a/b/c/deep"
ln "$S/f5121" "$S/a/hardlink"
ln "$S/f5121" "$S/a/b/hl2"
echo long > "$S/averyveryverylongfilename_over14"
echo fourteen > "$S/exactly14chars"
chmod 644 "$S"/f* "$S/zero" "$S"/averyvery* "$S/exactly14chars"
chmod 755 "$S/a/b/c/deep" "$S/f1"
chmod 755 "$S" "$S/a" "$S/a/b" "$S/a/b/c" "$S/empty" "$S/dev" "$S/dev/sub"
cat > "$S/DEVICES" <<'EOF'
dev/null c 666 1 0
dev/sub/hd0 b 600 2 3 3 3
tty c 620 5 1
# a comment, and a path named twice: it keeps its place, takes the later fields
dev/null c 644 1 2
EOF
cat > "$S/MANIFEST" <<'EOF'
f1 4755 3 3
a 700 1 2
a/b/c/deep 0711 2 2
f1 600 0 0
EOF
if [ -n "${COHFS_KEEP:-}" ]; then rm -rf "$COHFS_KEEP"; cp -a "$S" "$COHFS_KEEP"; fi

# ---- mkfs ----
IMG=img
yes 'x' | tr -d '\n' | head -c $((620 * 512)) > "$IMG"
"$COHFS" mkfs -p 7 "$IMG" 600 10 "$S" > mkfs.out
grep -q '^fs@7 .* 329/600 blocks used, 20/64 inodes used$' mkfs.out ||
	fail "mkfs summary: $(cat mkfs.out)"
got=$(dd if="$IMG" bs=512 skip=7 count=600 2>/dev/null | md5sum | cut -c1-32)
[ "$got" = "$PIN" ] || fail "filesystem md5 $got, pinned $PIN"
outside=$( (dd if="$IMG" bs=512 count=7 2>/dev/null
	    dd if="$IMG" bs=512 skip=607 2>/dev/null) | tr -d 'x' | wc -c)
[ "$outside" -eq 0 ] || fail "mkfs wrote outside its partition"
[ "$(wc -c < "$IMG")" -eq $((620 * 512)) ] || fail "mkfs changed the image's size"

# ---- reading back ----
[ "$("$COHFS" parts "$IMG")" = "7 600 10 271 44" ] || fail "parts: $("$COHFS" parts "$IMG")"
[ "$("$COHFS" parts -p 7 "$IMG")" = "7 600 10 271 44" ] || fail "parts -p 7"
"$COHFS" parts -p 8 "$IMG" > /dev/null 2>&1 && fail "parts -p 8 found a filesystem"
for f in zero f1 f5120 f5121 f70656 f70657 a/b/c/deep a/hardlink a/b/hl2 exactly14chars; do
	"$COHFS" cat "$IMG" "/$f" | cmp -s - "$S/$f" || fail "cat /$f"
done
"$COHFS" ls -p 7 "$IMG" / > ls
ino() { awk -v n="$1" '$4 == n { print $3 }' "$2"; }
"$COHFS" ls -p 7 "$IMG" /a > lsa
[ "$(ino f5121 ls)" = "$(ino hardlink lsa)" ] || fail "hard link is two inodes"
grep -q '^100600 .* f1$' ls || fail "MANIFEST's later line for f1"
grep -q '^ 40700 .* a$' ls || fail "MANIFEST mode for a/"
grep -q ' averyveryveryl$' ls || fail "long name not cut at 14"
"$COHFS" cat "$IMG" /nonexistent 2>/dev/null && fail "cat of a missing path succeeded"
"$COHFS" find "$IMG" / > find
[ "$(wc -l < find)" -eq 21 ] || fail "find: $(wc -l < find) names, not 21"
grep -q '^40755 6 0 1 224 2 - /$' find || fail "find: the root"
grep -q '^100644 3 0 1 5121 [0-9]* - /a/hardlink$' find || fail "find: the hard link"
grep -q '^20620 1 0 1 0 [0-9]* 5,1 /tty$' find || fail "find: tty"
grep -q '^20644 1 0 1 0 [0-9]* 1,2 /dev/null$' find || fail "find: /dev/null"
grep -q '^60600 1 3 3 0 [0-9]* 2,3 /dev/sub/hd0$' find || fail "find: /dev/sub/hd0"
[ "$("$COHFS" blocks "$IMG" /f5121 | wc -l)" -eq 11 ] || fail "blocks of an 11-block file"
[ "$("$COHFS" blocks "$IMG" /f70657 | wc -l)" -eq 139 ] || fail "blocks of a 139-block file"

# ---- put ----
fill new 90000 big
"$COHFS" put -p 7 "$IMG" big /f5120 "$S/f5121" /empty/created > /dev/null
"$COHFS" put -p 7 -m 4711 "$IMG" "$S/f1" /a/b/c/deep "$S/f1" /rootfile > /dev/null
"$COHFS" cat "$IMG" /f5120 | cmp -s - big || fail "put replace, double indirect"
"$COHFS" cat "$IMG" /empty/created | cmp -s - "$S/f5121" || fail "put create"
"$COHFS" cat "$IMG" /rootfile | cmp -s - "$S/f1" || fail "put create at the root"
"$COHFS" ls "$IMG" /a/b/c/deep | grep -q '^104711 ' || fail "put -m on a replace"
"$COHFS" ls "$IMG" /rootfile | grep -q '^104711 ' || fail "put -m on a create"
"$COHFS" ls "$IMG" /f1 | grep -q '^100600 ' || fail "put without -m kept f1's mode"

# ---- refusals ----
: > small
"$COHFS" mkfs -p 0 small 160 4 "$S" > /dev/null 2> err && fail "mkfs overfilled"
grep -q 'filesystem full at block 160' err || fail "full: $(cat err)"
"$COHFS" mkfs -p 0 small 1000 3 "$S" > /dev/null 2> err && fail "mkfs ran out of inodes"
grep -q 'out of inodes' err || fail "inodes: $(cat err)"

if [ $bad -ne 0 ]; then
	echo "cohfs.sh: $bad check(s) failed"
	exit 1
fi
echo "cohfs.sh: mkfs matches its pin; ls, cat, find, blocks, put, parts and the refusals hold"
