import random, sys
# Byte-pointer / string-walk fuzzer: a local char buffer (ASCII range 1..127, NUL-
# terminated) walked with char pointers -- *p, *p++, p[i], `while(*p)' scan, byte copy
# `*q++ = *p++' -- accumulating a U16.  THE real-userland idiom (argv/string scanning)
# and the heaviest exercise of byte deref through a far pointer (@RRn / off(RRn) byte
# loads + EXTSB), pointer post-increment (the *p++ value+effect path #47), and byte
# register allocation (#80).  Values 1..127 stay positive so signed-char promotion is
# unambiguous on host and target; the NUL terminates the scans identically.  BARE
# program; run.py prepends the per-target #define prelude.
def program(seed):
    rng = random.Random(seed)
    n = rng.randint(4, 12)
    vals = [rng.randint(1, 127) for _ in range(n)]
    L = ['U16 f(){']
    L.append('  I8 s[%d];' % (n + 1))
    L.append('  I8 d[%d];' % (n + 1))
    L.append('  I8 *p, *q;')
    L.append('  U16 acc, i;')
    for i, v in enumerate(vals):
        L.append('  s[%d] = %d;' % (i, v))
    L.append('  s[%d] = 0;' % n)
    L.append('  p = s; q = d;')
    L.append('  while (*p) *q++ = *p++;')          # byte copy, post-inc both pointers
    L.append('  *q = 0;')
    L.append('  acc = 0U; p = d;')
    L.append('  while (*p) acc = (U16)(acc + (U16)(*p++));')   # scan + accumulate via *p++
    L.append('  for (i=0U; i<%dU; i=(U16)(i+1U)) acc = (U16)(acc ^ (U16)(s[i]));' % n)
    if rng.random() < 0.5:                          # a byte compare against a constant (#33)
        c = rng.randint(1, 127)
        L.append('  p = s;')
        L.append('  while (*p) { if (*p == %d) acc = (U16)(acc + 1U); p++; }' % c)
    L.append('  return acc;')
    L.append('}')
    return '\n'.join(L)

if __name__ == '__main__':
    print(program(int(sys.argv[1])))
