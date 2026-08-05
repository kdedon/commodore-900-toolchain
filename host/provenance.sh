# provenance.sh -- shared build-provenance stamping, for `.' not for exec.
#
# WHY.  Several lanes build into one filesystem namespace on one machine, so an
# artifact's identity is not implied by its path.  A toolchain built from a
# working tree with uncommitted edits in it once manufactured a compiler ICE in
# gzip that was relayed to another lane as a real source bug: two wrong
# diagnoses and hours, because nothing in any transcript said which source the
# compiler came from.  Isolating the ARTIFACT (build/z8001 is an atomically
# renamed symlink now) does not isolate the SOURCE.  Provenance does not prevent
# that incident; it makes it self-announcing, which is the difference between an
# hour and a session.
#
# WHAT IS RECORDED, and the one design decision that matters.  A whole-tree
# `git status --porcelain' is useless as an alarm here: this tree normally
# carries 100-200 uncommitted files belonging to other lanes, so a DIRTY flag
# that counts all of them is on permanently, and a warning that is always on is
# read as decoration.  So every stamp records TWO dirt counts:
#
#   dirty     the whole worktree             -- context, never an alarm
#   dirtysrc  ONLY the paths that were compiled into this artifact -- the alarm
#
# `dirtysrc' is what makes the line worth reading: it is nonzero exactly when
# the artifact cannot be reproduced from any commit.  Callers pass the scope
# (paths relative to the repo root) that actually feeds the thing they built.
#
# Usage:
#	. "$HERE/provenance.sh"
#	prov_write <stampfile> <kind> [scope-path ...] [-- k=v ...]
#	prov_header <label> [stampfile]     # prints; loud FIRST LINE if dirtysrc>0
#	prov_get <stampfile> <key>
#
# A stamp is `key=value' lines, one per line, values free of newlines.

# prov_repo [dir]: the git worktree containing <dir>, falling back to the
# caller's cwd.  The fallback matters: a stamp may legitimately be written to a
# scratch path outside the tree, and the tree it should NAME is still the one
# the build is running in.
#
# Prints nothing and SUCCEEDS when there is no git tree at all.  Every caller
# here runs under `set -e', so returning git's 128 would abort the build that
# just finished -- which is what happened the first time this toolchain was
# built from an exported tarball: the compiler linked, the smoke test passed,
# and the build then died stamping it.  Not being in a repository is a
# legitimate state for a source release; it costs the commit id, not the build.
prov_repo() {
	git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null ||
	git rev-parse --show-toplevel 2>/dev/null ||
	return 0
}

