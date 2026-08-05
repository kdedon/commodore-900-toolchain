import random, sys
# Control-flow fuzzer: bounded loops (for/while), if/else, nested, computing a U16.
# All arithmetic U16 (wraps mod 2^16, wrapped (U16) so the host truncates each step).
# Every loop gets a GLOBALLY-UNIQUE counter (c0,c1,...) so a nested loop can never
# reset an enclosing loop's counter -> guaranteed termination (no infinite loop in
# either the sim or the host oracle). Loop bounds are small fixed constants; loop
# bodies only assign to value vars (never to a counter). Divisors guarded (&0x7FFF)|1.
BIN=['+','-','*','&','|','^']
def e(vars,d,rng):
    if d<=0 or (rng.random()<0.35 and vars):
        return rng.choice(vars) if (rng.random()<0.6 and vars) else str(rng.randint(0,0xFFFF))+'U'
    r=rng.random()
    if r<0.6: return '(U16)('+e(vars,d-1,rng)+rng.choice(BIN)+e(vars,d-1,rng)+')'
    if r<0.75: return '(U16)('+e(vars,d-1,rng)+rng.choice(['/','%'])+'(((U16)('+e(vars,d-1,rng)+')&0x7FFFU)|1U))'
    if r<0.9:  return '(U16)('+e(vars,d-1,rng)+rng.choice(['<<','>>'])+str(rng.randint(0,15))+'U)'
    return '('+e(vars,d-1,rng)+rng.choice(['<','>','<=','>=','==','!='])+e(vars,d-1,rng)+')'
def stmt(vars,ctr,depth,rng,ind):
    # ctr is a 1-element list holding the next free counter index (mutable across recursion)
    pad='  '*ind
    r=rng.random()
    if depth<=0 or r<0.45:
        return pad+'%s = %s;'%(rng.choice(vars), e(vars,2,rng))
    if r<0.62:   # if / if-else
        s=pad+'if (%s) {\n%s\n%s}'%(e(vars,2,rng), stmt(vars,ctr,depth-1,rng,ind+1), pad)
        if rng.random()<0.5: s+=' else {\n%s\n%s}'%(stmt(vars,ctr,depth-1,rng,ind+1), pad)
        return s
    if r<0.82:   # for loop with a fresh counter
        n=rng.randint(1,8); v='c%d'%ctr[0]; ctr[0]+=1
        return pad+'for (%s=0U; %s<%dU; %s=(U16)(%s+1U)) {\n%s\n%s}'%(v,v,n,v,v, stmt(vars,ctr,depth-1,rng,ind+1), pad)
    # while with a fresh decrementing counter
    n=rng.randint(1,8); v='c%d'%ctr[0]; ctr[0]+=1
    return pad+'%s = %dU;\n%swhile (%s) {\n%s\n%s%s = (U16)(%s-1U);\n%s}'%(v,n,pad,v, stmt(vars,ctr,depth-1,rng,ind+2), '  '*(ind+1),v,v, pad)
NCTR=24  # plenty of unique loop counters for the bounded nesting depth/breadth below
def program(seed):
    rng=random.Random(seed)
    nv=rng.randint(3,5); vars=['v%d'%i for i in range(nv)]
    ctrs=['c%d'%i for i in range(NCTR)]
    L=['U16 f(){','  U16 '+', '.join(vars)+';','  U16 '+', '.join(ctrs)+';']
    for v in vars: L.append('  %s = %dU;'%(v,rng.randint(0,0xFFFF)))
    ctr=[0]
    for _ in range(rng.randint(2,4)):
        if ctr[0]>=NCTR-6: break  # keep within the declared counter pool
        L.append(stmt(vars,ctr,3,rng,1))
    L.append('  return %s;'%e(vars,3,rng)); L.append('}')
    return '\n'.join(L)
if __name__=='__main__': print(program(int(sys.argv[1])))
