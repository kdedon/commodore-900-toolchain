import random, sys
# Struct/aggregate fuzzer: field access at non-zero offsets, struct ASSIGNMENT (block move),
# struct passed BY VALUE to a helper (blkmv arg), struct RETURN by value, and a nested struct.
# All fields are U16 so the target's struct layout matches the host's for VALUE comparison
# (named field access -- s.b -- is layout-internal; we never take sizeof or cross-field
# pointer arithmetic, where the target's packing would diverge from host gcc).  Every op
# wrapped (U16) for per-step truncation; divisors guarded &0x7FFF|1.
BIN=['+','-','*','&','|','^']
FIELDS=['a','b','c','d']
def e(vars,d,rng):
    # an expression over struct-field lvalues (s.a ...) and U16 vars
    if d<=0 or (rng.random()<0.4):
        return rng.choice(vars) if (rng.random()<0.7 and vars) else str(rng.randint(0,0xFFFF))+'U'
    r=rng.random()
    if r<0.55: return '(U16)('+e(vars,d-1,rng)+rng.choice(BIN)+e(vars,d-1,rng)+')'
    if r<0.70: return '(U16)('+e(vars,d-1,rng)+rng.choice(['/','%'])+'((((U16)('+e(vars,d-1,rng)+'))&0x7FFFU)|1U))'
    if r<0.85: return '(U16)('+e(vars,d-1,rng)+rng.choice(['<<','>>'])+str(rng.randint(0,15))+'U)'
    return '('+e(vars,d-1,rng)+rng.choice(['<','>','==','!=','<=','>='])+e(vars,d-1,rng)+')'
def program(seed):
    rng=random.Random(seed)
    # lvalue pool: struct fields of s1/s2, the nested struct's inner fields, plus plain vars
    lv=['s1.'+f for f in FIELDS]+['s2.'+f for f in FIELDS]+['n1.s.'+f for f in FIELDS]+['n1.e','v0','v1']
    L=[]
    L.append('struct S { U16 a; U16 b; U16 c; U16 d; };')
    L.append('struct N { struct S s; U16 e; };')
    # helper: struct by VALUE -> U16 (reads fields of a copied struct)
    L.append('U16 sum(p) struct S p; { return (U16)((U16)((U16)(p.a+p.b)+p.c)^p.d); }')
    # helper: U16 -> struct by value RETURN
    L.append('struct S mk(x) U16 x; { struct S r; r.a=x; r.b=(U16)(x*3U); r.c=(U16)(x^0xAAAAU); r.d=(U16)(x+0x1234U); return r; }')
    L.append('U16 f(){')
    L.append('  struct S s1, s2; struct N n1; U16 v0, v1, acc;')
    for f in FIELDS: L.append('  s1.%s = %dU;'%(f,rng.randint(0,0xFFFF)))
    for f in FIELDS: L.append('  s2.%s = %dU;'%(f,rng.randint(0,0xFFFF)))
    for f in FIELDS: L.append('  n1.s.%s = %dU;'%(f,rng.randint(0,0xFFFF)))
    L.append('  n1.e = %dU;'%rng.randint(0,0xFFFF))
    L.append('  v0 = %dU; v1 = %dU; acc = 0U;'%(rng.randint(0,0xFFFF),rng.randint(0,0xFFFF)))
    for _ in range(rng.randint(4,7)):
        r=rng.random()
        if r<0.5:    L.append('  %s = %s;'%(rng.choice(lv), e(lv,2,rng)))            # field store
        elif r<0.65: L.append('  s2 = s1;')                                          # struct copy (block move)
        elif r<0.78: L.append('  n1.s = s2;')                                        # nested struct copy
        elif r<0.90: L.append('  acc = (U16)(acc ^ (U16)sum(s1));')                  # struct BY VALUE arg
        else:        L.append('  s1 = mk(%s);'%e(lv,2,rng))                          # struct RETURN by value
    # fold every field into acc
    for f in FIELDS: L.append('  acc = (U16)(acc ^ s1.%s ^ s2.%s ^ n1.s.%s);'%(f,f,f))
    L.append('  acc = (U16)(acc ^ n1.e ^ (U16)sum(s2));')
    L.append('  return acc; }')
    return '\n'.join(L)
if __name__=='__main__': print(program(int(sys.argv[1])))
