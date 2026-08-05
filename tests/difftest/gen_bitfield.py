import random, sys
# Bitfield fuzzer: a struct of UNSIGNED bitfields (total <= 16 bits, so they pack into a
# single 16-bit word identically on the Z8001 (unsigned=16) and the host (unsigned
# short=16) -- no straddling/layout divergence).  Assign each field from a runtime
# variable, compound-assign some, then read the fields back into a U16 accumulator.
# Exercises the Z8001 bitfield codegen (FFLD extract = shift+mask; insert = read-modify-
# write through the container) -- pure PORT code (had ICEs/value bugs #22/#44/#46).
# UNSIGNED fields only (plain-int bitfield signedness is impl-defined); every value is a
# runtime variable, so no constant-fold corner.  BARE program; run.py adds the prelude.
def program(seed):
    rng = random.Random(seed)
    nf = rng.randint(3, 6)
    # distribute a 16-bit budget so every field is >=1 and the total never exceeds one word
    widths = []
    rem = 16
    for i in range(nf):
        hi = min(8, rem - (nf - i - 1))
        w = rng.randint(1, max(1, hi))
        widths.append(w)
        rem -= w
    fields = ['f%d' % i for i in range(nf)]
    L = ['struct S {']
    for f, w in zip(fields, widths):
        L.append('  U16 %s : %d;' % (f, w))
    L.append('};')
    L.append('U16 f(){')
    L.append('  struct S s;')
    L.append('  U16 ' + ', '.join('v%d' % i for i in range(nf)) + ', acc;')
    for i in range(nf):
        L.append('  v%d = %dU;' % (i, rng.randint(0, 0xFFFF)))
    for i, f in enumerate(fields):
        L.append('  s.%s = v%d;' % (f, i))               # straight insert (truncates to width)
    for _ in range(rng.randint(1, 4)):                    # read-modify-write inserts
        f = rng.choice(fields)
        op = rng.choice(['+=', '-=', '|=', '&=', '^='])
        L.append('  s.%s %s v%d;' % (f, op, rng.randint(0, nf - 1)))
    for _ in range(rng.randint(0, 2)):                    # ++/-- on a field (bef.t/aft.t)
        f = rng.choice(fields)
        L.append('  s.%s%s;' % (f, rng.choice(['++', '--'])))
    L.append('  acc = 0U;')
    for f in fields:                                      # extract each field
        op = rng.choice(['+', '-', '|', '^', '&'])
        L.append('  acc = (U16)(acc %s s.%s);' % (op, f))
    L.append('  return acc;')
    L.append('}')
    return '\n'.join(L)

if __name__ == '__main__':
    print(program(int(sys.argv[1])))
