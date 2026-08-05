# `src/cc` — provenance and the patch verdict table

`src/cc` is the **source of record** for the Z8001 C compiler. It vendors the
MWC 4.2.12 machine-independent passes (donor `v4.2.12/c`, pristine at copy
time) with the Z8001 machine layer developed for this project, laid out
in the donor's own shape (`n0/ n1/ n2/ n3/ common/ h/ coh/` + `<pass>/z8001/`).

The host cross-build previously applied ~20 build-time patches to the donor
source. Consolidating required classifying each one:

- **BAKED** — a genuine defect (or a Z8001-target requirement) that is wrong on
  *any* platform including the native C900: applied to the committed source
  here, permanently.
- **HOST SHIM** — an LP64 / glibc / gcc-strictness workaround needed only to
  build the compiler *on the Linux host*: stays in the host harness
  (`host/build-cc.sh`), applied to a scratch copy at build
  time. The committed source stays native-faithful (MWC cc accepts it as-is).

## BAKED into this tree

**This table is generated.** The record is `src/cc/MI-PATCHES`, one justified
record per divergence, keyed to the file's content by SHA-256; `make mi-table`
renders it here and `make check-mi` (which `make check` runs) fails if this page
is stale, if a machine-independent file differs from the donor with no record,
or if a recorded file has changed since its justification was written. Editing
the table below changes nothing and will be overwritten — the last time it was
hand-maintained it drifted three rows and a false claim.

