#!/bin/sh
# ld-commsize.sh -- a common against a definition of the same name.
#
# A definition's size is the room before the next symbol in its segment.  One
# smaller than the common is refused; a larger one passes.  A common that
# loses to a definition reserves no BSSD.

set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"		# $BUILD
AS="$BUILD/as-z8001"; LD="$BUILD/ld-z8001"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bad=0

asm() {			# asm NAME <<text
	cat > "$T/$1.s"
	"$AS" -o "$T/$1.o" "$T/$1.s"
}

# link NAME ok|no OBJ...
link() {
	n=$1; want=$2; shift 2
	if "$LD" -o "$T/$n.out" "$@" > "$T/$n.log" 2>&1; then got=ok; else got=no; fi
	if [ "$got" != "$want" ]; then
		echo "  FAIL $n: link $got, wanted $want"
		sed -n '1,3p' "$T/$n.log"
		bad=$((bad+1))
	elif [ "$want" = no ] && ! grep -q 'common' "$T/$n.log"; then
		echo "  FAIL $n: refused without naming the common"
		sed -n '1,3p' "$T/$n.log"
		bad=$((bad+1))
	else
		echo "  ok   $n ($got)"
	fi
}

# bssd NAME WANT
bssd() {
	got=$(python3 -c 'import sys
b=open(sys.argv[1],"rb").read()
o=8+4*5
print((b[o]|b[o+1]<<8)<<16|(b[o+2]|b[o+3]<<8))' "$T/$1.out")
	if [ "$got" != "$2" ]; then
		echo "  FAIL $1: BSSD $got, wanted $2"
		bad=$((bad+1))
	else
		echo "  ok   $1 BSSD=$got"
	fi
}

asm c64 <<'EOF'
	.comm	v,64
EOF
asm c4 <<'EOF'
	.comm	v,4
EOF
asm c100 <<'EOF'
	.comm	m,100
EOF
asm c200 <<'EOF'
	.comm	m,200
EOF
asm d2 <<'EOF'
	.globl	v
	.prvd
v:	.word	0
EOF
asm d64 <<'EOF'
	.globl	v
	.prvd
v:	.blkb	64
EOF
asm d128 <<'EOF'
	.globl	v
	.prvd
v:	.blkb	128
EOF
asm fn <<'EOF'
	.globl	v
v:	ret
EOF

echo "=== 1 a definition smaller than the common is refused, either order"
link small1 no "$T/c64.o" "$T/d2.o"
link small2 no "$T/d2.o" "$T/c64.o"

echo "=== 2 an equal definition is taken"
link equal ok "$T/c64.o" "$T/d64.o"

echo "=== 3 a larger definition is taken, and says nothing"
link large ok "$T/c4.o" "$T/d128.o"
if [ -s "$T/large.log" ]; then
	echo "  FAIL large: ld had something to say"
	sed -n '1,3p' "$T/large.log"
	bad=$((bad+1))
fi

echo "=== 4 two commons of a name take the larger, and reserve it"
link two ok "$T/c100.o" "$T/c200.o"
bssd two 200

echo "=== 5 a common that a definition satisfies reserves nothing"
link nores ok "$T/c64.o" "$T/d64.o"
bssd nores 0

echo "=== 6 a common against a function is refused, either order"
link func1 no "$T/c64.o" "$T/fn.o"
link func2 no "$T/fn.o" "$T/c64.o"

echo "=== ld common against definition: $([ $bad = 0 ] && echo PASS || echo FAIL) ==="
[ $bad = 0 ]
