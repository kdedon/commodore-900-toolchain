import random, sys
# Array + pointer fuzzer: a small U16 array, indexed loads/stores, pointer walks,
# all arithmetic U16 (wrapped (U16) so the host truncates each step). Indices are
# masked into range (&7) so every access is in-bounds; divisors guarded (&0x7FFF)|1.
BIN=['+','-','*','&','|','^']
N=8
def idx(vars,rng):
    # an in-bounds [0,N) index expression
    return '(('+e(vars,1,rng)+')&7U)'
def e(vars,d,rng):
    if d<=0 or (rng.random()<0.4 and vars):
        r=rng.random()
        if r<0.45 and vars: return rng.choice(vars)
        if r<0.75: return 'a[%s]'%idx(vars,rng)
        return str(rng.randint(0,0xFFFF))+'U'
    r=rng.random()
    if r<0.6: return '(U16)('+e(vars,d-1,rng)+rng.choice(BIN)+e(vars,d-1,rng)+')'
    if r<0.75: return '(U16)('+e(vars,d-1,rng)+rng.choice(['/','%'])+'(((U16)('+e(vars,d-1,rng)+')&0x7FFFU)|1U))'
    if r<0.9:  return '(U16)('+e(vars,d-1,rng)+rng.choice(['<<','>>'])+str(rng.randint(0,15))+'U)'
    return 'a[%s]'%idx(vars,rng)
def stmt(vars,rng,ind):
    pad='  '*ind
    r=rng.random()
    if r<0.4:   return pad+'%s = %s;'%(rng.choice(vars), e(vars,2,rng))
    if r<0.7:   return pad+'a[%s] = %s;'%(idx(vars,rng), e(vars,2,rng))
    if r<0.85:  # pointer write through p = a + k
        return pad+'p = a + (%s); *p = %s;'%(idx(vars,rng), e(vars,2,rng))
    # pointer read through p
    return pad+'p = a + (%s); %s = *p;'%(idx(vars,rng), rng.choice(vars))
def program(seed):
    rng=random.Random(seed)
    nv=rng.randint(2,4); vars=['v%d'%i for i in range(nv)]
    L=['U16 f(){','  U16 a[%d], %s, i;'%(N, ', '.join(vars)), '  U16 *p;']
    for k in range(N): L.append('  a[%d] = %dU;'%(k, rng.randint(0,0xFFFF)))
    for v in vars: L.append('  %s = %dU;'%(v, rng.randint(0,0xFFFF)))
    # a bounded loop that touches the array
    n=rng.randint(1,N)
    L.append('  for (i=0U; i<%dU; i=(U16)(i+1U)) {'%n)
    L.append('  '+stmt(vars,rng,2))
    L.append('  }')
    for _ in range(rng.randint(2,4)): L.append(stmt(vars,rng,1))
    # fold the whole array into the result so every cell matters
    L.append('  v0 = 0U;')
    L.append('  for (i=0U; i<%dU; i=(U16)(i+1U)) v0 = (U16)(v0 + a[i]);'%N)
    L.append('  return (U16)(v0 + %s);'%e(vars,2,rng)); L.append('}')
    return '\n'.join(L)
if __name__=='__main__': print(program(int(sys.argv[1])))
