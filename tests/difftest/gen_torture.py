import random, sys
# Torture fuzzer: mixes EVERY feature in one high-register-pressure function -- globals +
# locals, U16 + U32 + char + struct, calls, bounded loops, if/else, pointers into arrays,
# int<->long widen/narrow.  The point is FEATURE INTERACTION (one
# feature's codegen clobbering a value another holds), which single-feature generators miss.
# UB-free throughout: unsigned wraps, divisors guarded &0x7FFF|1 (U16) / &0x7FFFFFFF|1 (U32),
# array indices masked in-bounds, loops bounded, helpers call no one (no recursion).
WV=['w0','w1','w2']        # U16 locals
LVV=['l0','l1']            # U32 locals
GV=['g0','g1']             # U16 globals
def we(d,rng):             # U16 expression mixing locals/globals/array/narrowed-long
    if d<=0 or rng.random()<0.4:
        r=rng.random()
        if r<0.3: return rng.choice(WV)
        if r<0.5: return rng.choice(GV)
        if r<0.7: return 'a[((%s)&7U)]'%we(0,rng) if d>0 else 'a[(w0&7U)]'
        if r<0.85: return '(U16)(%s)'%rng.choice(LVV)         # narrow long->word
        return str(rng.randint(0,0xFFFF))+'U'
    r=rng.random()
    if r<0.4:
        op=rng.choice(['+','-','*','&','|','^'])
        # `*': mask one operand to a byte.  On the host U16 promotes to signed int, so a
        # full-range U16*U16 (up to 65535^2 ~ 4.3e9) OVERFLOWS int -> UB -> unreliable oracle.
        # a*(b&0xFF) <= 65535*255 < 2^31, UB-free, and still exercises the 16-bit MULT.
        if op=='*': return '(U16)(%s*((%s)&0xFFU))'%(we(d-1,rng),we(d-1,rng))
        return '(U16)(%s%s%s)'%(we(d-1,rng),op,we(d-1,rng))
    if r<0.55: return '(U16)(%s/((((U16)(%s))&0x7FFFU)|1U))'%(we(d-1,rng),we(d-1,rng))
    if r<0.7: return '(U16)(%s>>%dU)'%(we(d-1,rng),rng.randint(0,15))
    if r<0.82: return '(U16)g(%s, %s)'%(we(d-1,rng),we(d-1,rng))   # CALL (returns U16)
    if r<0.9: return '(U16)(s1.b ^ s1.d)'                          # struct field read
    return '(%s%s%s)'%(we(d-1,rng),rng.choice(['<','>','==','!=']),we(d-1,rng))
def le(d,rng):             # U32 expression (no 32-bit *,/,% -> those have their own gen)
    if d<=0 or rng.random()<0.45:
        if rng.random()<0.6: return rng.choice(LVV)
        # widen a word VARIABLE (runtime conversion, zero-extends correctly).  A widen of a
        # bit-15-set CONSTANT would hit the shared front-end constant sign-extend, not our
        # codegen -- so never widen a constant/folded word expr here.
        return '(U32)(%s)'%rng.choice(WV+GV)
    r=rng.random()
    if r<0.6: return '(U32)(%s%s%s)'%(le(d-1,rng),rng.choice(['+','-','&','|','^']),le(d-1,rng))
    return '(U32)(%s>>%dUL)'%(le(d-1,rng),rng.randint(0,31))
def stmt(d,rng,ind):
    pad='  '*ind; r=rng.random()
    if r<0.30: return pad+'%s = %s;'%(rng.choice(WV+GV), we(2,rng))
    if r<0.45: return pad+'a[((%s)&7U)] = %s;'%(we(1,rng), we(2,rng))
    if r<0.55: return pad+'%s = %s;'%(rng.choice(LVV), le(2,rng))
    if r<0.65: return pad+'p = a + ((%s)&7U); *p = %s;'%(we(1,rng), we(2,rng))
    if r<0.72: return pad+'s1.%s = %s;'%(rng.choice(['a','b','c','d']), we(2,rng))
    if r<0.80: return pad+'acc = (U16)(acc ^ (U16)g(%s, %s));'%(we(1,rng),we(1,rng))
    if r<0.90 and d>0:
        # unique counter PER NESTING LEVEL (c<d>): a nested loop reusing the outer's counter
        # would reset it -> infinite loop.  Body is stmt(d-1), so depth -> distinct counter.
        n=rng.randint(1,6); c='c%d'%d
        return pad+'for (%s=0U; %s<%dU; %s=(U16)(%s+1U)) {\n%s\n%s}'%(c,c,n,c,c, stmt(d-1,rng,ind+1), pad)
    if d>0:
        s=pad+'if (%s) {\n%s\n%s}'%(we(1,rng), stmt(d-1,rng,ind+1), pad)
        if rng.random()<0.5: s+=' else {\n%s\n%s}'%(stmt(d-1,rng,ind+1), pad)
        return s
    return pad+'acc = (U16)(acc + %s);'%we(2,rng)
def program(seed):
    rng=random.Random(seed)
    L=['U16 g0, g1;', 'U16 ga8tmp;',  # (ga8tmp unused; keep g0/g1 as the globals)
       'struct S { U16 a; U16 b; U16 c; U16 d; };',
       'U16 g(x, y) U16 x; U16 y; { return (U16)((U16)(x*3U)^(U16)(y>>2U)); }',
       'U16 f(){',
       '  U16 w0, w1, w2, i, c0, c1, c2, acc; U32 l0, l1; U16 a[8]; U16 *p; struct S s1;']
    for v in WV: L.append('  %s = %dU;'%(v,rng.randint(0,0xFFFF)))
    for v in GV: L.append('  %s = %dU;'%(v,rng.randint(0,0xFFFF)))
    for v in LVV: L.append('  %s = %dUL;'%(v,rng.randint(0,0xFFFFFFFF)))
    for k in range(8): L.append('  a[%d] = %dU;'%(k,rng.randint(0,0xFFFF)))
    for fld in ['a','b','c','d']: L.append('  s1.%s = %dU;'%(fld,rng.randint(0,0xFFFF)))
    L.append('  acc = 0U;')
    for _ in range(rng.randint(5,9)): L.append(stmt(2,rng,1))
    L.append('  for (i=0U; i<8U; i=(U16)(i+1U)) acc = (U16)(acc + a[i]);')
    for v in WV+GV: L.append('  acc = (U16)(acc ^ %s);'%v)
    for v in LVV: L.append('  acc = (U16)(acc ^ (U16)%s ^ (U16)(%s>>16U));'%(v,v))
    L.append('  acc = (U16)(acc ^ s1.a ^ s1.b ^ s1.c ^ s1.d);')
    L.append('  return acc; }')
    return '\n'.join(L)
if __name__=='__main__': print(program(int(sys.argv[1])))
