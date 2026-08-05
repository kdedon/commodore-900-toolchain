import random, sys
# Register-pressure fuzzer: MANY simultaneously-live values (12 word + 2 long + 3 byte)
# threaded through a long deep-expression sequence with interspersed calls (which clobber
# the scratch bank), long compares, and byte ops -- forcing the allocator to spill/reuse
# and push values into R8..R15 and pairs.  Targets the clobbered-scratch,
# NONE-reg-compare-operand and byte-value-in-a-non-byte-register classes, which the
# `-r' differential can MISS (a ramode over-read may execute the lucky value) but ASAN
# catches -- so sweep this through asan_frontend.sh too, not just -r vs host.  No U16*U16
# (host signed-int overflow UB); +,-,&,|,^ only, every step wrapped to its width.  Byte
# values 0..127 positive; the (I8) narrow + (U16) re-read sign-extend identically on host
# and target.  BARE program; run.py prepends the prelude.
BIN = ['+', '-', '&', '|', '^']
def e16(vs, d, rng):
    if d <= 0 or rng.random() < 0.3:
        return rng.choice(vs) if rng.random() < 0.7 else str(rng.randint(0, 0xFFFF)) + 'U'
    return '(U16)(' + e16(vs, d - 1, rng) + rng.choice(BIN) + e16(vs, d - 1, rng) + ')'
def program(seed):
    rng = random.Random(seed)
    vs = ['v%d' % i for i in range(12)]
    cs = ['c%d' % i for i in range(3)]
    ws = ['w%d' % i for i in range(2)]
    L = ['U16 h(a,b) U16 a, b; { return (U16)(a %s b); }' % rng.choice(BIN)]
    L.append('U16 f(){')
    L.append('  U16 ' + ', '.join(vs) + ', acc;')
    L.append('  I8 ' + ', '.join(cs) + ';')
    L.append('  U32 ' + ', '.join(ws) + ';')
    for v in vs: L.append('  %s = %dU;' % (v, rng.randint(0, 0xFFFF)))
    for c in cs: L.append('  %s = %d;' % (c, rng.randint(0, 127)))
    for w in ws: L.append('  %s = %dUL;' % (w, rng.randint(0, 0xFFFFFFFF)))
    for _ in range(rng.randint(12, 18)):
        r = rng.random()
        if r < 0.5:
            L.append('  %s = %s;' % (rng.choice(vs), e16(vs, 3, rng)))
        elif r < 0.7:
            L.append('  %s = h(%s, %s);' % (rng.choice(vs), e16(vs, 2, rng), e16(vs, 2, rng)))
        elif r < 0.85:
            c = rng.choice(cs)
            L.append('  %s = (I8)((U16)(%s) + (U16)(%s));' % (c, c, rng.choice(cs)))
        else:
            w = rng.choice(ws)
            L.append('  %s = (U32)(%s + (U32)(%s));' % (w, w, rng.choice(vs)))
    L.append('  acc = 0U;')
    for _ in range(rng.randint(2, 4)):
        L.append('  if (%s > %s) acc = (U16)(acc + %s);' % (e16(vs, 2, rng), e16(vs, 2, rng), rng.choice(vs)))
        L.append('  if (%s < %dUL) acc = (U16)(acc ^ %s);' % (rng.choice(ws), rng.randint(0, 0xFFFFFFFF), rng.choice(vs)))
    L.append('  acc = (U16)(acc' + ''.join(' ^ ' + v for v in vs) + ');')
    L.append('  acc = (U16)(acc' + ''.join(' + (U16)(' + c + ')' for c in cs) + ');')
    L.append('  acc = (U16)(acc' + ''.join(' ^ (U16)(' + w + ')' for w in ws) + ');')
    L.append('  return acc;')
    L.append('}')
    return '\n'.join(L)
if __name__ == '__main__':
    print(program(int(sys.argv[1])))
