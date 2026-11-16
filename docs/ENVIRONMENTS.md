# Compiler environments: compiling on the C900

An environment is a host directory holding a Z8001 compiler, assembler,
linker, archiver, C library and headers, laid out at the guest paths the
driver searches. A guest mounts it and builds; the host updates it in place.

```
make env                # ours -> host/build/env/ours
make env CCENV=inherited
make env-mwc1985

# from a release: unpack the z8001 archive and compose from it
tar xzf c900-toolchain-v1.2.3-z8001.tar.gz
sh host/build-env.sh -R c900-toolchain-v1.2.3-z8001 -o /tmp/env ours
```

No release archive has this shape. Each archive is `bin/`, `lib/` and
`usr/include` for the machine its name gives; moving the passes to `lib/`
and renaming `crt0.o` to `crts0.o` and `libc-z8001.a` to `libc.a` is
`build-env.sh`'s job. An environment composed with `-R` matches a
checkout-composed one except for `bin/ar`, which is cross-built from
`src/ar/ar.c`, and its provenance lines.

Consumers find an environment through `$C900_TOOLCHAIN`, or `$C900_ENV` when
it was composed from a release. The emulator is found as `host/runner.sh`
finds it: `$C900_EMU`, then `$PATH`, then sibling checkouts.

A directory rather than a disk image: the host changes it in place and the
next guest run sees the change, with nothing to repack.

## Layout

```
host/build/env/ours/
    bin/   cc as ld ar
    lib/   cc0 cc1 cc2 crts0.o libc.a libm.a
    usr/include/
    CCENV          whose compiler this environment holds
```

The driver (`src/cc/coh/cc.c`) finds its parts by path:

| part | how `cc` finds it |
|---|---|
| `cc0` `cc1` `cc2` | searched on `LIBPATH`, default `/lib:/usr/lib` |
| `crts0.o` | on `LIBPATH`, under that name |
| `libc.a`, `libm.a` | on `LIBPATH`, as `makelib()` composes `lib` + name + `.a` |
| `as` `ld` | searched on `PATH`, default `:/bin:/usr/bin` |

`ar` is not a pass, but library builds need it and the guest is minimal.

### `mwc1985`: the system compiler

The 1985 binaries built the kernel, drivers and boot ROM, which name the
kernel headers by absolute guest path (`cc -I/usr/sys/z8001/h`). So
`mwc1985` carries more:

```
host/build/env/mwc1985/
    bin/   cc ccx as ld nld ar nm size
    lib/   cpp cc0 cc1 cc2 cc3 crts0.o libc.a
    usr/include/
    usr/sys/h/          the kernel's headers
    usr/sys/z8001/h/    the Z8001 machine headers
    VARIANT             the variant word per kind of artifact, with evidence
    CCENV
```

* `nld` links the 32-bit objects (`LF_32`) these passes emit.
* `VARIANT` travels with the binaries: the wrong word silently builds objects
  the machine never shipped. `commodore-900-bios` keeps its own copy.

The 1985 library, startup and kernel headers are not vendored here. Name a
root: `C900_STOCK_ROOT=…/commodore-900-bios/vendor/mwc-1985` for the 1985
originals, or a built COHERENT staging root.

Its `cc` is a script that execs `/bin/ccx` by absolute path, so it must be
installed in the guest's `/bin`, not run from a mount.

## Using it from the guest

**Point the driver at the mount.** `-t` names the parts to relocate and `-B`
the colon-separated list to take them from:

```
cc -t012sdlr -B/mnt/env/bin:/mnt/env/lib -I/mnt/env/usr/include -c x.c
```

`-t012sdlr` is cc0, cc1, cc2, as (`s`), ld (`d`), libc (`l`), crts0.o (`r`).
The tests use this form.

**Install it.** Copy `bin/*` to `/bin`, `lib/*` to `/lib` and `usr/include` to
`/usr/include`; plain `cc x.c` then works. Use a system whose `/usr` is on the
root filesystem, or `/etc/rc` mounts a separate `/usr` over the headers.

