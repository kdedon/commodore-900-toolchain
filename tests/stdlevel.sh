#!/bin/sh
# stdlevel.sh -- the language levels -VKR, -VC89 and -VC99.
#
# Each addition is taken at its level and above and by default, and is an
# error naming it below; `//' and `f(T)' (T a typedef name) are refused the
# donor's way, since K&R code can hold the same text.  K&R code compiles to the
# same object at every level: the C library's sources are the corpus.  The
# driver maps each option onto VSTD0/VSTD1, and -VSTRICT sets VSTRICT, which
# makes every strict message an error.  ccz takes the same levels from
# CCZ_LEVEL.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
. "$H/host/coherent-os.sh"		# $COHERENT_OS
CC0="$BUILD/z8001/cc0-z8001"
DEF=800000020800; KR=800000020840; C89=800000020880; C99=8000000208C0
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

# <name> <message or -> <levels taking it: C89 (and up), C99, or KRONLY> <source>
feature() {
	printf '%s\n' "$4" > "$T/f.c"
	bad=0
	for lv in DEF KR C89 C99; do
		eval v=\$$lv
		case "$3.$lv" in
		KRONLY.KR|C89.DEF|C89.C89|C89.C99|C99.DEF|C99.C99) want=ok ;;
		*) want=refused ;;
		esac
		if "$CC0" $v "$T/f.c" "$T/f.z0" > "$T/f.err" 2>&1; then got=ok; else got=refused; fi
		if [ "$got" != "$want" ]; then
			echo "  $1 at $lv: $got, want $want FAIL"; cat "$T/f.err"; bad=1
		elif [ "$got" = refused ] && [ "$2" != - ] && [ "$lv" != DEF ] &&
		     ! grep -q "$2" "$T/f.err"; then
			echo "  $1 at $lv: no \"$2\" FAIL"; cat "$T/f.err"; bad=1
		fi
	done
	if [ "$bad" = 0 ]; then echo "  $1 PASS"; else fail=1; fi
}
feature prototype 'a function prototype is not K&R C' C89 \
	'int f(int a, char *b) { return a + *b; }'
feature 'prototype cast' 'a function prototype is not K&R C' C89 \
	'int (*g)(); h() { return ((int (*)(int))g)(1); }'
feature 'structure initializer' 'a structure initialized by an expression is not K&R C' C89 \
	'struct R { int a; }; f(p) struct R *p; { struct R o = *p; return o.a; }'
feature 'sized automatic array' 'an automatic array sized by its initializer is not K&R C' C89 \
	'f(i) { long a[] = { 1, 2 }; return a[i]; }'
feature 'long switch' 'a switch on a long is not K&R C' C89 \
	'f(l) long l; { switch (l) { case 70000L: return 1; } return 0; }'
# Under -VKR `&' of an array is the MWC compiler's error.
feature 'address of an array' 'lvalue required' C89 \
	'struct S { short a[4]; } s; short b[4]; f(p) struct S *p; { return (short *)&p->a - (short *)&b; }'
# Under -VKR offsetof() is not a constant, as in the MWC compiler.
printf '#include <stddef.h>\nstruct S { short x; char c; };\nf(i) { switch (i) { case offsetof(struct S, c): return 1; } return 0; }\n' > "$T/oc.c"
if "$CC0" $DEF "$T/oc.c" "$T/oc.z0" -I"$H/src/include" >/dev/null 2>&1 &&
   ! "$CC0" $KR "$T/oc.c" "$T/oc.z0" -I"$H/src/include" > "$T/oc.err" 2>&1 &&
   grep -q 'int constant expression required' "$T/oc.err"; then
	echo "  -VKR offsetof() case label refused PASS"
else
	echo "  -VKR offsetof() case label FAIL"; cat "$T/oc.err"; fail=1
fi
feature '// comment' - C99 \
	'f() { return 1; // one
}'
feature 'declaration after a statement' 'a declaration after a statement is not' C99 \
	'f() { int a; a = 1; int b = a; return b; }'
feature 'declaration in a for' 'a declaration in a for is not' C99 \
	'f() { int s = 0; for (int i = 0; i < 3; i++) s += i; return s; }'
feature 'f(T) is a K&R parameter' - KRONLY \
	'typedef int T; int f(T) int T; { return T + 1; }'

# The C89 message names C89 under -VC89.
printf 'f() { int a; a = 1; int b = a; return b; }\n' > "$T/c.c"
if "$CC0" $C89 "$T/c.c" "$T/c.z0" 2>&1 | grep -q 'is not C89 (-VC89)'; then
	echo "  -VC89 message PASS"
