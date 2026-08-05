import random, sys
# Extended control-flow fuzzer: do-while, nested break/continue, and value-context
# ternary ?: -- the control constructs gen_ctrl (for/while/if) doesn't cover.  Every
# loop has a fresh bounded counter so it always terminates on host and target.  All
# arithmetic U16, wrapped.  BARE program; run.py adds the prelude.
def e(vars, rng):
    if rng.random() < 0.5: return rng.choice(vars)
    return str(rng.randint(0, 0xFFFF)) + 'U'
def program(seed):
    rng = random.Random(seed)
    nv = rng.randint(3, 4); vars = ['v%d' % i for i in range(nv)]
    L = ['U16 f(){', '  U16 ' + ', '.join(vars) + ', acc, c0, c1, c2;']
    for v in vars: L.append('  %s = %dU;' % (v, rng.randint(0, 0xFFFF)))
    L.append('  acc = 0U;')
    # do-while
    n = rng.randint(2, 8)
    L.append('  c0 = 0U;')
    L.append('  do {')
    L.append('    c0 = (U16)(c0 + 1U);')   # increment FIRST: a later `continue' must not skip it
    L.append('    acc = (U16)(acc + %s);' % e(vars, rng))
    if rng.random() < 0.5:
        L.append('    if (%s) continue;' % e(vars, rng))
        L.append('    acc = (U16)(acc ^ %s);' % e(vars, rng))
    L.append('  } while (c0 < %dU);' % n)
    # nested loop with break/continue
    L.append('  for (c1=0U; c1<%dU; c1=(U16)(c1+1U)) {' % rng.randint(2, 6))
    L.append('    for (c2=0U; c2<%dU; c2=(U16)(c2+1U)) {' % rng.randint(2, 6))
    L.append('      if ((U16)(c1 ^ c2) > %dU) break;' % rng.randint(0, 8))
    L.append('      acc = (U16)(acc + (%s > %s ? %s : %s));' % (e(vars,rng), e(vars,rng), e(vars,rng), e(vars,rng)))
    L.append('    }')
    L.append('    if (%s) continue;' % e(vars, rng))
    L.append('    acc = (U16)(acc - %s);' % e(vars, rng))
    L.append('  }')
    L.append('  return (U16)(acc + (%s ? %s : %s));' % (e(vars,rng), e(vars,rng), e(vars,rng)))
    L.append('}')
    return '\n'.join(L)
if __name__ == '__main__': print(program(int(sys.argv[1])))