**Ship it on the image.** `commodore-900-dist`'s `os/dist/lists/toolchain.list`
installs `ours` in `/usr/bin`, `/usr/lib` and `/usr/include`, all on the
driver's default search paths. The `extended-dev` dist includes it. For
`CCENV=ours`, `build-env.sh` writes the source map
`hostbuild/build/.ulsrcmap` the dist cuts its `toolchain-src` package from,
and deletes it for the others.

`cc` writes intermediates to `/tmp`, which must exist and be writable.

## `CCENV`

An environment is a (compiler, C library, headers) triple:

| `CCENV` | compiler | library and headers |
|---|---|---|
| `ours` | this repository's, built for the target: the self-host `cc0/cc1/cc2` (`build-selfhost.sh`), driver, assembler and linker (`build-native.sh`) | this repository's `src/` |
| `inherited` | a COHERENT tree's own, from its staging root | that root, `$C900_STOCK_ROOT` |
| `mwc1985` | `vendor/mwc-1985` (driver, `as`, `ld`, `nld`, `ar`) and the passes `cpp cc0 cc1 cc2 cc3` from the COHERENT userland checkout's `src/dist/lib` (`C900_MWC1985_PASSES` overrides) | `$C900_STOCK_ROOT` |

`CCENV` names a compiler, not an OS dist: `inherited` and `mwc1985` share one
library and header root. Neither namespace encodes a release number;
`mwc1985` names a fixed third-party release.

`make env` builds `ours` and its prerequisites. The others are selected from
roots built elsewhere, and `build-env.sh` refuses, naming the variable, when
an input is missing.

## Fallback dists

`make env-fallback` packs the composed `ours` and `mwc1985` roots as release
assets (`host/pack-fallback.sh`), each with a `.provenance` naming its
commits. Consumers place them with `make deps` and compile without a
toolchain or OS checkout. `ours` has consumers; `mwc1985` is kept for one
that wants the 1985 compiler without a checkout.

`pack-fallback.sh` refuses a root that is not a working compiler, and for
`mwc1985` also one missing `bin/nld`, `VARIANT`, `usr/sys/h` or
`usr/sys/z8001/h`.

The `fallback-N` tag is re-cut in place. The `toolchain <commit>` line in
`.provenance` tells cuts apart, which is why a dirty tree is refused. `make
deps` leaves an unpacked dist alone; `rm -rf external/<name>` takes a new cut.

## Verification

`build-env.sh` ends by running `tools/loutid -m z8001` over every file in
`bin/` and `lib/`, archive members included; any non-Z8001 file, such as a host
ELF binary, fails it:

```
host/build/env/ours/bin/as              ELF (a HOST binary)   <-- WANTED z8001
GATE EXIT=1
```

## Native build changes

`build-native.sh` builds the driver, assembler and linker for the target from
unshimmed source; the host shims are LP64 and glibc workarounds. The driver
needs:

* `-DX_OK=AEXEC -DR_OK=AREAD`: COHERENT 3.x `access.h` spells the modes
  `AEXEC`/`AREAD`.
* `-DVERSMWC=...`: the version string.
* `-DV8087=VMBASE+13` and friends: the i386/i8086 FP and OMF variant bits the
  option table names, mapped to one unused machine slot inside
  `VMBASE..VMAXIM`.
* `getpass` renamed `ccgetpass` in a scratch copy, to avoid libc's
  `getpass(3)`.

`src/cc/coh/cc.c` itself defaults, under `#if Z8001`, to the segmented model
`VSEG` (the donor's `VSMALL` truncates pointers) and to `VREADONLY` (the
headers spell `const` as `readonly`).

## Guest compile cost

Under `commodore-900-emulator`, COHERENT 3.5 booted from the `extended-build`
dist, environment mounted from a rendered medium:

| workload | host wall clock |
|---|---|
| boot, mount, umount, no compiling | 23 s |
| `make` over 8 one-function files | 33 s, about 10 s compiling |
| `make` over a 2-file `<stdio.h>` program, link and run | 37 s, about 14 s building |

About 1-7 s per source file after a fixed 20 s.

Drive builds with `make`: each long command line typed at the console costs
about 20 s of input pacing. The guest's clocks disagree with each other (the
RTC and the kernel tick differ about 250x), so quote host time.
