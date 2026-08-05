import random, sys
# Char fuzzer: exercises the BYTE/char codegen paths that differ from word -- char
# arithmetic (promote to int via EXTSB sign-extend), char<->int conversions, signed-char
# comparisons, and char-array indexing.  MWC `char' is SIGNED (byte widen = EXTSB), so the
# host prelude maps I8=signed char.  char operands are small [-128,127], so the int
# promotion of `c1 OP c2' never overflows 16-bit int -- naturally UB-free; we still wrap
# every int sub-result (I16) so the 32-bit host truncates to the target's 16-bit int per
# step, and every char store (I8).  Divisors guarded != 0 via |1 on the int value.
CBIN=['+','-','*','&','|','^']
def ci(vars,d,rng):
    # an int (I16) expression whose leaves are SIGN-EXTENDED chars or small int consts
    if d<=0 or (rng.random()<0.4):
        if rng.random()<0.7 and vars: return '(I16)('+rng.choice(vars)+')'   # widen char->int (EXTSB)
        return '('+str(rng.randint(-128,127))+')'   # parens: a bare `-79' after `-' lexes as `--'
    r=rng.random()
    if r<0.5: return '(I16)('+ci(vars,d-1,rng)+rng.choice(CBIN)+ci(vars,d-1,rng)+')'
    if r<0.65: return '(I16)('+ci(vars,d-1,rng)+rng.choice(['/','%'])+'((I16)('+ci(vars,d-1,rng)+')|1))'
    if r<0.78: return '(I16)('+ci(vars,d-1,rng)+rng.choice(['<<','>>'])+str(rng.randint(0,7))+')'
    if r<0.90: return '(I16)('+ci(vars,d-1,rng)+rng.choice(['<','>','<=','>=','==','!='])+ci(vars,d-1,rng)+')'
    return '(I16)((I8)('+ci(vars,d-1,rng)+'))'   # narrow int->char (truncate) then re-widen
def stmt(vars,arr,rng,ind):
    pad='  '*ind; r=rng.random()
    if r<0.5:   return pad+'%s = (I8)(%s);'%(rng.choice(vars), ci(vars,2,rng))         # char store
    if r<0.75:  return pad+'%s[(%s)&7] = (I8)(%s);'%(arr, ci(vars,1,rng), ci(vars,2,rng))  # char array store
    return pad+'acc = (I16)(acc + %s);'%ci(vars,2,rng)
def program(seed):
    rng=random.Random(seed)
    nv=rng.randint(3,5); vars=['c%d'%i for i in range(nv)]; arr='ca'
    L=['U16 f(){','  I8 '+', '.join(vars)+';','  I8 %s[8];'%arr,'  I16 acc;']
    for v in vars: L.append('  %s = (I8)(%d);'%(v,rng.randint(-128,127)))
    for k in range(8): L.append('  %s[%d] = (I8)(%d);'%(arr,k,rng.randint(-128,127)))
    L.append('  acc = 0;')
    for _ in range(rng.randint(3,6)): L.append(stmt(vars,arr,rng,1))
    # fold all chars (widened) into acc
    for v in vars: L.append('  acc = (I16)(acc ^ (I16)(%s));'%v)
    L.append('  acc = (I16)(acc ^ (I16)(%s[(acc)&7]));'%arr)
    L.append('  return (U16)acc;'); L.append('}')
    return '\n'.join(L)
if __name__=='__main__': print(program(int(sys.argv[1])))
