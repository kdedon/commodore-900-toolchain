# DEPS -- what this repository consumes from other repositories.
#
#	name  kind  url  [ref]  [asset]  [dir]
#
# Read by `make deps' (host/deps-fetch.sh).  The build resolves dependencies
# through the script; a named variable wins over anything here.
#
# kind release  a published archive, pinned to <ref>
#
#   emu       emulator (our fork), built by our workflow
#
# The C library, the headers and crts0 are not an edge: they are in src/,
# beside the compiler that builds them.

emu       release  https://github.com/kdedon/commodore-900-emulator   latest  c900-@REF@-@HOST@
