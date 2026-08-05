#!/bin/sh
# build-ld.sh - host-build the Coherent Z8001 linker for the test
# toolchain (links n.out objects from as + cc2 into an l.out executable the
# sim runs).  Sources FROM src/ld (the native source of record, which carries
# the baked eq() 16-char-symbol and calloc(1,n) fixes).  Unity build via all.c.
# Host-port shims applied to the scratch copy:
#   - BREADBOX=0: skip the in-memory-output optimization that pokes Coherent stdio
#     internals (FILE._cc/_cp/_pt); use plain fopen output instead.
#   - types.h shim (Coherent fs types the dir/ar/stat headers need; host size_t).
#   - host <sys/stat.h> for stat.h.
#   - setoutput(): forward decl made static to match the static definition.
#   - canon.c: _canw/_canl byte-swap host LE <-> Z8000 BE (shared with build-as.sh).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
LD="$HERE/../src/ld"     		# native source of record (baked: eq() 16-char fix, calloc(1,n))
. "$HERE/publish.sh"				# $BUILD, stagedir, publish_dir/_file
. "$HERE/srcman.sh"				# srcman_list, srcman_check
# What the linker is made of is src/ld/all.c's include list -- the unity build
# IS the declaration.  Only all.c is compiled below, so a .c under src/ld that
# all.c does not include would be copied in and never built: refused by name
# here rather than reading as source that is part of the linker.
srcman_check ld "$LD" || exit 2
OUT=$(stagedir ld)
trap 'rm -rf "$OUT"' EXIT INT TERM
for f in $(srcman_list ld "$LD"); do cp "$LD/$f" "$OUT"/; done
cp "$LD"/*.h "$OUT"/
# headers from host/include (vendored verbatim); ar.h includes <sys/dir.h>
for h in canon.h mtype.h ar.h; do
  cp "$HERE/include/$h" "$OUT"/
done
mkdir -p "$OUT/sys"; cp "$HERE/include/sys/dir.h" "$OUT/sys/dir.h"
# canon.c + n.out.h come PATCHED from the as build (PDP-canonical fields,
# exact-width packed on-file structs) -- run build-as.sh first.
cp "$BUILD/as/canon.c" "$BUILD/as/n.out.h" "$OUT"/

# ar.h exact-width: the donor's time_t/size_t fields are 8 bytes on the host,
# which would widen ar_hdr/ar_sym past the native archive layout (ar_hdr 28 B,
# ar_sym 20 B).  Same treatment as n.out.h; mkarz shares this header.
python3 - "$OUT/ar.h" <<'PY'
import sys
f = sys.argv[1]; s = open(f).read()
for old, new in (("time_t\tar_date", "int\tar_date"),
                 ("fsize_t\tar_size", "unsigned int\tar_size"),
                 ("fsize_t\tar_off", "unsigned int\tar_off")):
    assert s.count(old) == 1, old
    s = s.replace(old, new)
s = ("#pragma pack(2)\n" + s.rstrip() + "\n#pragma pack()\n")
open(f, "w").write(s)
print("ar.h: exact-width native layout (ar_hdr 28 B, ar_sym 20 B)")
PY

# Use the HOST <sys/stat.h>: ld fstat()s input files, and the host fstat writes a
# host-sized struct stat -- the small Coherent struct stat overflowed (stack smash).
# Host <sys/types.h> also supplies ino_t/dev_t/time_t/off_t for the donor ar.h/dir.h;
# types.h adds only the Coherent-specific address types host lacks.
cat > "$OUT/stat.h" <<'EOF'
#include <sys/stat.h>
EOF
cat > "$OUT/types.h" <<'EOF'
#ifndef TYPES_H
#define TYPES_H TYPES_H
#include <sys/types.h>
typedef unsigned saddr_t; typedef unsigned long vaddr_t; typedef long ctime_t;
typedef long fsize_t;
#define FSIZE_T_DEFINED
#endif
EOF
sed -i 's/^FILE\t\*setoutput();/static FILE *setoutput();/' "$OUT/main.c"
# MWC printf %D = 32-bit decimal (pre-%ld); glibc printf mis-consumes it and
# faults on the following %s (seen in the -L lfixup path).  Args are longs.
sed -i 's/%D/%ld/g' "$OUT/pass1.c" "$OUT/pass2.c" "$OUT/main.c"

# baked-fix drift guards: the source of record must carry the genuine fixes
grep -q "all NCPLN chars matched" "$OUT/pass1.c" || { echo "src/ld pass1.c: eq() 16-char fix MISSING"; exit 1; }
grep -q "calloc(1, sizeof(\*mp))" "$OUT/pass1.c" || { echo "src/ld pass1.c: calloc(1,n) fix MISSING"; exit 1; }
sed -i 's/^void\tmessage(), fatal.*/void message(char*,...),fatal(char*,...),usage(char*,...),filemsg(char*,char*,...),modmsg(char*,char*,char*,...),mpmsg(mod_t*,char*,...),spmsg(sym_t*,char*,...);/' "$OUT/data.h"