else
	echo "  -VC89 message FAIL"; fail=1
fi
# `a //* c */ b' is a division in K&R.
printf 'f(a, b) { return a //* c */ b;\n}\n' > "$T/d.c"
if "$CC0" $KR "$T/d.c" "$T/d.z0" > /dev/null 2>&1; then
	echo "  -VKR a //* c */ b PASS"
else
	echo "  -VKR a //* c */ b FAIL"; fail=1
fi

# K&R code: the same code at every level.  cc0's output is the same, except
# that above -VKR offsetof() folds to its constant; where the output differs,
# the objects must not.  The C library's sources are the corpus, with one
# that uses offsetof() at run time.
cat > "$T/ofs.c" <<'EOF'
#include <stddef.h>
struct S { short x; char c; short a[4]; };
static unsigned so = offsetof(struct S, c);
f(p, n) char *p; { return *(short *)(p + offsetof(struct S, x)) + n * offsetof(struct S, c) + so; }
g() { return (int)&((struct S *)0)->c; }
EOF
CC1="$BUILD/z8001/cc1-z8001"; CC2="$BUILD/z8001/cc2-z8001"
obj() { "$CC1" $1 "$2" "$2.z1" >/dev/null 2>&1 && "$CC2" 0012 "$2.z1" "$2.o" "$2.scr" 0 >/dev/null 2>&1; }
n=0; nz=0; diff=""
for c in "$COHERENT_OS"/libc/*/*.c "$T/ofs.c"; do
	b=$(basename "$c" .c)
	I="-I$COHERENT_OS/include -I$COHERENT_OS/include/sys"
	[ "$c" = "$T/ofs.c" ] && I="-I$H/src/include"
	"$CC0" $DEF "$c" "$T/def.z0" $I >/dev/null 2>&1 || continue
	for lv in KR C89 C99; do
		eval v=\$$lv
		if ! "$CC0" $v "$c" "$T/lv.z0" $I >/dev/null 2>&1; then
			diff="$diff $b($lv)"
		elif ! cmp -s "$T/def.z0" "$T/lv.z0"; then
			nz=$((nz+1))
			obj $DEF "$T/def.z0" && obj $v "$T/lv.z0" && cmp -s "$T/def.z0.o" "$T/lv.z0.o" ||
				diff="$diff $b($lv)"
		fi
	done
	n=$((n+1))
done
if [ -z "$diff" ] && [ "$n" -gt 100 ] && [ "$nz" -gt 0 ]; then
	echo "  $n sources, the same code at every level ($nz cc0 outputs differ, their objects do not) PASS"
else
	echo "  K&R code at the levels ($n sources, $nz cc0 outputs differ): differ:$diff FAIL"; fail=1
fi

# -VSTRICT (VSTRICT, bit 48: a seventh variant byte, 01) makes every strict
# message an error, which -VNOWARN does not hide.  <want: warn|error|quiet> <variant> <source>
strict() {
	printf '%s\n' "$3" > "$T/s.c"
	if "$CC0" $2 "$T/s.c" "$T/s.z0" > "$T/s.err" 2>&1; then rc=0; else rc=1; fi
	if grep -q 'Strict:' "$T/s.err"; then said=1; else said=0; fi
	case "$1.$rc.$said" in
	warn.0.1|error.1.1|quiet.0.0) echo "  $1 at $2 PASS" ;;
	*) echo "  $2: rc $rc, message $said, want $1 FAIL"; cat "$T/s.err"; fail=1 ;;
	esac
}
VA='extern int f(char *, ...); g() { f("x", 1); }'
BK='struct R { int a; } q; g() { struct R o; o = q; return o.a; }'
strict quiet 800000020800 "$VA"
strict warn 800000020820 "$VA"
strict error 80000002082001 "$VA"
strict quiet 80000002080001 "$VA"
strict quiet 800040020820 "$VA"
strict error 80004002082001 "$VA"
strict warn A00000020840 "$BK"
strict error A0000002084001 "$BK"
# A seventh byte of 00 reads as the twelve-digit string.
printf '%s\n' "$VA" > "$T/s.c"
"$CC0" 800000020820 "$T/s.c" "$T/a.z0" 2>/dev/null; "$CC0" 80000002082000 "$T/s.c" "$T/b.z0" 2>/dev/null
if cmp -s "$T/a.z0" "$T/b.z0"; then echo "  ...00 = twelve digits PASS"; else echo "  ...00: output differs FAIL"; fail=1; fi
# ccz maps the options as the cc driver does.
printf '%s\n' "$BK" > "$T/k.c"
printf 'int h(int a) { return a; }\n' > "$T/p.c"
if "$H/host/ccz" -c -o "$T/k.o" -VKR "$T/k.c" >/dev/null 2>&1 &&
   ! "$H/host/ccz" -c -o "$T/k.o" -VKR -VSTRICT "$T/k.c" >/dev/null 2>&1 &&
   ! "$H/host/ccz" -c -o "$T/k.o" -VKR "$T/p.c" >/dev/null 2>&1 &&
   "$H/host/ccz" -c -o "$T/k.o" -VKR -VC89 "$T/p.c" >/dev/null 2>&1 &&
   "$H/host/ccz" -c -o "$T/k.o" -VC99 -VSTRICT "$T/k.c" >/dev/null 2>&1; then
	echo "  ccz -VKR -VC89 -VC99 -VSTRICT PASS"
else
	echo "  ccz level options FAIL"; fail=1
fi

# CCZ_LEVEL: the level options from the environment, in whichever base string
# the compile uses; a level on the command line wins.  Unset or empty changes
# nothing.
C="$H/host/ccz"
printf 'extern int x; f() { return x; }\n' > "$T/e.c"
lv() { printf '  CCZ_LEVEL %s ' "$1"; shift
	if "$@" >/dev/null 2>&1; then echo PASS; else echo FAIL; fail=1; fi; }
lv 'KR refuses a prototype' eval '! CCZ_LEVEL=KR "$C" -c -o "$T/l.o" "$T/p.c"'
lv 'C89,STRICT takes a prototype' eval 'CCZ_LEVEL=C89,STRICT "$C" -c -o "$T/l.o" "$T/p.c"'
lv '"KR STRICT" refuses a structure assignment' eval '! CCZ_LEVEL="KR STRICT" "$C" -c -o "$T/l.o" "$T/k.c"'
lv 'STRICT keeps a -VKR on the command line' eval '! CCZ_LEVEL=STRICT "$C" -c -o "$T/l.o" -VKR "$T/k.c"'
lv 'KR is replaced by -VC89' eval 'CCZ_LEVEL=KR "$C" -c -o "$T/l.o" -VC89 "$T/p.c"'
lv 'C99 is replaced by -VKR' eval '! CCZ_LEVEL=C99 "$C" -c -o "$T/l.o" -VKR "$T/p.c"'
lv 'unknown word refused' eval '! CCZ_LEVEL=K\&R "$C" -c -o "$T/l.o" "$T/k.c"'
# With the PIC variant: KR still refuses a prototype, and the object is the
# PIC one, not the plain one.
"$C" -c -o "$T/pic.o" -VPIC "$T/e.c" >/dev/null 2>&1
"$C" -c -o "$T/abs.o" "$T/e.c" >/dev/null 2>&1
lv 'KR with -VPIC refuses a prototype' eval '! CCZ_LEVEL=KR "$C" -c -o "$T/l.o" -VPIC "$T/p.c"'
lv 'KR with -VPIC keeps PIC' eval 'CCZ_LEVEL=KR "$C" -c -o "$T/l.o" -VPIC "$T/e.c" && cmp -s "$T/l.o" "$T/pic.o" && ! cmp -s "$T/pic.o" "$T/abs.o"'
lv 'KR with CCZ_VAR keeps the level' eval '! CCZ_LEVEL=KR CCZ_VAR=800000020808 "$C" -c -o "$T/l.o" "$T/p.c"'
# Unset, empty and blank are the default strings, the same bytes.
for f in p e; do for pv in "" -VPIC; do
	unset CCZ_LEVEL
	if [ -n "$pv" ]; then d=800000020808; else d=800000020800; fi
	CCZ_VAR=$d "$C" -c -o "$T/d.o" $pv "$T/$f.c" >/dev/null 2>&1
	"$C" -c -o "$T/u.o" $pv "$T/$f.c" >/dev/null 2>&1
	CCZ_LEVEL= "$C" -c -o "$T/z.o" $pv "$T/$f.c" >/dev/null 2>&1
	CCZ_LEVEL=' ' "$C" -c -o "$T/b.o" $pv "$T/$f.c" >/dev/null 2>&1
	lv "unset/empty $f.c $pv identical" eval 'cmp "$T/d.o" "$T/u.o" && cmp "$T/u.o" "$T/z.o" && cmp "$T/u.o" "$T/b.o"'
done; done

[ "$fail" = 0 ] || { echo "=== stdlevel: FAIL ==="; exit 1; }
echo "=== stdlevel: PASS ==="
