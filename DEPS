# DEPS -- what this repository consumes from other repositories.
#
#	name  kind  url  [ref]  [asset]
#
# Read by `make deps' (host/deps-fetch.sh) and by CI.  It is a statement of
# what is consumed, not a resolver: nothing in the build reads this file.
# host/deps.sh still does the finding, and a named variable still wins.  The
# name column is the dep name that resolver answers to, so `make deps' can ask
# it whether an edge is already satisfied before placing anything.
#
# kind git = one of ours, cloned beside this repository and left FLOATING on
# <ref>.  We can fix our own repositories, so a float costs at most a broken
# build we own, and the release stamp records which commit actually produced an
# artifact -- strictly more truthful than a pin, which records only what a build
# was supposed to use.  There is no lockfile: a lockfile is a pin in a hat.
#
# kind local = one of ours that IS NOT PUBLISHED: nothing is fetched and the
# edge is satisfied only by a checkout the operator already has.  No line uses
# it today; `make deps' still implements it.
#
# kind release = a third-party BINARY, PINNED by tag and unpacked into deps/,
# which is gitignored.  We cannot fix the emulator and nothing about a binary is
# recoverable from our own history, so "which emulator ran this test" has to be
# a number chosen in advance.  Bump it deliberately.
#
# NEITHER EDGE IS NEEDED TO BUILD THE TOOLCHAIN.  `make', `make check-isa' and
# `make check-cc3tab' run from this repository alone.  The emulator is needed by
# the value assertions in `make check', which EXECUTE what they compiled; the
# COHERENT tree by `make libc', `make native', `make selfhost' and `make env',
# which build OS artifacts with the toolchain rather than the toolchain itself.
#
# That second edge closes a CYCLE -- COHERENT needs this repository to build
# anything, and this repository needs COHERENT's source to build the C library
# it ships against.  It is not an accident awaiting a refactor: the library's
# source belongs to the operating system and the compiler that compiles it
# belongs here.  It is also why there are no submodules anywhere in this
# project; the cycle forbids them outright.
#
# The COHERENT edge is a SNAPSHOT until that repository is published: the three
# directories this one compiles (os/include, os/libc, os/csu, plus cmd/ar.c),
# cut from a checkout by host/pack-coherent-os.sh and published as a release of
# ours.  It is a second copy of somebody else's source and it is pinned to the
# day it was cut, which is the whole objection to it -- so three things answer
# that rather than leaving it implicit:
#
#   * a CHECKOUT WINS.  host/deps.sh searches siblings first and deps/ last, so
#     anyone with the OS tree builds against the tree, not the snapshot.
#   * IT SAYS SO.  The archive carries .provenance naming the commit and the
#     date, and host/coherent-os.sh prints both, on stderr, in every build that
#     resolves to it.  "Built against COHERENT as of some Tuesday" is exactly
#     the failure mode; it cannot happen silently.
#   * THE TAG IS THE VERSION.  The release is tagged coherent-os-DATE-COMMIT
#     and the asset is that name, so bumping the pin is one legible edit and
#     the diff says which OS a build moved to.
#
# The packer refuses a dirty or unversioned tree for the same reason.  When
# commodore-900-coherent is published this line becomes `coherent git <url>
# main' and nothing else changes.
#
# With the snapshot placed, every stage runs in CI -- S2, S3, S4 and the
# COHERENT consumer link.  Where it is NOT placed they still do not run, and
# the run's verdict names each one and why, because a green badge over stages
# that never ran is the same lie as a gate that cannot fail.
#
# The emulator release is built by the workflow on OUR FORK, which packages
# bin/, rom/ and disk/ so that unpacking it is the whole installation.  Upstream
# publishes no releases; when it does, this line's url is the one-line change.
# Stating it rather than implying it: a dependency on a fork of a third party's
# work should not be something anybody discovers later.

coherent  release  https://github.com/kdedon/commodore-900-toolchain  coherent-os-2026-08-05-1cd93190  @REF@.tar.gz  coherent-os
emu       release  https://github.com/kdedon/commodore-900-emulator   v0.1  c900-@REF@-@HOST@