<!-- BEGIN GENERATED BAKED -- from src/cc/MI-PATCHES, `make mi-table' -->
| File | Fix | Why it is native-correct |
|---|---|---|
| `n0/expr.c` | `d_dp != NULL` guard before `d_dp->d_type == D_FUNC` | NULL deref on every `arr[i]` decay; survivable only because Coherent mapped page 0 |
| `n0/stat.c` | signedness guard on `bitcompat()` for DIV/REM/SHR/ASHR (+ op-assign) | mixed-signedness divide/shift skipped the conversion that selects signed vs unsigned instructions |
| `n0/cc0.c` | `file[NFNAME-1] = 0` after `strncpy` in `setfname()` | strncpy leaves the name unterminated at exactly NFNAME; `sput()` then scans past the buffer |
| `n0/get.c` | terminal-EOF guard: NULL `ifp` after `fclose`, return EOF on re-entry | use-after-free + double `fclose` when error recovery pulls tokens past EOF |
| `n0/cc0key.c` | keyword tokens wrapped in `{TOK t; char id[];}` with inline storage | the bare-TOK form relies on link-order adjacency of the id string -- an ABI accident, not a guarantee; the wrapper is layout-identical where the accident held and correct everywhere |
| `n1/out.c`, `n1/sel0.c` | `!islong(...)` -- a long compare-vs-0 must not fold to a direct operand test | Z8001: no test-long reaches the relop selector; the fold drops the explicit `CPL n,#0`. (Z8001-target edit: this tree builds the Z8001 compiler only. The donor i386 coder needs the fold; the i386 host harness uses pristine donor source.) |
| `n1/out.c` | subgoal-output sites skip re-materializing an operand already a `REG` leaf | Z8001 far pointers arrive in a register pair as a REG leaf; re-routing one through `outtree` derefs a garbage `t_lp` (FUZZ-13 SIGSEGV) |
| `n1/mtree0.c` | `x op= 0' folding CONVERTs a narrower lvalue to the node's promoted type instead of retyping it in place; an effect context keeps the retype | the value of `x op= 0' is x at the PROMOTED type, so retyping the lvalue node widens the object's own load -- on the Z8001 `char c; v = (c += 0)' emitted `ld r0,-1(r13)', a WORD load of a one-byte auto, reading the neighbouring byte as the high half (big-endian, so v became c<<8|junk). Confirmed at HEAD and fixed: the load is now `ldb rl0,-1(r13)' + `extsb', identical to plain `v = c'. Reached by AADD/ASUB/AOR/AXOR/ASHL/ASHR (AAND is rewritten to ASSIGN above); `c += 1' was never affected, only the zero fold. MEFFECT reads nothing, so it keeps the cheaper retype and no code moves |
| `n1/mtree0.c` | the SUB->ADD constant canonicalization keeps the node's own type (donor stamped `IVAL_T` "Signed") | the stamp writes junk signedness over the C type (`u - 1` labeled signed, `p - c` labeled non-pointer); the Z8001 MD selects signed-vs-unsigned divide/shift by node type, and the MD `fixaddtype` now preserves node signedness through reassociation (FUZZ-5), so the stamp must not lie. Donor i386 relied on the re-derive repairing it each pass |
| `n0/expr.c` | LPAREN cast: don't collapse a bit-compatible cast that CHANGES signedness onto a DIV/REM/SHR/ASHR/ADIV/AREM node -- keep the CAST node | the collapse retypes the op in place, making `(int)(u/d) >> k` and `(int)((u/d) >> k)` the same tree with opposite correct shifts (FUZZ-20); the surviving node is the only disambiguator. Same guard the `n0/stat.c` return-coerce row already carries; cc1 selects the kept convert at zero cost (leaves.t same-kind identity) |
| `common/bput.c` | `putc(b, ofp) == EOF && ferror(ofp)` -- EOF alone is not failure | the native putc fast path returns the stored CHAR (`*_cp++ = c`), so byte 0xFF reads back as -1 == EOF; the donor's own `#if 0` comment describes this bug class but its `b &= 0xFF` guard cannot fix the macro's return value. Any IR stream containing an 0xFF byte (every negative ival) aborted "temporary file write error" on the target; the host putc returns an int and never trips it |
| `n0/z8001/bind.c`, `h/z8001/mch.h`, `h/cc0.h` | word-align structure members: `fieldalign()` rounds a normal member up to its natural alignment (1 for a byte object, 2 for any wider type/pointer) via new `memalign()`; new `salign()` gives the struct itself the alignment of its widest member; `saligntype()` macro -> `salign()`; `extern int salign()` declared | the donor i8086 template packs members to byte offsets, which the i8086 tolerates (unaligned word/dword access); the Z8000 does NOT -- a word/long/far-pointer read at an odd address returns the wrong bytes. getty's `struct stable` put `char *s_lmsg` at odd offset 5, so `LDL 5(Rn)` loaded a garbage far pointer -> strlen SIGSEGV (the login-prompt blocker). Aligning is a hardware requirement, so the original MWC Z8001 compiler must do the same. Codegen cost: field access is still one load and array indexing still one MULT/scale -- only the displacement/size *immediate* changes, so no instruction-count change; the sole effect is a few padding bytes in mixed sub-word/word structs, which the original ABI also carries. Efficiency parity vs the original is an OPEN follow-up, to be A-B'd against the original HD-extracted binaries via loutdis (NOT a self-comparison). All difftest generators (struct/bitfield/2darr/strptr/torture) still match gcc |
| `n3/itree.c` | the `op >= ETCBASE` arm `sprintf`s into `opid` before `opid` points anywhere: give it a local buffer | writes through an uninitialized pointer. The arm fires only on an out-of-range tree opcode -- i.e. on a corrupt or foreign intermediate file, which is precisely when someone runs cc3 -- so the tool crashes exactly where it is supposed to report |
| `n3/z8001/igen.c` | bound the `ENTER` segment-directive lookup by `NSEGDIR` | `seg_enter[]`/`seg_leave[]` have an entry per LOADABLE segment (6); `ops.h` defines 11 segment codes, and `SANY` and up would index past the end. The i8086 template has the same unbounded index |
| `n0/expand.c` | `dspush(DS_IEOF, 0)` -> `dspush(DS_IEOF, NULL)` | K&R: the callee takes a pointer, and a bare `0` passes an `int`. On the Z8001 that is 2 bytes into a 4-byte slot, so the argument and everything after it is misaligned. The project's most recurring bug class; harmless on the host, wrong on the target |
| `n0/fold.c` | constant folding widens each operand by ITS OWN signedness, not the goal type's | an unsigned operand promoted into a wider signed goal (unsigned int + long) is value-preserving and must ZERO extend; a signed operand promoted into an unsigned goal must SIGN extend. Keying both off the goal type mis-widens one or the other. The operation's own signed/unsigned semantics still use the goal `uflag` |
| `n1/node.c` | `(unsigned) tp->t_ival` -> `(uival_t) tp->t_ival` | `unsigned` is the HOST's width; `uival_t` is the IR's. Casting a target constant through host `unsigned` truncates it on any host wider than the target |
| `n0/cc0.c`, `h/z8001/cppmch.h` | new `OLDMACHINE` ("Z8001"), predefined beside `MACHINE` ("_Z8001") | the June 1985 compiler's standalone cpp predefines the target unprefixed, and the COHERENT 3.2 sources select on that spelling: `<l.out.h>` takes the **n.out object layout** under `#ifdef Z8001`, `sbrk()` its segment-crossing arithmetic, `exec()` its shared-library arms. A compiler that defines only `_Z8001`/`__Z8001__` builds the wrong layout silently, so this is a target-macro requirement, not a convenience. Guarded by `#ifdef`, so a machine layer that does not define it is unchanged |
| `n0/get.c`, `n0/cpp.c` | in `isvariant(VCPP)` (standalone-preprocessor) runs only: a quote literal ends at the newline instead of erroring, and a non-C byte is copied instead of erroring | VCPP is the mode in which cc0 is a **preprocessor**, and the text it copies is in the CONSUMER's language, not C. The assembly the kernel build preprocesses (`md.s`, `mmas.s`, `scroll.s`) has apostrophes and a stray ESC inside `/`-comments; as C those are "new line in character literal" and "illegal cpp character", and the unterminated-quote scan then ran on past the end of the line. The 1985 standalone cpp copies both without comment, and our output now matches its output on `md.s` token for token. Nothing changes on the compile path: `VCPP` is never set there |
| `h/stream.h` | new `_WIN32` arm selecting `"rb"`/`"wb"`/`"r+b"` with the pass-to-pass accessors, and the `COHERENT` arm yields to it | the streams cc0/cc1/cc2 pass between them are BINARY, and the host build defines `COHERENT`, whose arm asks for text mode. On Windows that turns every 0x0A written into 0x0D 0x0A and the objects are garbage, silently -- nothing about the compile fails. BAKED, not a shim: it is `#ifdef`-guarded on a platform macro exactly like the donor's own `MSDOS` and `GEMDOS` arms, which are there for the same reason, so the donor plainly anticipated the arm and no other target sees it |
| `h/var.h` | new variant code `VKERN` (9) | the kernel model: numeric frame/auto addresses carry the system stack segment (SS = 0x3F) rather than the flat model's segment 0. Variant codes are a shared namespace, so the definition has to live with the others; nothing machine-independent reads it |
| `n1/sel0.c`, `n1/code.c`, `h/cc1.h` | `store()` records the subtree each spill was made for (`storesub[]`, beside the existing `storelist[]`), and a second demand for the same subtree is a `cbotch` naming the operator instead of a silent re-enqueue | `store()` spills a subtree to a stack temp and enqueues `temp = <subtree>`; if selecting that assignment cannot address the subtree either, the donor enqueues it again with the same tree and the same registers, so the list grows without converging and NSTORE decides only how long the loop runs (ICE 5149). One subtree now gets one store. This is a termination guarantee, not a codegen change: no accepted program compiles differently, and the diagnostic lands at the demand rather than as an exhausted table. The native cost is the array itself -- NSTORE is 20 off the i386 arm, so 20 near pointers of BSS in cc1, which has room; the loop it bounds is over at most 20 entries and runs once per store, so it is invisible beside selection |
| `n1/reg0.c` | `rallo()` keeps one register that can address: when an allocation would take the last register whose `r_lvalue` is non-empty, a register that can hold the kind but could never address it takes the value instead. A pointer-typed value is exempt | the reserve is decided entirely by the machine register table's `r_lvalue` -- the set of kinds a register can be dereferenced through -- so it is machine-independent code reading a machine-dependent fact, and on a machine where every register can address (the donor's i386) `hold` is never set and the function returns exactly what the donor returned. On the Z8001 that set is small and exhaustible: a value in the last addressable register cannot be undone, the selector then spills, and the spilled assignment wants the address it could not form -- ICE 5149, which the original 1985 compiler fails on too. Measured over 1017 sources (798 compiling), the reserve fires so rarely that exactly two objects move, awk5.o 1915 -> 1910 instructions and the kernel's bio.o 1523 -> 1521, both FEWER, and the 13 sources shared with the 1985 compiler are unchanged -- so it costs nothing against the efficiency baseline |
| `coh/cc.c` | `#if _Z8001` arms in the driver's variant defaults: `VSEG` + `VREADONLY` instead of `V80186`, and the model-selection block chooses `VLARGE` unless `-VSMALL` was asked for, in place of the Intel OMF rules | the C900's C model is the segmented one -- a pointer is a two-word seg:offset (`h/z8001/varmch.h` VSEG) -- and the donor's default is Intel's, so a driver taking it would compile every program for a flat Z8002 with truncated pointers. `VREADONLY` goes with it because the COHERENT 3.2 headers spell const `readonly` (`ctype.h`) and without the keyword they do not parse. The Intel block below forces the small model outside OMF output; there is no OMF on this machine, and `VSEG`/`VNSEG` are one machine-dependent slot apart and must never both be set. Both arms are `#if _Z8001`, so no other target sees them |
<!-- END GENERATED BAKED -->

