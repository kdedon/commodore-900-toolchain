import random, sys
# Generate a UB-FREE program computing a 16-bit value, over width-abstract macros.
# UNSIGNED 16-bit arithmetic wraps mod 2^16 -- fully defined on BOTH Z8001 (int=16) and
# host (unsigned short) -- so the host result is a sound oracle.  We use U16 throughout
# for arithmetic that can overflow; div/rem guard the divisor; shifts use 0..15.
BINOPS = ['+','-','*','&','|','^']
def expr(vars, depth, rng):
    if depth<=0 or (rng.random()<0.3 and vars):
        if rng.random()<0.5 and vars: return rng.choice(vars)
        return str(rng.randint(0,0xFFFF))+'U'
    r=rng.random()
    if r<0.55:
        return '(U16)('+expr(vars,depth-1,rng)+rng.choice(BINOPS)+expr(vars,depth-1,rng)+')'
    if r<0.70:  # guarded divide/modulo (divisor | 1 -> never 0)
        op=rng.choice(['/','%'])
        return '(U16)('+expr(vars,depth-1,rng)+op+'(((U16)('+expr(vars,depth-1,rng)+')&0x7FFFU)|1U))'  # divisor 1..0x7FFF (matches original; >=0x8000 is a shared latent DIV limit)
    if r<0.85:  # shift by a 0..15 constant
        return '(U16)('+expr(vars,depth-1,rng)+rng.choice(['<<','>>'])+str(rng.randint(0,15))+'U)'
    if r<0.95:  # comparison -> 0/1
        return '('+expr(vars,depth-1,rng)+rng.choice(['<','>','<=','>=','==','!='])+expr(vars,depth-1,rng)+')'
    return '('+expr(vars,depth-1,rng)+'?'+expr(vars,depth-1,rng)+':'+expr(vars,depth-1,rng)+')'  # ternary

def program(seed):
    rng=random.Random(seed)
    nv=rng.randint(2,5); vars=['v%d'%i for i in range(nv)]
    lines=['U16 f(){','  U16 '+', '.join(vars)+';']
    for v in vars: lines.append('  %s = %sU;'%(v, rng.randint(0,0xFFFF)))
    # a few assignments to mutate state
    for _ in range(rng.randint(1,4)):
        lines.append('  %s = %s;'%(rng.choice(vars), expr(vars,rng.randint(1,3),rng)))
    lines.append('  return %s;'%expr(vars,rng.randint(2,4),rng))
    lines.append('}')
    return '\n'.join(lines)
if __name__=='__main__':
    print(program(int(sys.argv[1])))
