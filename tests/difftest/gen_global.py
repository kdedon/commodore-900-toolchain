import random, sys
# Globals/statics fuzzer: file-scope U16 variables + a global array, exercising the codegen
# paths that DIFFER from frame locals -- DA (direct absolute) addressing, static-base+index
# X-mode (g[i], #34/#16a), and pointers INTO a global array.  All U16 so the result VALUE is
# layout-independent vs host gcc.  Wrapping unsigned (UB-free); divisors &0x7FFF|1; array
# indices masked &7 in-bounds; a global pointer walks the array.
BIN=['+','-','*','&','|','^']
GV=['g0','g1','g2']            # scalar globals
def idx(rng): return '(('+e(1,rng)+')&7U)'
def e(d,rng):
    if d<=0 or (rng.random()<0.4):
        r=rng.random()
        if r<0.4:  return rng.choice(GV)
        if r<0.7:  return 'ga['+idx(rng)+']'      # static base + runtime index (X-mode)
        return str(rng.randint(0,0xFFFF))+'U'
    r=rng.random()
    if r<0.5:  return '(U16)('+e(d-1,rng)+rng.choice(BIN)+e(d-1,rng)+')'
    if r<0.65: return '(U16)('+e(d-1,rng)+rng.choice(['/','%'])+'((((U16)('+e(d-1,rng)+'))&0x7FFFU)|1U))'
    if r<0.80: return '(U16)('+e(d-1,rng)+rng.choice(['<<','>>'])+str(rng.randint(0,15))+'U)'
    return 'ga['+idx(rng)+']'
def program(seed):
    rng=random.Random(seed)
    L=['U16 g0, g1, g2;', 'U16 ga[8];', 'U16 *gp;', 'U16 f(){', '  U16 i, acc;']
    for v in GV: L.append('  %s = %dU;'%(v, rng.randint(0,0xFFFF)))
    for k in range(8): L.append('  ga[%d] = %dU;'%(k, rng.randint(0,0xFFFF)))
    L.append('  acc = 0U;')
    for _ in range(rng.randint(4,7)):
        r=rng.random()
        if r<0.4:   L.append('  %s = %s;'%(rng.choice(GV), e(2,rng)))          # scalar global store (DA)
        elif r<0.7: L.append('  ga[%s] = %s;'%(idx(rng), e(2,rng)))            # global array store (X-mode)
        elif r<0.85:L.append('  gp = ga + (%s); *gp = %s;'%(idx(rng), e(2,rng)))  # ptr into global, write
        else:       L.append('  gp = ga + (%s); acc = (U16)(acc ^ *gp);'%idx(rng)) # ptr read
    # a bounded loop summing the global array by runtime index (X-mode in a loop)
    L.append('  for (i=0U; i<8U; i=(U16)(i+1U)) acc = (U16)(acc + ga[i]);')
    for v in GV: L.append('  acc = (U16)(acc ^ %s);'%v)
    L.append('  return acc; }')
    return '\n'.join(L)
if __name__=='__main__': print(program(int(sys.argv[1])))
