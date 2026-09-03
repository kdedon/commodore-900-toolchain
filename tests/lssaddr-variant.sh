#!/bin/sh
# lssaddr-variant.sh -- `&local' must compile under EVERY variant.
#
# A frame-relative address is *(FP + offset), and modleaf() in mtree2.c builds
# that node with the MODEL's pointer type.  It asked isvariant(VLARGE) and fell
# back to SPTR, but the model is really "near only when VSMALL is set" --
# cc1mch.h's iptrtype(), which is what bind.c's mytypes[T_PTR] and altemp.c's
# stack temporaries already say.  A variant word that sets NEITHER bit therefore
# got a 4-byte LPTR `char *' and a 2-word-narrower SPTR frame address in the
# same expression, and selection had nothing to match: `pp = &local' aborted
# cc1 with EDFA69 (ASSIGN), `g(&x)' with EDFA62 (CALL).
#
# The cc driver always sets one of the two bits, so only a hand-written variant
# word reaches this.  The CP/M tree's UVAR (VPEEP|VTPA, 001000000004) is one --
# it drives cc2 with it, and anything that also handed it to cc1 would meet the
# internal compiler error.
#
# cc0/cc1 take the MODEL word and cc2 the code-emission word, which is how every
# build in this tree drives them (host/build-libc-z8001.sh: cc2 0010; the CP/M
# Makefile: cc2 $(UVAR)).  Both cc2 words are run against both cc1 outputs.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"		# $BUILD
CC0="$BUILD/z8001/cc0-z8001"
CC1="$BUILD/z8001/cc1-z8001"
CC2="$BUILD/z8001/cc2-z8001"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

cat > "$T/lss.c" <<'EOF'
struct s { int a; char b[6]; };
char *pp;
struct s *sp;
int *ip;
g();
f1() { int x; g(&x); }			/* address of a local as an argument */
f2() { int x; ip = &x; return (*ip); }	/* ... assigned to a global pointer */
f3() { char c; pp = &c; }		/* ... of a byte */
f4() { struct s v; sp = &v; return sp->a; }	/* ... of an aggregate */
f5() { char buf[10]; pp = buf; return pp[0]; }	/* a local array decaying */
f6(n) { int x; int *q; q = &x; *q = n; return x; }  /* ... into a local pointer */
f7() { struct s v, w; v = w; sp = &v; }	/* aggregate copy plus its address */
EOF

# the system variant, then the user variant the CP/M commands are built with
fail=0
for var in 800000020800 001000000004; do
	if "$CC0" "$var" "$T/lss.c" "$T/lss.z0" >"$T/out" 2>&1 &&
	   "$CC1" "$var" "$T/lss.z0" "$T/$var.z1" >>"$T/out" 2>&1
	then
		echo "  $var &local: cc1 ok"
	else
		echo "  $var &local: cc1 FAIL"
		sed 's/^/    /' "$T/out"
		fail=1
		continue
	fi
	for v2 in 0010 001000000004; do
		if "$CC2" "$v2" "$T/$var.z1" "$T/lss.o" "$T/lss.scr" 0 >"$T/out" 2>&1
		then
			echo "    cc2 $v2: ok"
		else
			echo "    cc2 $v2: FAIL"
			sed 's/^/      /' "$T/out"
			fail=1
		fi
	done
done
[ $fail -eq 0 ] || { echo "lssaddr-variant: FAILED"; exit 1; }
echo "lssaddr-variant: OK -- every variant takes the address of a local"
