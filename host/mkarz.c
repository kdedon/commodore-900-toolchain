/* Minimal Coherent l.out archive writer: ARMAG magic + [ar_hdr + member]...
 * No __.SYMDEF (ld does the linear member scan for non-ranlib archives). */
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include "n.out.h"
#include "ar.h"
#include "canon.h"

int main(argc, argv) int argc; char **argv; {
	FILE *out, *m; int i; unsigned short magic; long sz; size_t n; char buf[8192];
	struct ar_hdr h; char *base;
	if (argc < 3) { fprintf(stderr, "usage: mkarz out.a obj...\n"); return 2; }
	if ((out = fopen(argv[1], "wb")) == NULL) { perror(argv[1]); return 1; }
	magic = ARMAG; canshort(magic);
	fwrite(&magic, sizeof magic, 1, out);
	for (i = 2; i < argc; i++) {
		if ((m = fopen(argv[i], "rb")) == NULL) { perror(argv[i]); return 1; }
		fseek(m, 0L, SEEK_END); sz = ftell(m); fseek(m, 0L, SEEK_SET);
		memset(&h, 0, sizeof h);
		base = strrchr(argv[i], '/'); base = base ? base + 1 : argv[i];
		strncpy(h.ar_name, base, DIRSIZ);
		h.ar_date = 0; cantime(h.ar_date);
		h.ar_size = sz; cansize(h.ar_size);
		fwrite(&h, sizeof h, 1, out);
		while ((n = fread(buf, 1, sizeof buf, m)) > 0) fwrite(buf, 1, n, out);
		fclose(m);
	}
	fclose(out);
	return 0;
}