# prov_write <stampfile> <kind> [scope paths...] [-- extra k=v...]
# Written to a temporary and renamed, so a concurrent reader never sees half a
# stamp -- the same rule the artifacts themselves follow.
prov_write() {
	_ps_file=$1; _ps_kind=$2; shift 2
	# Scope words are collected into a string (they are paths, no spaces);
	# the extras stay POSITIONAL, because a value legitimately contains
	# spaces (a file list) and flattening them would split one k=v into
	# several bare lines.
	_ps_scope=""
	while [ $# -gt 0 ]; do
		case "$1" in
		--) shift; break;;
		*=*)	# A scope word can never contain `='.  Seeing one means a
			# `--' separator was glued to its neighbour, which silently
			# produces a stamp with none of the keys the caller asked
			# for -- and a stamp missing its key reads downstream as a
			# missing artifact.  Refuse it instead.
			echo "prov_write: scope word \"$1\" looks like a k=v -- a '--' separator is missing or glued to its neighbour" >&2
			return 1;;
		*) _ps_scope="$_ps_scope $1";;
		esac
		shift
	done
	# The tree a stamp NAMES is the source tree the build ran from, resolved
	# from this script's own directory ($HERE, the convention every caller
	# sets before sourcing).  Resolving it from the stamp's location instead
	# names whatever repository happens to contain the build directory: with
	# $C900_BUILD outside the checkout -- which is how a lane keeps its build
	# to itself -- that is a different repository, so the commit and the dirty
	# counts describe the wrong tree, and prov_pub_check, which resolves from
	# the source side, reads every build after the first as a cross-tree
	# publish over a directory nobody else has ever written to.
	_ps_root=$(prov_repo "${HERE:-.}")
	if [ -n "$_ps_root" ]; then
		_ps_head=$(git -C "$_ps_root" rev-parse HEAD 2>/dev/null)
		_ps_dirty=$(git -C "$_ps_root" status --porcelain 2>/dev/null | wc -l)
		if [ -n "$_ps_scope" ]; then
			# shellcheck disable=SC2086
			_ps_dsrc=$(git -C "$_ps_root" status --porcelain -- $_ps_scope 2>/dev/null | wc -l)
			# shellcheck disable=SC2086
			# Capped: the point of the list is to name the edits, and a
			# 60-entry line is scrolled past rather than read.  The
			# count above is the complete answer; this is the lead.
			# shellcheck disable=SC2086
			_ps_dlist=$(git -C "$_ps_root" status --porcelain -- $_ps_scope 2>/dev/null |
				    awk '{print $NF}' | sort | head -8 | tr '\n' ' ')
			if [ "$_ps_dsrc" -gt 8 ]; then
				_ps_dlist="$_ps_dlist+$((_ps_dsrc - 8)) more"
			fi
		else
			_ps_dsrc=$_ps_dirty; _ps_dlist=""
		fi
	else
		_ps_head=unknown; _ps_dirty=-1; _ps_dsrc=-1; _ps_dlist=""
	fi
	mkdir -p "$(dirname "$_ps_file")"
	{
		echo "kind=$_ps_kind"
		echo "commit=$_ps_head"
		echo "dirty=$_ps_dirty"
		echo "dirtysrc=$_ps_dsrc"
		echo "scope=$(echo $_ps_scope)"
		echo "dirtyfiles=$_ps_dlist"
		echo "tree=${_ps_root:-unknown}"
		echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		echo "host=$(hostname 2>/dev/null)"
		echo "builder=$$"
		for _ps_kv in "$@"; do echo "$_ps_kv"; done
	} > "$_ps_file.tmp.$$" && mv -f "$_ps_file.tmp.$$" "$_ps_file"
	unset _ps_file _ps_kind _ps_scope _ps_root _ps_head \
	      _ps_dirty _ps_dsrc _ps_dlist _ps_kv
}

# prov_get <stampfile> <key> -- empty if absent.
prov_get() {
	[ -f "$1" ] || return 0
	sed -n "s/^$2=//p" "$1" | head -1
}

# prov_header <label> [stampfile] -- one or two lines describing what is about
# to be used.  If the stamp says the artifact was built with uncommitted edits
# in its OWN source, the warning is the FIRST line printed, before any result,
# so it cannot be discovered three lanes later.
#
# Returns 0 clean, 1 DIRTY, 2 NO STAMP.  The two are different findings and a
# caller must be able to treat them differently: dirty is a caveat on a result
# that is still a result, while an artifact with no stamp at all has no known
# origin and is the thing a consistency check should refuse.
prov_header() {
	_ph_label=$1; _ph_f=${2:-}; _ph_rc=0
	if [ -n "$_ph_f" ] && [ -f "$_ph_f" ]; then
		_ph_c=$(prov_get "$_ph_f" commit)
		_ph_d=$(prov_get "$_ph_f" dirty)
		_ph_ds=$(prov_get "$_ph_f" dirtysrc)
		_ph_t=$(prov_get "$_ph_f" tree)
		_ph_b=$(prov_get "$_ph_f" built)
		if [ "${_ph_ds:-0}" -gt 0 ] 2>/dev/null; then
			echo "!! $_ph_label WAS BUILT FROM A DIRTY TREE ($_ph_ds uncommitted file(s) in its own source)"
			echo "!! it matches NO commit -- do not report a failure from it as a source bug"
			echo "!!   $(prov_get "$_ph_f" dirtyfiles)"
			_ph_rc=1
		fi
		echo "== $_ph_label: commit $(echo "$_ph_c" | cut -c1-8) dirtysrc=$_ph_ds dirty=$_ph_d built $_ph_b"
		echo "==   tree $_ph_t"
	else
		echo "!! $_ph_label: NO PROVENANCE STAMP${_ph_f:+ ($_ph_f)} -- origin unknown"
		_ph_rc=2
	fi
	unset _ph_label _ph_f _ph_c _ph_d _ph_ds _ph_t _ph_b
	return $_ph_rc
}

