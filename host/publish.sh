# publish.sh -- build into a private directory, publish by rename.  For `.', not
# for exec; the caller has already set $HERE.
#
#	. "$HERE/publish.sh"			sets $BUILD
#	OUT=$(stagedir libc-z8001)		private $BUILD/libc-z8001.$$, emptied
#	publish_dir libc-z8001			$BUILD/libc-z8001 -> that directory
#	publish_file "$OUT/as" as-z8001		one file, same guarantee
#	stagedir/publish_dir/publish_file name an artifact under $BUILD;
#	stage_at/publish_at/publish_file_at take a full path, for a tree the
#	caller was told where to put.
#	stagecopy seeds the staging tree from what is published, for a build
#	that keeps an object cache or writes only the targets it was named.
#
# $BUILD is the build directory: $C900_BUILD when set, host/build otherwise.
# One directory serves every lane by default, and everything in the tree spawns
# compilers and reads libraries out of it while builds are running.
#
# A published name is a symlink that swings onto a finished staging directory in
# a single rename, so a reader resolving it at any instant gets one complete
# artifact or the previous one -- never a half-built tree, never nothing, and
# never a mixture of two concurrent builds.  A binary already exec'd out of the
# old directory keeps running after it is removed: the kernel holds the inode.
#
# Callers trap on their staging directory, so a build that fails publishes
# nothing and leaves the previous artifact standing.
BUILD="${C900_BUILD:-$HERE/build}"
mkdir -p "$BUILD"

stage_at() {	# stage_at <path> -- print an empty private directory for <path>
	# Leftovers: a run killed before it could clean up, or the loser of two
	# publishes racing to swing the same name.  Anything from today may
	# belong to a build running right now, so only yesterday's go.
	find "$BUILD" "${1%/*}" -maxdepth 1 -mtime +0 -name '*.[0-9][0-9]*' \
	     -exec rm -rf {} + 2>/dev/null || true
	rm -rf "$1.$$"
	mkdir -p "$1.$$"
	echo "$1.$$"
}

publish_at() {	# publish_at <path> -- point <path> at its staging directory
	_b=${1##*/}
	_d=${1%/*}
	_old=''
	if [ -L "$1" ]; then
		_old=$(readlink "$1")
	elif [ -d "$1" ]; then
		# Migration off the plain directory these used to be.  The rename
		# is what keeps the gap to a single syscall.
		_old="$_b.legacy.$$"
		mv -T "$1" "$_d/$_old"
	fi
	ln -s "$_b.$$" "$_d/.$_b.link.$$"
	mv -T "$_d/.$_b.link.$$" "$1"
	[ -n "$_old" ] && rm -rf "$_d/$_old"
	return 0
}

publish_file_at() {	# publish_file_at <src> <path> -- install one file at <path>
	cp "$1" "$2.$$"
	chmod --reference="$1" "$2.$$"
	mv -f "$2.$$" "$2"
}

stagecopy() {	# stagecopy <name> -- stagedir seeded from what is published now
	# The copy preserves mtimes, so an object that was up to date still is.
	_s=$(stage_at "$BUILD/$1")
	if [ -d "$BUILD/$1" ]; then cp -a "$BUILD/$1"/. "$_s"/; fi
	echo "$_s"
}

stagedir()     { stage_at "$BUILD/$1"; }
publish_dir()  { publish_at "$BUILD/$1"; }
publish_file() { publish_file_at "$1" "$BUILD/$2"; }
