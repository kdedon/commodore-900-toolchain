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

# THE OTHER HALF OF THE SAME RECORD: what an invocation PRODUCED, and from what.
#
# c900_buildlog answers "was this source compiled".  It cannot answer "which
# sources is this program made of", because a line naming a source says nothing
# about which of the fifty links running in the same sweep it fed.  A consumer
# that has to name the complete corresponding source of a shipped executable --
# which is what a licence obligation is -- needs the second question answered,
# and only the compile driver knows the answer: one directory is not one program
# in the producing tree, and half the programs are linked from objects compiled
# by a separate invocation.
#
# $C900_BUILD_MAP names the file, on the same terms as $C900_BUILD_LOG: unset,
# nothing is written and nothing about the build differs.
#
# FOUR-COLUMN, ONE PATH PER LINE, tab-separated:
#
#	o<TAB><cwd><TAB><output><TAB><recipe>	an invocation, and the script
#						($C900_BUILD_RECIPE) that ran it
#	i<TAB><cwd><TAB><output><TAB><input>	one input of that invocation
#
# One path per line rather than an input list, because a link line carrying
# sixty objects is longer than PIPE_BUF and would interleave in halves under a
# parallel build; every line here is short enough to append whole.  Paths are
# spelled as the caller spelled them and $cwd is recorded beside them, because a
# tree whose Makefile compiles `src/clients/bell.c' with no directory in it can
# only be resolved by knowing where it stood.  A reader groups by (cwd, output).
#
# $C900_SRC_EXTRA names sources that belong to a program but are not compile
# inputs -- a yacc grammar whose generated parser is what the compiler sees.
# They are recorded as inputs of the invocation that would otherwise disown
# them.

# c900_buildmap <output> <input>... -- record one invocation's product.
c900_buildmap() {
	[ -n "${C900_BUILD_MAP:-}" ] || return 0
	if [ ! -f "$C900_BUILD_MAP" ]; then
		case "$C900_BUILD_MAP" in
		*/*) mkdir -p "${C900_BUILD_MAP%/*}" 2>/dev/null;;
		esac
	fi
	_bm_o=$1; shift
	printf 'o\t%s\t%s\t%s\n' "$PWD" "$_bm_o" "${C900_BUILD_RECIPE:-}" \
		>>"$C900_BUILD_MAP" 2>/dev/null || { unset _bm_o; return 0; }
	for _bm_i in "$@" ${C900_SRC_EXTRA:-}; do
		printf 'i\t%s\t%s\t%s\n' "$PWD" "$_bm_o" "$_bm_i" \
			>>"$C900_BUILD_MAP" 2>/dev/null || break
	done
	unset _bm_o _bm_i
	return 0
}
