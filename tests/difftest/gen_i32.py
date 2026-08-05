import random, sys
BIN=['+','-','*','&','|','^']
# Every op and constant wrapped (U32) so the host (where UL is 64-bit) truncates to 32 bits
# at each step -- matching Z8001 unsigned long (32-bit).  div/mod operands explicitly (U32)
# so the dividend/divisor are 32-bit BEFORE the (non-mod-2^32-commuting) divide.  Divisor
# &0x7FFFFFFF | 1 keeps it 1..0x7FFFFFFF (the >=0x80000000 signed-DIVL corner is shared, #23).
def k(rng): return '(U32)'+str(rng.randint(0,0xFFFFFFFF))+'UL'
def e(vars,d,rng):
    if d<=0 or (rng.random()<0.3 and vars):
        return rng.choice(vars) if (rng.random()<0.5 and vars) else k(rng)
    r=rng.random()
    if r<0.55: return '(U32)('+e(vars,d-1,rng)+rng.choice(BIN)+e(vars,d-1,rng)+')'
    if r<0.70:
        op=rng.choice(['/','%']); return '(U32)((U32)('+e(vars,d-1,rng)+')'+op+'(((U32)('+e(vars,d-1,rng)+')&(U32)0x7FFFFFFFUL)|(U32)1UL))'
    if r<0.85: return '(U32)('+e(vars,d-1,rng)+rng.choice(['<<','>>'])+str(rng.randint(0,31))+'UL)'
    if r<0.95: return '(U32)('+e(vars,d-1,rng)+rng.choice(['<','>','<=','>=','==','!='])+e(vars,d-1,rng)+')'
    return '(U32)('+e(vars,d-1,rng)+'?'+e(vars,d-1,rng)+':'+e(vars,d-1,rng)+')'
def program(seed):
    rng=random.Random(seed); nv=rng.randint(2,4); vars=['w%d'%i for i in range(nv)]
    L=['U16 f(){','  U32 '+', '.join(vars)+';']
    for v in vars: L.append('  %s = %s;'%(v,k(rng)))
    for _ in range(rng.randint(1,4)): L.append('  %s = %s;'%(rng.choice(vars), e(vars,rng.randint(1,3),rng)))
    L.append('  return (U16)(%s);'%e(vars,rng.randint(2,4),rng)); L.append('}')
    return '\n'.join(L)
if __name__=='__main__': print(program(int(sys.argv[1])))
