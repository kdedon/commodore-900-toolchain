#!/bin/sh
# asgval.sh -- the value of an assignment through a pointer reaches the
# return register.
#
# `return *p = v' with v in a register pair is coded as a copy of v into RR0
# and a store of RR0.  cc2 repoints the store to v's pair and deletes the
# copy when RR0 is dead afterwards.  The epilogue reads the registers a
# return statement left its value in, so there the copy stays.  An int
# function returns R1 alone, and a return without a value or the end of the
# body returns nothing, so there such copies are still deleted.  Each case
# checks the shape, then every assignment-as-value form runs at each width
# with register and non-register pointers and values.
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
struct A { long x; };
extern long lim;
extern sink();
struct A *ret(pp) struct A **pp; { register struct A *a = *pp; a++; return *pp = a; }
long rt0(pp, n) long **pp; long n; { register long *p = *pp; register long v = n; return *p = v; }
struct A *jmp(pp, n) struct A **pp;
{
	register struct A *a = *pp;
	a++;
	if (n)
		return *pp = a;
	sink();
	return 0;
}
int keep(pp) struct A **pp;
{
	register struct A *a = *pp;
	a++;
	if ((long)a >= lim)
		return 0;
	return 1;
}
struct P { struct P *n; int pid; int fl; int ppid; };
extern struct P q, *self;
extern int err, rv;
extern lock(), unlock();
int keepv(req, pid)
{
	register struct P *pp;

	lock(&q);
	for (pp = q.n; pp != &q; pp = pp->n)
		if (pp->pid == pid)
			break;
	unlock(&q);
	if (pp == &q || (pp->fl & 32) == 0 || pp->ppid != self->pid) {
		err = 3;
		return;
	}
	lock(&rv);
	return (rv);
}
keepf(pp)
register struct P *pp;
{
	if (!pp->fl)
		return -1;
	lock(pp, 0);
	lock(pp);
	if (pp == self) {
		lock(10);
		if (!err)
			pp->pid = 0;
	}
}
EOF
"$CC0" $VAR "$T/f.c" "$T/f.z0" && "$CC1" $VAR "$T/f.z0" "$T/f.z1" &&
"$CC2" 0012 "$T/f.z1" "$T/f.o" "$T/f.scr" 0 || { echo "  asgval: compile FAIL"; exit 1; }
[ -x "$DIS" ] || { echo "  asgval: no $DIS"; exit 2; }

for fn in ret_ rt0_ jmp_; do
	d=$("$DIS" -v -fn $fn "$T/f.o" 2>/dev/null) || true
	if printf '%s\n' "$d" | grep -Eq 'LDL +RR0,'; then
		printf '  %-6s value copied to RR0 PASS\n' $fn
	else
		printf '  %-6s FAIL: the value never reaches RR0\n' $fn
		printf '%s\n' "$d" | sed 's/^/      /'
		fail=1
	fi
done
# An int function returns R1 alone; a return without a value, or running
# off the end, returns nothing.  There a copy of a pair to RR0 is still dead.
for fn in keep_ keepv_ keepf_; do
	d=$("$DIS" -v -fn $fn "$T/f.o" 2>/dev/null) || true
	if [ -n "$d" ] && ! printf '%s\n' "$d" | grep -q 'LDL *RR0,RR'; then
		printf '  %-6s copy to RR0 still deleted PASS\n' $fn
	else
		printf '  %-6s FAIL: a dead copy to RR0 kept\n' $fn
		printf '%s\n' "$d" | sed 's/^/      /'
		fail=1
	fi
done

[ -n "$N2" ] || { echo "  asgval: no guest runner"; exit 2; }
cat > "$T/r.c" <<'EOF'
#include <stdio.h>
struct A { long x; };
struct A arr[4];
long g_l; struct A *g_p; int g_i; char g_c; unsigned char g_u;
sink_l(x) long x; { g_l = x; }
sink_p(x) struct A *x; { g_p = x; }
sink_i(x) int x; { g_i = x; }
sink_c(x) char x; { g_c = x; }
sink_u(x) unsigned char x; { g_u = x; }

