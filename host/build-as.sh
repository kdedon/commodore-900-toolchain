#!/bin/sh
# build-as.sh - host-build the Coherent Z8001 assembler for the test toolchain
# (assembles libc/crt soft-float etc. -> n.out objects the mini-linker loads).
# Sources FROM src/as (the native source of record), which carries the baked
# genuine fixes: the machine.c corruption reconstruction (S_POP end/S_PUSH/S_LDM;
# memory cmd-as-machinec-corruption) and the asmout.c outrw/outrl outchk
# reservation fix.  Host-port shims applied to the scratch copy here:
#   - getline -> asgetline, asm() -> asmline()  (host keyword/POSIX collisions);
#   - shim <types.h> (Coherent size_t==long collides with host); canon.c
#     (_canw/_canl: host <-> PDP-canonical); n.out.h exact-width packed on-file
#     structs so host output is the NATIVE l.out layout.
# Object-format headers come from host/include (vendored, -D_Z8001
# selects the Z8001 branches of canon.h / l.out.h, as the native cc0 predefines).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
AS="$HERE/../src/as"
. "$HERE/publish.sh"				# $BUILD, stagedir, publish_dir/_file
. "$HERE/srcman.sh"				# srcman_list, srcman_check
# What the assembler is made of is src/as/run's $SRC/$MDSRC (the NATIVE build's
# lists), read here so both builds compile one list and a .c under src/as that
# neither names is refused by name instead of linked into as-z8001.
srcman_check as "$AS" || exit 2
ASRC=$(srcman_list as "$AS")
OUT=$(stagedir as)
trap 'rm -rf "$OUT"' EXIT INT TERM
# The two source directories flatten into one; srcman_check refuses a basename
# used twice, which here would be one file overwriting the other.
for f in $ASRC; do cp "$AS/$f" "$OUT"/; done
cp "$AS"/*.h "$AS"/z8001/*.h "$OUT"/
# the baked fixes must be present in the source of record (drift guard)
grep -q 'case S_LDM:' "$OUT/machine.c" || { echo "src/as machine.c: S_LDM reconstruction MISSING"; exit 1; }
grep -q 'n = 7;' "$OUT/asmout.c" || { echo "src/as asmout.c: outchk reservation fix MISSING"; exit 1; }
# Object-format + machine-type headers from host/include (vendored verbatim;
# canon.h/l.out.h select their Z8001 branches via -D_Z8001, matching the native
# compiler's predefine).  The host still shims types.h + exact-width n.out.h below.
for h in n.out.h l.out.h mtype.h canon.h; do
  cp "$HERE/include/$h" "$OUT"/
done

# ---- patch 2: host collisions ----
sed -i 's/\bgetline\b/asgetline/g; s/\basm(/asmline(/g' "$OUT"/*.c

# ---- patch 3a: <types.h> shim (omit the host-colliding size_t/time_t) ----
cat > "$OUT/types.h" <<'EOF'
#ifndef TYPES_H
#define TYPES_H TYPES_H
#include <stddef.h>
typedef long daddr_t; typedef long paddr_t;
typedef unsigned saddr_t; typedef unsigned long vaddr_t;
#endif
EOF
# ---- patch 3b: canon.c (host <-> PDP-canonical object fields) ----
# The native ecosystem (ROM boot, kernel exec, every shipped .o/l.out/.a) is
# PDP-canonical: 16-bit fields little-endian, 32-bit fields high WORD first
# with each word little-endian.  On a little-endian host that makes canshort
# the identity and canlong a 16-bit word swap.  (Involutions: the same
# routines convert file->host on read and host->file on write.)
cat > "$OUT/canon.c" <<'EOF'
int _canw(w) int w; { return w & 0xFFFF; }
long _canl(l) long l; {
	return (long)((((unsigned long)l >> 16) & 0xFFFFUL)
	            | (((unsigned long)l & 0xFFFFUL) << 16));
}
EOF

# ---- patch 3c: n.out.h exact-width on-file structs ----
# The donor structs use `long' for 32-bit file fields; on the LP64 host that
# silently widened ldheader to 88 bytes and ldsym to 32 -- a host-only l.out
# dialect no native tool (or the ROM boot) could read.  Force the native
# layout: 4-byte `int' fields, 2-byte packing (ldheader 48, ldsym 22).
python3 - "$OUT/n.out.h" <<'PY'
import sys
f = sys.argv[1]; s = open(f).read()
for old, new in (("fsize_t\tl_ssize[NLSEG]", "int\tl_ssize[NLSEG]"),
                 ("long lu_entry", "int lu_entry"),
                 ("long lu_nhwrel", "int lu_nhwrel"),
                 ("long\tls_addr", "int\tls_addr"),
                 ("long\tn_value", "int\tn_value")):
    assert s.count(old) == 1, old
    s = s.replace(old, new)
assert s.count("#include <sys/types.h>") == 1
s = s.replace("#include <sys/types.h>", "#include <types.h>\n#pragma pack(2)")
tail = "#endif\n\n/* end of n.out.h */"
assert s.rstrip().endswith(tail)
s = s.rstrip()
s = s[:-len(tail)] + "#pragma pack()\n" + tail + "\n"
open(f, "w").write(s)
print("n.out.h: exact-width native layout (ldheader 48 B, ldsym 22 B)")
PY

# ---- compile + link ----
cd "$OUT"
# canon.c is written above, not a src/as source, so it is named alongside them.
for fc in $(for f in $ASRC; do basename "$f"; done) canon.c; do
	gcc -std=gnu89 -w -DLADDR=1 -D_Z8001 -c -I. "$fc"
done
gcc -std=gnu89 -w -o "$OUT/as-z8001" *.o
echo "as-z8001: LINKED ($(wc -c < "$OUT/as-z8001") B)"

publish_dir as
trap - EXIT INT TERM				# $OUT is published now
publish_file "$OUT/as-z8001" as-z8001
