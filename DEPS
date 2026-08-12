# DEPS -- what this repository consumes from other repositories.
#
#	name  kind  url  [ref]  [asset]  [dir]
#
# Read by `make deps' (host/deps-fetch.sh).  The build resolves dependencies
# through the script; a named variable wins over anything here.
#
# kind release  a published archive, pinned to <ref>
#
#   coherent  self-published OS snapshot (include, libc, csu) for cross-build
#   emu       emulator (our fork), built by our workflow

coherent  release  https://github.com/kdedon/commodore-900-toolchain  fallback-1  @REF@-coherent-os.tar.gz  coherent-os
emu       release  https://github.com/kdedon/commodore-900-emulator   v0.1  c900-@REF@-@HOST@