# prov_now <label> [scope paths...] -- the CURRENT state of this tree, for
# harnesses that have no stamp to read (or want it beside one that they do).
prov_now() {
	_pn_label=$1; shift
	_pn_root=$(prov_repo)
	if [ -z "$_pn_root" ]; then echo "== $_pn_label: not a git tree"; return 0; fi
	_pn_h=$(git -C "$_pn_root" rev-parse HEAD 2>/dev/null | cut -c1-8)
	_pn_d=$(git -C "$_pn_root" status --porcelain 2>/dev/null | wc -l)
	if [ $# -gt 0 ]; then
		_pn_s=$(git -C "$_pn_root" status --porcelain -- "$@" 2>/dev/null | wc -l)
		echo "== $_pn_label: commit $_pn_h dirtysrc=$_pn_s dirty=$_pn_d tree $_pn_root"
	else
		echo "== $_pn_label: commit $_pn_h dirty=$_pn_d tree $_pn_root"
	fi
	unset _pn_label _pn_root _pn_h _pn_d _pn_s
}

# prov_id <file> -- the content identity of a build artifact.  sha1 of the bytes,
# short.  Used as the KERNEL LINK ID: `ld -k' bakes absolute kernel addresses
# into every loadable driver, so a driver is only valid against the exact
# kernel.out image it was linked from, and content is the only honest name for
# that -- an mtime says when, not which.
prov_id() {
	[ -f "$1" ] || { echo none; return 0; }
	sha1sum "$1" 2>/dev/null | cut -c1-12
}

# prov_srcid <tree> [scope paths...] -- the SOURCE identity of a build: WHICH
# SOURCE was compiled, not which bytes came out.  12 hex, or `unknown' when
# <tree> is not a git worktree (an unpacked release has no source to name, and
# its stamp's recorded id stands on its own).
#
# The output bytes cannot serve as this id.  Two builds of the compiler from
# one tree into two build directories differ, and differ ONLY there: the
# staging path is mapped into the debug info and the build-id note follows it.
# A content id would report every lane's private build of identical source as a
# different compiler -- an alarm on the normal case.  It is also the wrong
# question.  A compiler is the same compiler wherever it was built, and what a
# lane holding a bad object needs is which source to go and read.
#
# HEAD alone is not enough either: this tree is normally dirty in scope, and a
# bare commit id would call two lanes' different edits one compiler.  So the id
# covers uncommitted content too -- the diff against HEAD, plus the bytes of
# untracked files.  Scope is the paths that were compiled in, as everywhere
# else here: a change outside it did not change the compiler.
prov_srcid() {
	_pi_t=$1; shift
	git -C "$_pi_t" rev-parse HEAD >/dev/null 2>&1 || { echo unknown; return 0; }
	{
		git -C "$_pi_t" rev-parse HEAD
		git -C "$_pi_t" status --porcelain -- "$@"
		git -C "$_pi_t" diff HEAD -- "$@"
		git -C "$_pi_t" ls-files -o --exclude-standard -- "$@" |
		(cd "$_pi_t" && tr '\n' '\0' | xargs -0 -r sha1sum 2>/dev/null)
	} 2>/dev/null | sha1sum | cut -c1-12
	unset _pi_t
}

# prov_tc_check <toolchain-build-dir> <record-file> [shape] -- refuse a compiler
# that is not the one this build tree was made with.  Returns 0 to proceed, 1 to
# stop; the caller stops, because a sourced file must not decide that for it.
#
# <shape> is `checkout' (the default) or `release X.Y.Z'.  A release is pinned
# on purpose and its source tree is not on this machine, so only the identity
# half applies to it; running the staleness half would report every pinned
# release as stale the moment the checkout beside it moved on.
#
# Two different wrongs, both silent until now, both caught here:
#
#   STALE      the published compiler is behind its own source tree.  This is
#              the one that keeps happening: one build directory serves every
#              lane, so a compiler published hours ago is what a lane picks up
#              even after the bug it carries has been fixed and committed.  A
#              check that only compared commits would miss the other half of
#              it -- an edit made after the build, same commit, same tree --
#              so the comparison is against prov_srcid, which moves when
#              uncommitted content moves.
#
#   CHANGED    a build tree that recorded one compiler is offered another.  Its
#              existing objects came from the first; linking the two mixes
#              codegen from two compilers, which reads downstream as a bug in
#              whatever was compiled last.
#
# C900_TC_ACCEPT=1 proceeds and re-records, for the case where the operator
# knows -- a deliberate compiler upgrade, or a build tree already known clean.
prov_tc_check() {
	_tk_b=$1; _tk_rec=$2; _tk_shape=${3:-checkout}; _tk_why=
	_tk_s="$_tk_b/z8001/.provenance"
	_tk_id=$(prov_get "$_tk_s" tcid)
	if [ -z "$_tk_id" ]; then
		echo "!! TOOLCHAIN WITH NO SOURCE ID: $_tk_b" >&2
		echo "!!   no $_tk_s, or one written before ids existed." >&2
		echo "!!   Nothing can say which source this compiler came from." >&2
		echo "!!   Rebuild it: (cd ${_tk_b%/host/build} && make cc as ld)," >&2
		echo "!!   or, for a release, unpack one packed since ids existed." >&2
		return 1
	fi
	_tk_tree=$(prov_get "$_tk_s" tree)
	_tk_scope=$(prov_get "$_tk_s" scope)
	_tk_live=unknown
	if [ "$_tk_shape" = checkout ] && [ -n "$_tk_tree" ] && [ -d "$_tk_tree" ]; then
		# shellcheck disable=SC2086
		_tk_live=$(prov_srcid "$_tk_tree" $_tk_scope)
	fi
	_tk_was=$(prov_get "$_tk_rec" toolchain_id)
	if [ "$_tk_live" != unknown ] && [ "$_tk_live" != "$_tk_id" ]; then
		_tk_why="STALE TOOLCHAIN"
		echo "!! STALE TOOLCHAIN: the published compiler is behind its own source." >&2
		echo "!!   built from source id $_tk_id (commit $(prov_get "$_tk_s" commit | cut -c1-8), $(prov_get "$_tk_s" built))" >&2
		echo "!!   $_tk_tree is now source id $_tk_live (commit $(git -C "$_tk_tree" rev-parse --short=8 HEAD 2>/dev/null))" >&2
		echo "!!   scope: $_tk_scope" >&2
		echo "!!   compiler: $_tk_b" >&2
		echo "!! The compiler's source has moved since it was built.  A fix that is in the" >&2
		echo "!! tree -- committed or not -- is NOT in the compiler you would use." >&2
		echo "!! Rebuild it: (cd $_tk_tree && make cc as ld)." >&2
		echo "!! If another lane owns that checkout, take your own -- git worktree add, build" >&2
		echo "!! it, and set C900_TOOLCHAIN to it.  C900_BUILD alone does not reach here: a" >&2
		echo "!! consumer reads <toolchain>/host/build and cannot see a private build dir." >&2
	elif [ -n "$_tk_was" ] && [ "$_tk_was" != "$_tk_id" ]; then
		_tk_why="TOOLCHAIN CHANGED"
		echo "!! TOOLCHAIN CHANGED under an existing build tree." >&2
		echo "!!   ${_tk_rec%/*} was built with source id $_tk_was" >&2
		echo "!!     ($(prov_get "$_tk_rec" toolchain), commit $(prov_get "$_tk_rec" toolchain_commit | cut -c1-8), recorded $(prov_get "$_tk_rec" recorded))" >&2
		echo "!!   the compiler now offered is source id $_tk_id" >&2
		echo "!!     ($_tk_b, commit $(prov_get "$_tk_s" commit | cut -c1-8), built $(prov_get "$_tk_s" built))" >&2
		echo "!! Its objects came from the first compiler; a link would mix two codegens." >&2
		echo "!! Build from a clean build directory, or keep the compiler you had." >&2
	fi
	if [ -n "$_tk_why" ]; then
		if [ -n "${C900_TC_ACCEPT:-}" ]; then
			echo "!! C900_TC_ACCEPT is set -- proceeding, and recording $_tk_id." >&2
		else
			echo "!! Refusing to build.  C900_TC_ACCEPT=1 proceeds anyway." >&2
			return 1
		fi
	fi
	mkdir -p "${_tk_rec%/*}"
	{
		echo "kind=consumer-toolchain"
		echo "toolchain_id=$_tk_id"
		echo "toolchain=$_tk_b"
		echo "toolchain_commit=$(prov_get "$_tk_s" commit)"
		echo "toolchain_dirtysrc=$(prov_get "$_tk_s" dirtysrc)"
		echo "toolchain_built=$(prov_get "$_tk_s" built)"
		echo "recorded=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	} > "$_tk_rec.tmp.$$" && mv -f "$_tk_rec.tmp.$$" "$_tk_rec"
	unset _tk_b _tk_rec _tk_shape _tk_why _tk_s _tk_id _tk_tree _tk_scope _tk_live _tk_was
	return 0
}

# prov_pub_check <builddir> <artifact> <dir-in-this-tree> -- refuse to PUBLISH
# over an artifact that a DIFFERENT source tree published.  Returns 0 to
# proceed, 1 to stop; the caller stops, as with prov_tc_check.
#
# The consumer half of this problem (prov_tc_check) catches a wrong compiler at
# the build that would have used it.  This is the producer half, and it is the
# earlier and cheaper place to catch the same thing: one build directory serves
# every lane by default, so publishing here silently replaces the compiler every
# other lane is running out of that directory -- which is how four lanes came to
# share one nobody had asked for.  Cross-lane publication is a legitimate thing
# to do; it is not a legitimate thing to do by accident, so it is made explicit
# rather than default, the way check-boot refuses a kernel git already has.
#
# The comparison is the artifact's own `tree' stamp against the tree this script
# is running from.  Two `git worktree' checkouts of one repository have
# different toplevels and are, correctly, different trees here: that is the
# whole point of taking one.
#
# C900_PUBLISH_ACCEPT=1 proceeds, for the deliberate case.
prov_pub_check() {
	_pp_b=$1; _pp_a=$2
	_pp_mine=$(prov_repo "$3")
	_pp_was=$(prov_get "$_pp_b/$_pp_a/.provenance" tree)
	[ -n "$_pp_was" ] && [ -n "$_pp_mine" ] && [ "$_pp_was" != "$_pp_mine" ] || {
		unset _pp_b _pp_a _pp_mine _pp_was; return 0; }
	echo "!! CROSS-TREE PUBLISH: $_pp_b/$_pp_a was published by another source tree." >&2
	echo "!!   there now: $_pp_was" >&2
	echo "!!     (commit $(prov_get "$_pp_b/$_pp_a/.provenance" commit | cut -c1-8), built $(prov_get "$_pp_b/$_pp_a/.provenance" built))" >&2
	echo "!!   this build: $_pp_mine" >&2
	echo "!! Publishing would replace the compiler every consumer of that directory runs," >&2
	echo "!! including builds in flight, with one built from source they did not choose." >&2
	echo "!! Publish somewhere of your own instead -- set C900_BUILD here, and" >&2
	echo "!! C900_TC_BUILD to the same path in the consuming tree (both halves: C900_BUILD" >&2
	echo "!! alone moves only where this script emits, not where a consumer reads)." >&2
	if [ -n "${C900_PUBLISH_ACCEPT:-}" ]; then
		echo "!! C900_PUBLISH_ACCEPT is set -- publishing over it anyway." >&2
		unset _pp_b _pp_a _pp_mine _pp_was
		return 0
	fi
	echo "!! Refusing to publish.  C900_PUBLISH_ACCEPT=1 proceeds anyway." >&2
	unset _pp_b _pp_a _pp_mine _pp_was
	return 1
}
