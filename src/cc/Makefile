# src/cc/Makefile - the Z8001 C compiler, built ON the C900 by itself.
#
# The repository's own Makefile does the HOST cross-build of these same sources,
# through host/build-cc.sh, which applies the host-portability shims to a scratch
# copy first.  This one is the native build and takes them unshimmed.
#
# The object lists below are also THE list: host/srcman.sh reads them, so the
# host build compiles what this one does and refuses a .c under src/cc that no
# list names.  A scratch or backup copy belongs in a private directory or under
# $C900_BUILD, never beside the file it copies.
#
# Layout mirrors the MWC source shape: MI passes at n0/ n1/ n2/ (+ n3/, the
# intermediate-language printer cc3 reaches through `cc -3'), the Z8001 machine
# layer in <pass>/z8001/, headers in h/ and h/z8001/, pass-to-pass serialization
# in common/, and the tabgen-compiled selection tables in n1/tables/.  The
# preprocessor is inside cc0 (n0/cpp.c); there is no separate cpp pass.

CFLAGS=-O -DCOHERENT -Ih/z8001 -Ih -Icommon -Igenerated
LDFLAGS=

COMMON=	common/bget.o common/bput.o common/dget.o common/diag.o common/dput.o \
	common/getvar.o common/iget.o common/iput.o common/lget.o common/lput.o \
	common/makvar.o common/milnam.o common/mionam.o common/newlab.o \
	common/newseg.o common/nput.o common/segnam.o common/sget.o common/sput.o \
	common/talloc.o common/tcpy.o common/unbget.o

N0=	n0/cc0.o n0/cc0key.o n0/cc0sym.o n0/cpp.o n0/dbgt0.o n0/ddecl.o \
	n0/dope.o n0/double.o n0/etc.o n0/expand.o n0/expr.o n0/fold.o \
	n0/gcandt.o n0/gdecl.o n0/get.o n0/init.o n0/lex.o n0/locals.o \
	n0/sharp.o n0/size.o n0/stat.o n0/z8001/bind.o

N1=	n1/cc1.o n1/cc1sym.o n1/code.o n1/mtree0.o n1/mtree1.o n1/mtree3.o \
	n1/node.o n1/out.o n1/pool.o n1/reg0.o n1/sel0.o n1/sel1.o n1/snap0.o \
	n1/tree0.o n1/tree1.o \
	n1/z8001/altemp.o n1/z8001/amd.o n1/z8001/fixtop.o n1/z8001/gen1.o \
	n1/z8001/gen2.o n1/z8001/mtree2.o n1/z8001/mtree4.o n1/z8001/outmch.o \
	n1/z8001/reg1.o n1/z8001/sel2.o n1/z8001/snap1.o n1/z8001/table0.o \
	n1/z8001/table1.o n1/tables/macros.o n1/tables/patern.o

# cc3 prints the intermediate language -- both trees and CODE nodes.  It emits no
# code, so nothing in the pipeline depends on it; it links the machine NAME
# tables (common/z8001) that the other passes do not, because TINY=1 compiles
# out the -S dumps that are their only other reader.
N3=	n3/cc3.o n3/dbgt3.o n3/itree.o n3/z8001/icode.o n3/z8001/igen.o \
	common/z8001/mdlnam.o common/z8001/mdonam.o common/z8001/regnam.o \
	common/z8001/tyname.o

N2=	n2/cc2.o n2/cc2sym.o n2/dbgt2.o n2/emit0.o n2/getfun.o n2/optim.o \
	n2/z8001/afield.o n2/z8001/emit1.o n2/z8001/getcod.o n2/z8001/listing.o \
	n2/z8001/optab.o n2/z8001/outcoh.o n2/z8001/peep.o

TABLES=	n1/tables/aadd.t n1/tables/aand.t n1/tables/add.t n1/tables/adiv.t \
	n1/tables/aft.t n1/tables/amul.t n1/tables/and.t n1/tables/aor.t \
	n1/tables/arem.t n1/tables/ashl.t n1/tables/ashr.t n1/tables/assign.t \
	n1/tables/asub.t n1/tables/axor.t n1/tables/bef.t n1/tables/blkmv.t \
	n1/tables/div.t n1/tables/leaves.t n1/tables/mul.t n1/tables/neg.t \
	n1/tables/not.t n1/tables/or.t n1/tables/relop.t n1/tables/rem.t \
	n1/tables/shl.t n1/tables/shr.t n1/tables/sub.t n1/tables/xor.t

all:	cc0 cc1 cc2 cc3

cc0:	$(N0) $(COMMON)
	$(CC) $(LDFLAGS) -o cc0 $(N0) $(COMMON)

cc1:	$(N1) $(COMMON)
	$(CC) $(LDFLAGS) -o cc1 $(N1) $(COMMON)

cc2:	$(N2) $(COMMON)
	$(CC) $(LDFLAGS) -o cc2 $(N2) $(COMMON)

cc3:	$(N3) $(COMMON)
	$(CC) $(LDFLAGS) -o cc3 $(N3) $(COMMON)

# The .t selection grammar compiles through tabgen into the pattern/macro tables.
n1/tables/macros.c n1/tables/patern.c: tabgen n1/tables/prefac.f $(TABLES)
	cd n1/tables && ../../tabgen -s prefac.f *.t

tabgen:	coh/tabgen.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o tabgen coh/tabgen.c

# Native cc driver (donor coh/cc.c has a Z8001CC target); bring-up pending.
cc:	coh/cc.o $(COMMON)
	$(CC) $(LDFLAGS) -o cc coh/cc.o $(COMMON)

clean:
	rm -f cc0 cc1 cc2 cc3 cc tabgen n1/tables/macros.c n1/tables/patern.c \
	$(COMMON) $(N0) $(N1) $(N2) $(N3) coh/cc.o
