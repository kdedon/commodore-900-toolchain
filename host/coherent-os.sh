# coherent-os.sh -- resolve an OS tree, for `.' not for exec.
#
# The toolchain does not depend on any OS: it builds, and its regression gates
# run, from this repository alone.  But a few harnesses here do not build the
# TOOLCHAIN -- they build OS artifacts WITH it (libc-z8001.a, libm, the native
# self-host, and ccz's default system include path).  Those genuinely need an OS
# checkout, and the honest thing is to say so and take its location as an input
# rather than to produce a confusing failure deep in a compile.
#
# Sets $COHERENT_OS.  Caller: `. "$HERE/coherent-os.sh"` -- it exits nonzero with
# an explanation if no usable tree is named or found.
#
# The variable still wins, a value that does not resolve is refused as itself
# rather than quietly replaced, and the variable is still what the refusal names.
# The search behind it is host/deps.sh, bounded at three parents plus repos/,
# and it exists because `make deps' clones the OS repository to exactly one of
# those paths: a resolver that would not look there would make `make deps' a
# lie.  What is not allowed is an unbounded walk, which would make this
# repository look self-contained by finding somebody else's tree.
_c9d=${HERE:-$(dirname "$0")}
_c9os=$(COHERENT_OS="${COHERENT_OS:-}" sh "$_c9d/deps.sh" coherent)
if [ -n "$_c9os" ]; then
	COHERENT_OS=$_c9os
else
	COHERENT_OS="${COHERENT_OS:-}" sh "$_c9d/deps.sh" -n coherent "${COHERENT_OS:-}"
	exit 2
fi
# A snapshot is a legitimate answer and a QUIETER one than a checkout: it goes
# on building the OS it was cut from long after that tree has moved.  So when
# the resolver lands on the unpacked fallback, every build says which commit it
# is compiling, on stderr, once.  Silence here would be the difference between
# "built against COHERENT" and "built against COHERENT as of some Tuesday".
if [ -f "$COHERENT_OS/.provenance" ]; then
	echo "coherent-os: OS SNAPSHOT $(awk '$1=="commit"{print substr($2,1,12)}' "$COHERENT_OS/.provenance") of $(awk '$1=="date"{print $2}' "$COHERENT_OS/.provenance") -- $COHERENT_OS" >&2
	echo "coherent-os: a checkout supersedes it; set COHERENT_OS to one." >&2
fi

unset _c9d _c9os
export COHERENT_OS
