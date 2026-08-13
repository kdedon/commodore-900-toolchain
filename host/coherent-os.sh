# coherent-os.sh -- locate the C library, headers and startup sources.
#
# Sets $COHERENT_OS to this repository's src/, the root the OS-side sources
# hang off.  Caller: `. "$HERE/coherent-os.sh"`.
#
#	$COHERENT_OS/include	the target's system headers
#	$COHERENT_OS/libc	the C library
#	$COHERENT_OS/csu	crts0.s
#	$COHERENT_OS/libm	the maths library
#	$COHERENT_OS/libmisc	the misc library
#	$COHERENT_OS/malloc	the allocator libc takes malloc/free from
#	$COHERENT_OS/ar/ar.c	the archive reader as and ld share
_c9d=${HERE:-$(dirname "$0")}
COHERENT_OS=$(cd "$_c9d/../src" && pwd) || {
	echo "coherent-os.sh: no src/ beside host/ -- this is not a toolchain checkout." >&2
	exit 2
}
unset _c9d
export COHERENT_OS
