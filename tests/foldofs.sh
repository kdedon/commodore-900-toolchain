#!/bin/sh
# foldofs.sh -- a constant field offset on a far pointer belongs in the
# Z8000 base-displacement operand, not in an ADD of its own.
#
# Loads and stores address `k(RRn)'; only arithmetic, compare, inc-dec and
# bit-field ops must build p + k first.  A CONVERT or CAST between the deref
# and its user is transparent.  Each case checks the shape and runs.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"; CC1="$BUILD/z8001/cc1-z8001"
CC2="$BUILD/z8001/cc2-z8001"; DIS="$BUILD/tools/loutdis"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/f.c" <<'EOF'
struct s { int a; int b; long c; char d; char e; int f; };
long gl; int gi; char gc;
ld_int(p)  struct s *p; { gi = p->f; }
st_int(p)  struct s *p; { p->f = gi; }
ld_long(p) struct s *p; { gl = p->c; }
st_long(p) struct s *p; { p->c = gl; }
ld_byte(p) struct s *p; { gc = p->e; }
st_byte(p) struct s *p; { p->e = gc; }
wide_byte(p) struct s *p; { gi = p->e; }	/* CONVERT between deref and store */
wide_int(p)  struct s *p; { gl = p->b; }	/* ... widening to long */
add_int(p)   struct s *p; { gi = p->f + 1; }	/* ADD: no memory displacement form */
inc_fld(p)   struct s *p; { p->f++; }		/* inc-dec addresses memory itself */
zero_st(p)   struct s *p; { p->f = 0; }		/* CLR has no displacement form */
struct n { int first; int second; };
struct h { int pad; struct n *a[4]; };
cmp_elt(h, m, i) struct h *h; int *m; int i; { if (m == &h->a[i]->first) return 1; return 0; }
lt_elt(h, m, i) struct h *h; int *m; int i; { if (m < &h->a[i]->first) return 1; return 0; }
tst_elt(h, i) struct h *h; int i; { if (&h->a[i]->first) return 1; return 0; }
not_elt(h, i) struct h *h; int i; { return !&h->a[i]->first; }
struct fh { char type; char wide; };
struct fnt { struct fh head; int x; };
struct w { char pad[0xF0]; struct fnt *font; int bw; };
mul_hd(p) struct w *p; { gi = p->font->head.wide * 5; }	/* head at 0: &* cancels */
ld_hd(p) struct w *p; { gi = p->font->head.wide; }
EOF
"$CC0" $VAR "$T/f.c" "$T/f.z0" && "$CC1" $VAR "$T/f.z0" "$T/f.z1" &&
"$CC2" 0012 "$T/f.z1" "$T/f.o" "$T/f.scr" 0 || { echo "  foldofs: compile FAIL"; exit 1; }

# Folded: a displacement off the loaded pair, no ADD/INC.

shape() { # <fn> <want-folded 1|0>
	d=$("$DIS" -v -fn "$1" "$T/f.o" 2>/dev/null)
	got=1
	printf '%s\n' "$d" | grep -Eq '^\s+[0-9a-f]+:\s+(INC|ADD|ADDL)\s+RR?1[01]' && got=0
	printf '%s\n' "$d" | grep -Eq '0x[0-9A-F]{4}\(R10\)' || got=0
	if [ "$got" = "$2" ]; then
		printf '  %-14s %s PASS\n' "$1" "$([ "$2" = 1 ] && echo folded || echo materialized)"
	else
		printf '  %-14s want=%s got=%s FAIL\n' "$1" "$2" "$got"
		printf '%s\n' "$d" | sed 's/^/      /'
		fail=1
	fi
}
for f in ld_int st_int ld_long st_long ld_byte st_byte wide_byte wide_int; do
	shape "${f}_" 1
done
shape add_int_ 0
shape inc_fld_ 0
shape zero_st_ 0

