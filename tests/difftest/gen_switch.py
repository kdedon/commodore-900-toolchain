import random, sys
# Switch-statement fuzzer: switch on a loop-driven value with DENSE (0..k) or SPARSE
# (scattered) case labels, break + C fall-through + default, accumulating a U16.
# Exercises the switch lowering (the relop/branch-chain or jump-table path) that no
# other generator covers.  All arithmetic is U16 and wrapped via (U16) so the host
# truncates each step identically.  BARE program -- run.py prepends the per-target
# #define prelude (never embed one here, or the host silently computes in 32-bit).
def expr(vars, rng):
    if rng.random() < 0.5 and vars:
        return rng.choice(vars)
    return str(rng.randint(0, 0xFFFF)) + 'U'

def gen_switch(vars, ctrl, rng, ind):
    pad = '  ' * ind
    ncases = rng.randint(2, 6)
    dense = rng.random() < 0.6
    L = [pad + 'switch (%s) {' % ctrl]
    used = set()
    for i in range(ncases):
        if dense:
            k = i
        else:
            k = rng.randint(0, 20)
            while k in used:
                k = rng.randint(0, 20)
        used.add(k)
        L.append(pad + 'case %dU:' % k)
        L.append(pad + '  %s = (U16)(%s + %s);' % (rng.choice(vars), rng.choice(vars), expr(vars, rng)))
        if rng.random() < 0.7:          # ~30% C fall-through to the next case
            L.append(pad + '  break;')
    L.append(pad + 'default:')
    L.append(pad + '  %s = (U16)(%s + %dU);' % (rng.choice(vars), rng.choice(vars), rng.randint(0, 0xFFFF)))
    L.append(pad + '  break;')
    L.append(pad + '}')
    return '\n'.join(L)

def program(seed):
    rng = random.Random(seed)
    nv = rng.randint(3, 5)
    vars = ['v%d' % i for i in range(nv)]
    L = ['U16 f(){', '  U16 ' + ', '.join(vars) + ', i, acc;']
    for v in vars:
        L.append('  %s = %dU;' % (v, rng.randint(0, 0xFFFF)))
    L.append('  acc = 0U;')
    n = rng.randint(4, 10)            # i runs 0..n-1, so dense (<=6) cases AND default are hit
    L.append('  for (i=0U; i<%dU; i=(U16)(i+1U)) {' % n)
    L.append(gen_switch(vars, 'i', rng, 2))
    L.append('    acc = (U16)(acc + %s);' % rng.choice(vars))
    L.append('  }')
    L.append('  return (U16)(acc + %s);' % rng.choice(vars))
    L.append('}')
    return '\n'.join(L)

if __name__ == '__main__':
    print(program(int(sys.argv[1])))