## HOST SHIMS (stay in `build-cc.sh`, never committed here)

| File(s) | Shim | Host-only because |
|---|---|---|
| `n0/sharp.c` | `getline` → `mwc_getline` | collides with POSIX/glibc `getline`; Coherent libc has no such symbol |
| `n1/*.c` (all) | `select` → `iselect` | collides with `select(2)`; Coherent 3.2 has no select |
| `n0/dbgt0.c`, `n0/double.c`, `n0/init.c`, `n0/size.c`, `n0/expr.c` (`bstring`) | drop `static` from defs that follow an implicit-extern call | gcc strictness; MWC cc accepts the K&R idiom |
| `common/tcpy.c` | same K&R `static` drops (`icpy`, `bcpy`) | same |
| `n2/cc2sym.c`, `n2/optim.c` | same K&R `static` drops (`symbucket`, `precedes`) | same |
| `common/diag.c` | replaced by the stdarg host port | the original walks `&args` up the stack — UB that segfaults on x86-64; correct on the native calling convention |
| (`common/i386/geno.c`) | stdarg host port (i386 harness only) | same class; the Z8001 pass set does not link geno |
| `n1/` + `shellsort.c` | host adds a shellsort.c | Coherent libc routine the host lacks; the port is `host/port/shellsort.c` |
| `coh/tabgen.c` | `ungetc` → `tg_ungetc` (host tabgen build) | pushback global collides with glibc `ungetc` |
| shim headers `path.h`, `access.h` | vendored in `host/include/` | the host lacks them; `path.h` pulls `access.h` |
| `h/i386/mch.h` | the i386 harness's IR-width header | this tree carries only `h/z8001/mch.h`; the i386 harness stays donor-sourced |