# `p->font->head.wide', with `head' at offset 0: the font pointer's deref was
# marked as the base load before `&*' re-parented it under the field-address
# ADD, and it is still a load, LDL RRn,0x00F0(RRn).
for f in mul_hd_ ld_hd_; do
	d=$("$DIS" -v -fn "$f" "$T/f.o" 2>/dev/null)
	if printf '%s\n' "$d" | grep -Eq ':\s+LDL\s+RR10,0x00F0\(R10\)' &&
	   ! printf '%s\n' "$d" | grep -Eq ':\s+ADD\s+R11,#0x00F0'; then
		printf '  %-14s folded base PASS\n' "$f"
	else
		printf '  %-14s FAIL: base load not folded\n' "$f"
		printf '%s\n' "$d" | sed 's/^/      /'
		fail=1
	fi
done

# `&h->a[i]->first', with `first' at offset 0, is the loaded a[i]: the deref was
# marked as a base load before `&*' cancelled it into a compare operand.  The
# compare must be the last instruction before its branch -- a displacement
# stepped back off the pair after the CP would set the flags the branch reads.
for f in cmp_elt_ lt_elt_ tst_elt_ not_elt_; do
	d=$("$DIS" -v -fn "$f" "$T/f.o" 2>/dev/null)
	last=$(printf '%s\n' "$d" | grep -E '^\s+[0-9a-f]+:' | grep -B1 -m1 -E ':\s+JR\s' | head -1)
	if printf '%s\n' "$last" | grep -Eq ':\s+(CP|TEST)L?\s'; then
		printf '  %-14s compare feeds the branch PASS\n' "$f"
	else
		printf '  %-14s FAIL: [%s] before the branch\n' "$f" "$last"
		printf '%s\n' "$d" | sed 's/^/      /'
		fail=1
	fi
done

# ... and the values the folded operands read and write.
[ -n "$N2" ] || { echo "  foldofs: no guest runner"; exit 2; }
cat > "$T/r.c" <<'EOF'
#include <stdio.h>
struct s { int a; int b; long c; char d; char e; int f; };
struct s v;
struct n { int first; int second; };
struct h { int pad; struct n *a[4]; };
struct n n0, n1;
struct h hh;
eq(h, m, i) struct h *h; int *m; int i; { if (m == &h->a[i]->first) return 1; return 0; }
lt(h, m, i) struct h *h; int *m; int i; { if (m < &h->a[i]->first) return 1; return 0; }
tst(h, i) struct h *h; int i; { if (&h->a[i]->first) return 1; return 0; }
struct n nn[2];
struct fh { char type; char wide; };
struct fnt { struct fh head; int x; };
struct w { char pad[0xF0]; struct fnt *font; int bw; };
struct fnt ft;
struct w ww;
mul(p) struct w *p; { return p->font->head.wide * 5; }
main() {
	struct s *p; long l;
	hh.a[0] = &n0; hh.a[1] = &n1; hh.a[2] = 0; hh.a[3] = &nn[1];
	ft.head.wide = 7; ww.font = &ft;
	p = &v;
	v.a = 1; v.b = -2; v.c = 0x12345678L; v.d = 3; v.e = -4; v.f = 5;
	p->f = p->f + 100;
	p->c = p->c + 1;
	p->e = 9;
	l = p->b;
	printf("%d %ld %d %d %ld %d%d%d%d\n", p->f, p->c, p->e, (int)p->d, l,
	    eq(&hh, &n0.first, 0), eq(&hh, &n1.first, 0),
	    eq(&hh, &n1.first, 1), eq(&hh, &n0.first, 1));
	printf("%d%d%d%d %d\n", lt(&hh, &nn[0].first, 3), lt(&hh, &nn[1].first, 3),
	    tst(&hh, 1), tst(&hh, 2), mul(&ww));
}
EOF
"$CCZ" -o "$T/r" "$T/r.c" >/dev/null 2>&1 || { echo "  foldofs: link FAIL"; exit 1; }
got=$("$N2" -runexec "$T/r" 2>/dev/null) || true
want="105 305419897 9 3 -2 1010
1010 35"
if [ "$got" = "$want" ]; then
	echo "  values         PASS"
else
	echo "  values         FAIL got=[$got] want=[$want]"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== foldofs: FAIL ==="; exit 1; }
echo "=== foldofs: PASS ==="
