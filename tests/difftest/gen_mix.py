import random, sys
# Mixed-width fuzzer: U16 (16-bit int) <-> U32 (32-bit long) widening/narrowing.
# Typed expression tree: every node is tagged 'w' (U16) or 'l' (U32); each operation
# is wrapped in its result-width cast so the host truncates per step exactly as the
# Z8001 does. Widen = (U32)w-expr; narrow = (U16)l-expr (low word). Unsigned only
# (wrap is defined); divisors guarded (&mask)|1. Returns a U16 that XOR-folds the
# high words of every U32 value so 32-bit high-word miscompiles surface in 16 bits.
BIN=['+','-','*','&','|','^']
BINL=['+','-','&','|','^']  # long (32-bit): NO '*' -- 32-bit MULTL has its own generator
def lit(t,rng):
    # An INLINE U16 literal stays <0x8000: a U-suffixed 16-bit constant with bit 15 set,
    # widened to long at COMPILE time, sign-extends in the MWC front-end fold (a
    # SHARED limit with the original compiler -- not our codegen).  Capping inline literals
    # keeps the fuzzer testing genuine codegen; variable initializers stay full-range
    # (their widen is a RUNTIME conversion, which zero-extends correctly via CLR).
    return (str(rng.randint(0,0x7FFF))+'U') if t=='w' else (str(rng.randint(0,0xFFFFFFFF))+'UL')
def cast(t): return '(U16)' if t=='w' else '(U32)'
def mask(t): return '0x7FFFU' if t=='w' else '0x7FFFFFFFUL'
def one(t): return '1U' if t=='w' else '1UL'
def var(t,wv,lv,rng):
    # Always a VARIABLE (the pools are never empty): a pure-constant subexpression would be
    # folded at compile time, and the MWC front-end constant folder mishandles the signedness
    # of any 16-bit value with bit 15 set (a SHARED limit with the original compiler --
    # not our codegen).  Keeping every leaf a variable makes all expression VALUES runtime, so
    # this generator exercises our int<->long CODEGEN faithfully.  Full-range constants still
    # enter via the variable initializers (runtime thereafter).
    pool = wv if t=='w' else lv
    return rng.choice(pool)
def e(t,d,wv,lv,rng):
    # t is the desired result width ('w' or 'l')
    if d<=0 or (rng.random()<0.35):
        return var(t,wv,lv,rng)
    r=rng.random()
    if r<0.45:   # same-width binary (no 32-bit '*' -- MULTL has its own generator)
        return cast(t)+'('+e(t,d-1,wv,lv,rng)+rng.choice(BIN if t=='w' else BINL)+e(t,d-1,wv,lv,rng)+')'
    if r<0.60 and t=='w':   # 16-bit div/mod only, guarded divisor.  32-bit (long) div/mod
        # has a known DIVL RQ0-pin gap under register pressure -- excluded
        # here so this generator stays green and catches NEW regressions.
        return cast(t)+'('+e(t,d-1,wv,lv,rng)+rng.choice(['/','%'])+'(('+cast(t)+'('+e(t,d-1,wv,lv,rng)+')&'+mask(t)+')|'+one(t)+'))'
    if r<0.72:   # same-width shift
        return cast(t)+'('+e(t,d-1,wv,lv,rng)+rng.choice(['<<','>>'])+str(rng.randint(0,15 if t=='w' else 31))+('U' if t=='w' else 'U')+')'
    if r<0.86:   # convert between widths
        if t=='w':  # NARROW long->word (takes the low word; always well-defined)
            return '(U16)('+e('l',d-1,wv,lv,rng)+')'
        # WIDEN word->long: use a word VARIABLE source so this is a RUNTIME conversion
        # (zero-extends via CLR).  A CONSTANT-foldable source would hit the shared
        # front-end constant sign-extend, which is not our codegen.
        return '(U32)('+(rng.choice(wv) if wv else lit('w',rng))+')'
    # extract a word from a long via shift then narrow (exercises high-word lowering)
    if t=='w':
        return '(U16)('+e('l',d-1,wv,lv,rng)+'>>'+str(rng.choice([0,8,16,24]))+'U)'
    # build a long from two words: both halves from word VARIABLES (runtime widen, see above)
    a = rng.choice(wv) if wv else lit('w',rng)
    b = rng.choice(wv) if wv else lit('w',rng)
    return '(U32)(((U32)('+a+')<<16)|(U32)('+b+'))'
def program(seed):
    rng=random.Random(seed)
    wv=['w%d'%i for i in range(rng.randint(2,3))]
    lv=['l%d'%i for i in range(rng.randint(2,3))]
    L=['U16 f(){','  U16 '+', '.join(wv)+';','  U32 '+', '.join(lv)+';','  U16 acc;']
    for v in wv: L.append('  %s = %dU;'%(v, rng.randint(0,0xFFFF)))
    for v in lv: L.append('  %s = %dUL;'%(v, rng.randint(0,0xFFFFFFFF)))
    L.append('  acc = 0U;')
    # a handful of assignments mixing both widths
    for _ in range(rng.randint(4,7)):
        if rng.random()<0.5:
            tv=rng.choice(wv); L.append('  %s = %s;'%(tv, e('w',3,wv,lv,rng)))
        else:
            tv=rng.choice(lv); L.append('  %s = %s;'%(tv, e('l',3,wv,lv,rng)))
    # fold all words directly and all longs (low ^ high) into acc
    for v in wv: L.append('  acc = (U16)(acc ^ %s);'%v)
    for v in lv: L.append('  acc = (U16)(acc ^ (U16)%s ^ (U16)(%s>>16U));'%(v,v))
    L.append('  return acc;'); L.append('}')
    return '\n'.join(L)
if __name__=='__main__': print(program(int(sys.argv[1])))
