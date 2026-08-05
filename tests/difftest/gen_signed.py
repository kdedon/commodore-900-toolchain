import random, sys
# Signed-integer fuzzer: exercises the SIGNED codegen paths that differ from unsigned --
# signed division/modulo (Z8000 EXTS sign-extend + DIV), signed comparisons (the #40/#41
# signed-relop area), and arithmetic shift-right (SRA).  Signed OVERFLOW is UB, so we never
# do signed +,-,* (those are bit-identical to unsigned anyway -- same ADD/SUB instruction):
# all VALUE arithmetic is wrapping UNSIGNED (U16, defined), reinterpreted to signed (I16)
# only AT the signedness-sensitive operation.  The U16->I16 reinterpretation is
# implementation-defined but two's-complement-consistent between gcc and the Z8001 (same
# basis as the arithmetic >>).  Divisors are guarded POSITIVE [1,0x7FFF] so neither div-by-0
# nor INT_MIN/-1 overflow can occur; the dividend is full-range signed (EXTS exercised).
UBIN=['+','-','*','&','|','^']
def u(vars,d,rng):
    # a defined wrapping-unsigned U16 expression.  Leaves are always VARIABLES (never a
    # constant): a folded constant with bit 15 set, cast to signed, hits the shared
    # constant-folder sign-extend shared with the original front end -- not our codegen.  Full-range values
    # still enter via the variable initializers (runtime thereafter).
    if d<=0 or (rng.random()<0.4):
        return rng.choice(vars)
    r=rng.random()
    if r<0.55: return '(U16)('+u(vars,d-1,rng)+rng.choice(UBIN)+u(vars,d-1,rng)+')'
    # unsigned '>>' (SRL) and '/'+'%' here feed sval's (I16)(...) wrap: the cast collapses
    # onto the unsigned op node in cc0, exercising the cc1 result-signedness re-sync
    # (mtree2 SHR/ASHR/DIV/REM) that keeps the OPERAND's form selecting the instruction.
    if r<0.70: return '(U16)('+u(vars,d-1,rng)+'>>'+str(rng.randint(0,15))+')'
    if r<0.80: return '(U16)('+u(vars,d-1,rng)+'/'+udiv(vars,rng)+')'
    if r<0.90: return '(U16)('+u(vars,d-1,rng)+'%'+udiv(vars,rng)+')'
    return '(U16)('+u(vars,d-1,rng)+'<<'+str(rng.randint(0,15))+'U)'
def udiv(vars,rng):
    # a NONZERO unsigned divisor in [1,0x7FFF].  Bit 15 stays CLEAR: a variable divisor
    # with the top bit set takes the signed divide (zero-extend + DIV computes the
    # SIGNED quotient) -- the original MWC Z8001 compiler emits the identical unguarded
    # sequence, so this is faithful-to-original.
    # (A CONSTANT top-bit divisor is fine: MI rewrites it to a compare.)
    return '(U16)((('+u(vars,1,rng)+')&0x7FFFU)|1U)'
def sval(vars,d,rng):
    # a signed I16 value (reinterpret a defined unsigned expr; no signed overflow involved)
    return '(I16)('+u(vars,d,rng)+')'
def posdiv(vars,rng):
    # a POSITIVE signed divisor in [1,0x7FFF]: guards div-by-0 AND INT_MIN/-1 overflow
    return '(I16)(((U16)('+u(vars,1,rng)+')&0x7FFFU)|1U)'
def s(vars,d,rng):
    # a signed I16 expression built from signedness-sensitive ops
    if d<=0 or (rng.random()<0.4):
        return sval(vars,1,rng)
    r=rng.random()
    if r<0.35: return '(I16)('+s(vars,d-1,rng)+'/'+posdiv(vars,rng)+')'   # signed DIV (EXTS)
    if r<0.60: return '(I16)('+s(vars,d-1,rng)+'%'+posdiv(vars,rng)+')'   # signed MOD
    # Signed arithmetic '>>' (SRA).  Exercises the cast-around-shift and the
    # reassociated-cast-signedness paths (mtree0/mtree4 type-keeping + the mtree2
    # result-signedness re-sync).
    if r<0.80: return '(I16)('+s(vars,d-1,rng)+'>>'+str(rng.randint(0,15))+')'
    # signed comparison -> ternary select (the result is one of two signed operands)
    return '('+s(vars,d-1,rng)+rng.choice(['<','>','<=','>=','==','!='])+s(vars,d-1,rng)+' ? '+s(vars,d-1,rng)+' : '+s(vars,d-1,rng)+')'
def program(seed):
    rng=random.Random(seed)
    nv=rng.randint(3,5); vars=['v%d'%i for i in range(nv)]
    L=['U16 f(){','  U16 '+', '.join(vars)+';','  I16 acc;']
    for v in vars: L.append('  %s = %dU;'%(v,rng.randint(0,0xFFFF)))
    L.append('  acc = '+sval(vars,2,rng)+';')
    for _ in range(rng.randint(3,6)):
        L.append('  acc = (I16)(acc + '+s(vars,3,rng)+');')   # accumulate (acc small-ish; wrap defined for unsigned bit pattern)
    L.append('  return (U16)acc;'); L.append('}')
    return '\n'.join(L)
if __name__=='__main__': print(program(int(sys.argv[1])))
