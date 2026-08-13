#!/bin/sh
# check-syscalls.sh -- the C library's system-call numbers against the kernel's.
#
#	sh host/check-syscalls.sh <kernel-syscalls.tab>
#
# libc/syscalls.tab says what number each stub traps on; the kernel's dispatch
# table says what number it answers.  They are two halves of one contract and
# nothing compared them until now: a wrong number is not a build failure, it is
# a program that silently calls the wrong system call.
#
# The kernel's file is packaged by its pack-kernel.sh (extracted from tab.c) and
# ships in the kernel package, `NN name' per line.  It is an ARGUMENT rather
# than a path into another repository, so this runs against whichever kernel is
# actually being built against.
#
# Calls the kernel has and libc does not are not an error: not every entry point
# has a C stub.  A libc stub the kernel cannot dispatch IS an error, and so is
# any disagreement about a number.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/coherent-os.sh"
LIBC="$COHERENT_OS/libc/syscalls.tab"
KERN=${1:-}

[ -f "$LIBC" ] || { echo "check-syscalls: no $LIBC" >&2; exit 1; }
[ -n "$KERN" ] || {
	echo "check-syscalls: no kernel table given; nothing was compared." >&2
	echo "  usage: sh host/check-syscalls.sh <kernel syscalls.tab>" >&2
	echo "  It ships in the c900-kernel package, beside boot/kernel.out." >&2
	exit 2
}
[ -f "$KERN" ] || { echo "check-syscalls: no such kernel table: $KERN" >&2; exit 1; }

W=$(mktemp -d "${TMPDIR:-/tmp}/cksys.XXXXXX")
trap 'rm -rf "$W"' EXIT INT TERM

# libc: `name number'.  kernel: `number name'.
sed -e 's/#.*//' -e '/^[ \t]*$/d' "$LIBC" | awk '{print $1, $2}' | sort > "$W/libc"
sed -e 's/#.*//' -e '/^[ \t]*$/d' "$KERN" | awk '{print $2, $1}' | sort > "$W/kern"
[ -s "$W/libc" ] || { echo "check-syscalls: $LIBC named no calls" >&2; exit 1; }
[ -s "$W/kern" ] || { echo "check-syscalls: $KERN named no calls" >&2; exit 1; }

bad=0
join -j1 "$W/libc" "$W/kern" | while read -r n a b; do
	[ "$a" = "$b" ] || echo "$n libc=$a kernel=$b"
done > "$W/mismatch"
if [ -s "$W/mismatch" ]; then
	echo "check-syscalls: libc and the kernel disagree about these numbers:" >&2
	sed 's/^/    /' "$W/mismatch" >&2
	bad=1
fi

# A stub for something the kernel cannot dispatch: the call traps into nothing.
join -v1 -j1 "$W/libc" "$W/kern" > "$W/orphan" || :
if [ -s "$W/orphan" ]; then
	echo "check-syscalls: libc has stubs the kernel does not dispatch:" >&2
	awk '{printf "    %s (%s)\n", $1, $2}' "$W/orphan" >&2
	bad=1
fi

[ "$bad" -eq 0 ] || exit 1
echo "check-syscalls: $(wc -l < "$W/libc") libc stubs agree with the kernel ($(wc -l < "$W/kern") entry points)"
