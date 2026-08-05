# buildlog.sh -- record which sources a build compiled, for `.' not for exec.
#
# A consumer's provenance gate can only ask "is this source judged?" of sources
# it can SEE, and it sees them by reading build scripts in its own repository.
# The libraries here are compiled out of an OS tree by scripts that live in
# THIS one, so that reading can never reach them.  The record closes that: the
# compile itself says what it compiled, whichever repository the script was in.
#
# $C900_BUILD_LOG names the file.  Unset -- the default, and what a release
# consumer has -- nothing is written, nothing is read, and no output, exit
# status or artifact differs.
#
# Each source is one line, appended, exactly as the caller spelled it: a path
# into another repository must read as one, since a path normalised to look
# local is precisely the thing the record exists to expose.  One printf per
# line keeps each append inside PIPE_BUF, so parallel builds sharing a log
# interleave whole lines rather than halves of two.

# c900_buildlog <source>... -- record sources about to be compiled.
c900_buildlog() {
	[ -n "${C900_BUILD_LOG:-}" ] || return 0
	if [ ! -f "$C900_BUILD_LOG" ]; then
		case "$C900_BUILD_LOG" in
		*/*) mkdir -p "${C900_BUILD_LOG%/*}" 2>/dev/null;;
		esac
	fi
	for _bl_s in "$@"; do
		printf '%s\n' "$_bl_s" >>"$C900_BUILD_LOG" 2>/dev/null || break
	done
	unset _bl_s
	return 0
}