#define FN(n, T, RP, RV, body) T n(pp, vv) T **pp; T vv; { RP T *p = *pp; RV T v = vv; body }
#define SET(k, s, T, RP, RV, INC) \
FN(ret_##s, T, RP, RV, v++; return *p = v;) \
FN(rt0_##s, T, RP, RV, return *p = v;) \
FN(jmp_##s, T, RP, RV, v++; if (vv != 0) return *p = v; sink_##k(v); return 0;) \
FN(chn_##s, T, RP, RV, T x; v++; x = *p = v; return x;) \
FN(arg_##s, T, RP, RV, v++; sink_##k(*p = v); return g_##k;) \
FN(cnd_##s, T, RP, RV, v++; if ((*p = v) != 0) return v; return 0;)
#define SETB(k, s, T, RP, RV, INC) \
FN(cmp_##s, T, RP, RV, return *p += INC;) \
FN(pre_##s, T, RP, RV, return ++*p;) \
FN(pst_##s, T, RP, RV, return (*p)++;) \
FN(prd_##s, T, RP, RV, return --*p;) \
FN(psd_##s, T, RP, RV, return (*p)--;) \
FN(ipp_##s, T, RP, RV, T r; r = *p++ = v; *pp = p; return r;)
#define TAB(s) ret_##s, rt0_##s, jmp_##s, chn_##s, arg_##s, cnd_##s, \
	cmp_##s, pre_##s, pst_##s, prd_##s, psd_##s, ipp_##s
#define NF 12

SET(l, l00, long, , , v)
SETB(l, l00, long, , , v)
SET(l, l01, long, , register, v)
SETB(l, l01, long, , register, v)
SET(l, l10, long, register, , v)
SETB(l, l10, long, register, , v)
SET(l, l11, long, register, register, v)
SETB(l, l11, long, register, register, v)
SET(p, p00, struct A *, , , 1)
SETB(p, p00, struct A *, , , 1)
SET(p, p01, struct A *, , register, 1)
SETB(p, p01, struct A *, , register, 1)
SET(p, p10, struct A *, register, , 1)
SETB(p, p10, struct A *, register, , 1)
SET(p, p11, struct A *, register, register, 1)
SETB(p, p11, struct A *, register, register, 1)
SET(i, i00, int, , , v)
SETB(i, i00, int, , , v)
SET(i, i01, int, , register, v)
SETB(i, i01, int, , register, v)
SET(i, i10, int, register, , v)
SETB(i, i10, int, register, , v)
SET(i, i11, int, register, register, v)
SETB(i, i11, int, register, register, v)
SET(c, c00, char, , , v)
SETB(c, c00, char, , , v)
SET(c, c01, char, , register, v)
SETB(c, c01, char, , register, v)
SET(c, c10, char, register, , v)
SETB(c, c10, char, register, , v)
SET(c, c11, char, register, register, v)
SETB(c, c11, char, register, register, v)
SET(u, u00, unsigned char, , , v)
SETB(u, u00, unsigned char, , , v)
SET(u, u01, unsigned char, , register, v)
SETB(u, u01, unsigned char, , register, v)
SET(u, u10, unsigned char, register, , v)
SETB(u, u10, unsigned char, register, , v)
SET(u, u11, unsigned char, register, register, v)
SETB(u, u11, unsigned char, register, register, v)

long (*lt[])() = { TAB(l00), TAB(l01), TAB(l10), TAB(l11) };
struct A *(*pt[])() = { TAB(p00), TAB(p01), TAB(p10), TAB(p11) };
int (*it[])() = { TAB(i00), TAB(i01), TAB(i10), TAB(i11) };
char (*ct[])() = { TAB(c00), TAB(c01), TAB(c10), TAB(c11) };
unsigned char (*ut[])() = { TAB(u00), TAB(u01), TAB(u10), TAB(u11) };

/* the value and the stored cell per form, from cell c0 and argument v0 */
#define WANT(c0, v0) \
	{ v0+1, v0, v0+1, v0+1, v0+1, v0+1, c0+v0, c0+1, c0, c0-1, c0, v0 }, \
	{ v0+1, v0, v0+1, v0+1, v0+1, v0+1, c0+v0, c0+1, c0+1, c0-1, c0-1, v0 }
long lw[2][NF] = { WANT(0x12345678L, 0x01020304L) };
int iw[2][NF] = { WANT(0x1234, -2) };
char cw[2][NF] = { WANT(0x7F, -16) };
unsigned char uw[2][NF] = { WANT(0xFF, 0x80) };
struct A *pw[2][NF] = {
	{ &arr[1], &arr[0], &arr[1], &arr[1], &arr[1], &arr[1], &arr[2], &arr[2], &arr[1], &arr[0], &arr[1], &arr[0] },
	{ &arr[1], &arr[0], &arr[1], &arr[1], &arr[1], &arr[1], &arr[2], &arr[2], &arr[2], &arr[0], &arr[0], &arr[0] }
};

#define RUN(k, T, tab, w, c0, v0) \
	for (i = 0; i < 4*NF; i++) { \
		T cell[2]; T *pp; T q; \
		cell[0] = c0; cell[1] = 0; pp = cell; \
		q = (*tab[i])(&pp, (T)(v0)); \
		if (q != w[0][i%NF] || cell[0] != w[1][i%NF] || cell[1] != 0 \
		 || (pp - cell) != (i%NF == NF-1)) { \
			printf(" %s%d", #k, i); ++bad; \
		} \
	}

main()
{
	int i, bad;

	bad = 0;
	RUN(l, long, lt, lw, 0x12345678L, 0x01020304L)
	RUN(p, struct A *, pt, pw, &arr[1], &arr[0])
	RUN(i, int, it, iw, 0x1234, -2)
	RUN(c, char, ct, cw, 0x7F, -16)
	RUN(u, unsigned char, ut, uw, 0xFF, 0x80)
	printf(bad ? " -> %d bad\n" : "%d bad\n", bad);
	return 0;
}
EOF
"$CCZ" -o "$T/r" "$T/r.c" >/dev/null 2>&1 || { echo "  asgval: link FAIL"; exit 1; }
got=$("$N2" -runexec "$T/r" 2>/dev/null) || true
if [ "$got" = "0 bad" ]; then
	echo "  values 240 forms PASS"
else
	echo "  values FAIL:$got"; fail=1
fi

[ "$fail" = 0 ] || { echo "=== asgval: FAIL ==="; exit 1; }
echo "=== asgval: PASS ==="