# message.c uses Coherent's old-style varargs (callers pass &args as a fake va_list)
# + a recursive %r printf format -- both broken on x86-64 (args are in registers).
# Replace with real <stdarg.h>: each message fn builds its prefix directly and a
# mini vrender() handles the %s/%.*s/%d/%lo/%x/%c subset ld uses (no %r nesting).
cat > "$OUT/message.c" <<'MSGEOF'
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
static void vrender(FILE *f, char *fmt, va_list ap) {
	for (; *fmt; fmt++) {
		int zero=0,width=0,prec=-1,star=0,lng=0,c; char nbuf[96],spec[16],*sp;
		if (*fmt!='%') { putc(*fmt,f); continue; }
		fmt++;
		while (*fmt=='-'||*fmt=='+'||*fmt==' '||*fmt=='#'||*fmt=='0'){ if(*fmt=='0')zero=1; fmt++; }
		while (*fmt>='0'&&*fmt<='9') width=width*10+(*fmt++ - '0');
		if (*fmt=='.'){ fmt++; if(*fmt=='*'){star=1;fmt++;} else { prec=0; while(*fmt>='0'&&*fmt<='9') prec=prec*10+(*fmt++ -'0'); } }
		while (*fmt=='l'||*fmt=='h'){ if(*fmt=='l')lng=1; fmt++; }
		c=*fmt;
		if (c=='s'){ int p= star? va_arg(ap,int): prec; char *s=va_arg(ap,char*); if(p<0) fputs(s,f); else { int i; for(i=0;i<p&&s[i];i++) putc(s[i],f); } }
		else if (c=='d'||c=='u'||c=='o'||c=='x'){ sp=spec; *sp++='%'; if(zero)*sp++='0'; if(width){sprintf(sp,"%d",width); sp+=strlen(sp);} if(lng)*sp++='l'; *sp++=(char)c; *sp=0; if(lng) sprintf(nbuf,spec,va_arg(ap,long)); else sprintf(nbuf,spec,va_arg(ap,int)); fputs(nbuf,f); }
		else if (c=='c') putc(va_arg(ap,int),f);
		else if (c=='r'){ char *nf=va_arg(ap,char*); vrender(f,nf,ap); }
		else if (c=='%') putc('%',f);
		else { putc('%',f); putc((char)c,f); }
	}
}
void message(char *fmt, ...){ va_list ap; va_start(ap,fmt); fputs("Ld: ",stderr); vrender(stderr,fmt,ap); fputc('\n',stderr); va_end(ap); }
void fatal(char *fmt, ...){ va_list ap; va_start(ap,fmt); fputs("Ld: ",stderr); vrender(stderr,fmt,ap); fputc('\n',stderr); va_end(ap); exit(1); }
void usage(char *fmt, ...){ va_list ap; va_start(ap,fmt); fputs("Ld: ",stderr); vrender(stderr,fmt,ap);
	fputs("\nUsage: ld [-d][-e entry][-i][-l<name>][-m][-n][-o file][-r][-s][-u sym][-x] file ...\n",stderr); va_end(ap); exit(1); }
void filemsg(char *fname, char *fmt, ...){ va_list ap; va_start(ap,fmt); fprintf(stderr,"Ld: file %s: ",fname); vrender(stderr,fmt,ap); fputc('\n',stderr); va_end(ap); }
void modmsg(char *fname, char mname[], char *fmt, ...){ va_list ap; va_start(ap,fmt); fprintf(stderr,"Ld: file %s: ",fname); if(mname[0]) fprintf(stderr,"module %.16s: ",mname); vrender(stderr,fmt,ap); fputc('\n',stderr); va_end(ap); }
void mpmsg(mod_t *mp, char *fmt, ...){ va_list ap; va_start(ap,fmt); fprintf(stderr,"Ld: file %s: ",mp->fname?mp->fname:"?"); if(mp->mname[0]) fprintf(stderr,"module %.16s: ",mp->mname); vrender(stderr,fmt,ap); fputc('\n',stderr); va_end(ap); }
void spmsg(sym_t *sp, char *fmt, ...){ va_list ap; va_start(ap,fmt); fprintf(stderr,"Ld: symbol %.16s: ",sp->s.ls_id); vrender(stderr,fmt,ap); fputc('\n',stderr); va_end(ap); }
MSGEOF

cd "$OUT"
gcc -std=gnu89 -w -DBREADBOX=0 -D_Z8001 -c -I. all.c
gcc -std=gnu89 -w -DBREADBOX=0 -D_Z8001 -c -I. canon.c
gcc -std=gnu89 -w -DBREADBOX=0 -o "$OUT/ld-z8001" all.o canon.o
echo "ld-z8001: LINKED ($(wc -c < "$OUT/ld-z8001") B)"

publish_dir ld
trap - EXIT INT TERM				# $OUT is published now
publish_file "$OUT/ld-z8001" ld-z8001
