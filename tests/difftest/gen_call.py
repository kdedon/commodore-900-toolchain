import random, sys
# Call-ABI fuzzer: multiple K&R functions calling each other, stressing argument passing
# (stack args at FP+offset), return values (R1), and callee-saved register preservation
# across calls.  All values U16 (unsigned, wraps mod 2^16 -- UB-free), every op wrapped
# (U16) so the host truncates per step.  Helpers gK may call only LOWER-indexed helpers
# (no cycles -> guaranteed termination); divisors guarded |1.
BIN=['+','-','*','&','|','^']
def e(args,d,rng,callees):
    # an unsigned expression over the in-scope arg names; may CALL a lower helper
    if d<=0 or (rng.random()<0.4):
        return rng.choice(args) if (rng.random()<0.7 and args) else str(rng.randint(0,0xFFFF))+'U'
    r=rng.random()
    if r<0.45: return '(U16)('+e(args,d-1,rng,callees)+rng.choice(BIN)+e(args,d-1,rng,callees)+')'
    # divisor masked &0x7FFF | 1 -> [1,0x7FFF]: a divisor >=0x8000 hits the shared
    # unsigned-divide-via-signed-DIV corner (div.t/#23), not a call-ABI issue.
    if r<0.58: return '(U16)('+e(args,d-1,rng,callees)+rng.choice(['/','%'])+'((((U16)('+e(args,d-1,rng,callees)+'))&0x7FFFU)|1U))'
    if r<0.70: return '(U16)('+e(args,d-1,rng,callees)+rng.choice(['<<','>>'])+str(rng.randint(0,15))+'U)'
    if r<0.80: return '('+e(args,d-1,rng,callees)+rng.choice(['<','>','==','!=','<=','>='])+e(args,d-1,rng,callees)+')'
    if callees:  # CALL a lower-indexed helper with the right arg count
        name,argc = rng.choice(callees)
        return '(U16)'+name+'('+', '.join(e(args,d-1,rng,callees) for _ in range(argc))+')'
    return e(args,d-1,rng,callees)
def func(idx,rng):
    argc = rng.randint(1,5)
    args = ['a%d'%i for i in range(argc)]
    callees = [('g%d'%j, FUNCS[j]) for j in range(idx)]  # only lower helpers
    decl = 'U16 g%d(%s) %s { return %s; }' % (
        idx, ', '.join(args), ' '.join('U16 %s;'%a for a in args),
        e(args,3,rng,callees))
    return decl, argc
FUNCS=[]
def program(seed):
    global FUNCS
    rng=random.Random(seed); FUNCS=[]
    nf=rng.randint(2,4); decls=[]
    for i in range(nf):
        d,argc=func(i,rng); FUNCS.append(argc); decls.append(d)
    callees=[('g%d'%j, FUNCS[j]) for j in range(nf)]
    L=decls+['U16 f(){','  U16 v0, v1, v2, acc;']
    for v in ['v0','v1','v2']: L.append('  %s = %dU;'%(v,rng.randint(0,0xFFFF)))
    L.append('  acc = 0U;')
    for _ in range(rng.randint(3,6)):
        nm,argc=rng.choice(callees)
        L.append('  acc = (U16)(acc ^ (U16)%s(%s));'%(nm, ', '.join(e(['v0','v1','v2'],2,rng,callees) for _ in range(argc))))
    L.append('  return acc;'); L.append('}')
    return '\n'.join(L)
if __name__=='__main__': print(program(int(sys.argv[1])))
