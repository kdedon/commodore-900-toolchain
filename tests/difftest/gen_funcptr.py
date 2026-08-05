import random, sys
# Function-pointer fuzzer: a table of small U16 helper functions called INDIRECTLY
# through a function-pointer array indexed at runtime, accumulating a U16.  Exercises
# the Z8001 indirect-call codegen + the call ABI (args at FP+6.., U16 return in R1) and
# the indexed-function-pointer path -- port code with past bugs (#43 indexed fnptr call,
# #48 fnptr-copy).  No `*' in the helpers (U16*U16 overflows int -> host UB); +,-,&,|,^
# only, every step wrapped (U16).  BARE program; run.py prepends the prelude.
def program(seed):
    rng = random.Random(seed)
    nfn = rng.randint(2, 4)
    L = []
    for i in range(nfn):
        op = rng.choice(['+', '-', '&', '|', '^'])
        L.append('U16 g%d(a,b) U16 a, b; { return (U16)(a %s b); }' % (i, op))
    L.append('U16 f(){')
    L.append('  U16 (*fp[%d])();' % nfn)
    L.append('  U16 i, acc, x, y;')
    for i in range(nfn):
        L.append('  fp[%d] = g%d;' % (i, i))
    L.append('  x = %dU; y = %dU; acc = 0U;' % (rng.randint(0, 0xFFFF), rng.randint(0, 0xFFFF)))
    L.append('  for (i=0U; i<%dU; i=(U16)(i+1U)) {' % (nfn * 2))
    L.append('    acc = (U16)(acc + (*fp[i %% %dU])(x, y));' % nfn)
    L.append('    x = (U16)(x + acc);')
    L.append('  }')
    # also one DIRECT-through-variable call (fnptr copy, #48)
    L.append('  { U16 (*q)(); q = fp[%dU %% %dU]; acc = (U16)(acc + (*q)(acc, y)); }'
             % (rng.randint(0, 9), nfn))
    L.append('  return acc;')
    L.append('}')
    return '\n'.join(L)

if __name__ == '__main__':
    print(program(int(sys.argv[1])))
