# shims.sh - apply the HOST SHIMS to a scratch copy of src/cc.
#
# The shims are LP64/glibc/gcc-strictness workarounds needed only to build the
# compiler ON A MODERN HOST; the committed source stays native-faithful.  They
# live in host/shims/*.patch, one file per row of the HOST SHIMS table in
# docs/PATCHES.md, so they can be read as patches.
#
# EVERY patch in the directory is applied, in name order, at fuzz 0.  The
# directory IS the shim set: a patch cannot be added without being used, and one
# whose hunks no longer match the source fails the build by name.  A shim that
# quietly stops matching is how a host-built and a native-built compiler drift
# apart while both look fine, so there is no path here that reports success
# without having changed anything.
#
# Sourced by host/build-cc.sh; run alone by tests/check-shims.sh (`make
# check-shims'), which applies them to a pristine copy and nothing else.

# shim_apply <shimdir> <tree> : apply the shims to <tree>, or fail naming one
shim_apply() {
	shim__d=$1 shim__t=$2 shim__n=0
	for shim__p in "$shim__d"/*.patch; do
		[ -f "$shim__p" ] || { echo "SHIMS: $shim__d holds no patches"; return 1; }
		patch -p1 -F0 -s --no-backup-if-mismatch -d "$shim__t" < "$shim__p" ||
			{ echo "SHIM DID NOT APPLY: ${shim__p##*/}"; return 1; }
		shim__n=$((shim__n + 1))
	done
	# A rename patch still applies when new source ADDS a call it does not
	# cover, so the renames are asserted by their RESULT: a name that
	# survives resolves to the host libc's function instead.
	shim_gone select "$shim__t"/n1/*.c &&
	shim_gone getline "$shim__t"/n0/sharp.c &&
	shim_gone ungetc "$shim__t"/coh/tabgen.c || return 1
	echo "shims: $shim__n applied, renames complete"
}

# shim_gone <word> <file>... : no file may still name <word>
shim_gone() {
	shim__w=$1; shift
	grep -lw "$shim__w" "$@" || return 0
	echo "SHIM INCOMPLETE: $shim__w survives the rename in the file(s) above"
	return 1
}
