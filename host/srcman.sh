# srcman.sh -- what a component is MADE OF, read from that component's own
# native build.  For `.', not for exec; the caller has already set $HERE.
#
#	. "$HERE/srcman.sh"
#	srcman_list  cc "$ROOT/src/cc"	 expected .c paths, relative, one per line
#	srcman_check cc "$ROOT/src/cc"	 refuse any source the build does not expect
#
# There is ONE declaration per component and it is the build that runs on the
# C900: src/cc/Makefile's object lists, src/as/run's $SRC/$MDSRC, src/ld/all.c's
# include list.  The host cross-build compiles the same list, so the native and
# the host compiler cannot be made of different files.
#
# srcman_check refuses a .c that is present in the source tree and named by no
# declaration, by name.  An undeclared source is neither compiled nor skipped in
# silence: silently compiled, it ships inside the released compiler with nothing
# anywhere recording it; silently skipped, it reads as source that is built.
#
# A scratch or backup copy therefore belongs in a private directory or under
# $C900_BUILD -- never beside the file it copies.

srcman_list() {	# srcman_list <component> <srcdir>
	case "$1" in
	cc)	# every object and every source the native Makefile names
		{ sed 's/#.*//' "$2/Makefile" | grep -oE '[A-Za-z0-9_./]+\.o' |
			sed 's/\.o$/.c/'
		  sed 's/#.*//' "$2/Makefile" | grep -oE '[A-Za-z0-9_./]+\.c'
		} | sort -u ;;
	as)	sed -n "s/^SRC='\([^']*\)'.*/\1/p; s/^MDSRC='\([^']*\)'.*/\1/p" "$2/run" |
		tr ' ' '\n' | grep '\.c$' | sort -u ;;
	ld)	# unity build: all.c and the sources it includes
		{ echo all.c
		  sed -n 's/^#include[ 	]*"\([A-Za-z0-9_./]*\.c\)".*/\1/p' "$2/all.c"
		} | sort -u ;;
	*)	echo "srcman: no manifest for component '$1'" >&2; return 1 ;;
	esac
}

srcman_selfhost_check() {	# srcman_selfhost_check <ccdir> <build-selfhost.sh>
	# build-selfhost.sh names the compiler's sources a second time, because it
	# compiles them one at a time under the TARGET compiler and caches the
	# objects.  It builds cc0/cc1/cc2 and cc3, so its list is the cc manifest
	# less coh/ (the native driver and tabgen, which no target pass links).  The
	# two lists must agree: a source in one and not the other is a compiler whose
	# self-host fixed point is not the compiler this repository ships.
	srcman__a=$(mktemp) || return 1
	srcman__b=$(mktemp) || { rm -f "$srcman__a"; return 1; }
	for srcman__v in COMMON:common N0:n0 N1:n1 N1MD:n1/z8001 N2:n2 N2MD:n2/z8001 \
			 N3:n3 N3MD:n3/z8001 CHNAM:common/z8001; do
		sed -n "s/^${srcman__v%%:*}=\"\([^\"]*\)\".*/\1/p" "$2" | tr ' ' '\n' |
		sed "/^\$/d; s|^|${srcman__v#*:}/|; s|\$|.c|"
	done > "$srcman__a"
	{ echo n0/z8001/bind.c; echo n1/tables/macros.c; echo n1/tables/patern.c; } >> "$srcman__a"
	sort -u -o "$srcman__a" "$srcman__a"
	srcman_list cc "$1" | grep -v '^coh/' > "$srcman__b"
	srcman__rc=0
	comm -3 "$srcman__a" "$srcman__b" | sed 's/^\t*//' | while read -r srcman__f; do
		echo "srcman: $2 and $1/Makefile disagree about $srcman__f" >&2
	done
	[ "$(comm -3 "$srcman__a" "$srcman__b" | wc -l)" = 0 ] || srcman__rc=1
	rm -f "$srcman__a" "$srcman__b"
	return $srcman__rc
}

srcman_check() {	# srcman_check <component> <srcdir>
	srcman__n=$1
	srcman__d=$2
	srcman__rc=0
	srcman__exp=$(srcman_list "$srcman__n" "$srcman__d") || return 1
	# An empty list means the declaration moved or stopped parsing, and every
	# stray in the tree would then be reported instead of none of them.
	[ -n "$srcman__exp" ] || {
		echo "srcman: $srcman__n: no sources declared -- the native build's list did not parse" >&2
		return 1
	}
	for srcman__f in $(cd "$srcman__d" && find . -name '*.c' | sed 's|^\./||' | sort); do
		case "
$srcman__exp
" in
		*"
$srcman__f
"*)	;;
		*)	echo "srcman: $srcman__n: $srcman__d/$srcman__f is declared by no build and will not be compiled" >&2
			echo "        declare it in the native build, or move the copy out of the source tree" >&2
			srcman__rc=1 ;;
		esac
	done
	# The host builds flatten <pass>/ and <pass>/z8001/ into one object
	# directory, where two sources of the same name are one object.
	srcman__dup=$(echo "$srcman__exp" | sed 's|.*/||' | sort | uniq -d)
	[ -z "$srcman__dup" ] || {
		echo "srcman: $srcman__n: declared twice under one basename: $srcman__dup" >&2
		srcman__rc=1
	}
	return $srcman__rc
}