## Not vendored (and why)

- **`c/cpp`** — the standalone preprocessor. cc0 integrates preprocessing
  (`n0/cpp.c`, `n0/sharp.c`, `n0/expand.c`), and cc0's own `VCPP` variant is
  the preprocessor-only mode; `host/cppz` gives that mode the `cpp [-P] IN
  [OUT]` command line the OS tree's assembly rules call, so no separate
  program is needed.
- **`c/n3`** — the `cc3` pass, which **prints the intermediate language** ("It
  understands all favours of intermediate files; that is, it understands both
  trees and CODE nodes!", `n3/cc3.c`). **Now vendored and built** — `src/cc/n3`
  (MI, from donor `v4.2.12/c/n3`) + `src/cc/n3/z8001` (machine layer, templated
  on the donor `i8086`, not `i386`) + `common/z8001/` (the `regnames`/`tynames`/
  `mdlnames`/`mdonames` tables the other passes do not link, because `TINY=1`
  compiles out the `-S` dumps that are their only other reader). It is what the
  driver's existing `-3` (`coh/cc.c:151`) invokes, and it replaced the
  hand-rolled `Z1DBG` tree dumper that used to sit in the machine-INDEPENDENT
  `n1/code.c` (the `Z1DBG` row is gone; what `n1/code.c` still carries is the
  `store-converge` record's one declaration). cc3 still emits no code, so it remains
  irrelevant to the #16 codegen gap; the 18,282-byte `cc3` in the original
  distribution is a debugging tool and never was a fourth code-producing pass.
- **`c/old`, `<pass>/i386`** — not on the Z8001 path.
- **`coh/number.c`, `siz286.c`, `sizomf.c`, `profil.c`** — other-target
  utilities; `coh/` here carries `cc.c` (the driver — note its existing
  `-DZ8001CC` cross target) and `tabgen.c`.
- **`optab.c`** — the decoder-inventory table, input to the development
  oracle only; it lives in `tools/isa/`. The tables the compiler actually
  compiles are `src/cc/generated/{opcode.h,OF_styles.h}`.

## Build

- **Native (self-host, the deliverable):** `make` here — tabgen → tables →
  cc0/cc1/cc2/cc3. The native driver (`coh/cc.c`) is a later bring-up item.
- **Host (cross, the working rig):** `host/build-cc.sh`
  copies this tree to scratch, applies the HOST SHIMS above, and builds
  `cc0-z8001`/`cc1-z8001`/`cc2-z8001`/`cc3-z8001` + `tabgen` with gcc. The shims are
  text-level and asserted to apply (a failed shim fails the build), so drift
  between this tree and the host build is caught immediately.
