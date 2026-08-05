import random, sys
# 2D-array fuzzer: a local U16 [R][C] matrix filled and read with double runtime indices
# m[i][j], accumulating a U16.  Exercises nested index addressing (row*C+col) -- the
# m[i][j] / array-of-array path (#45).  BARE program; run.py adds the prelude.
def program(seed):
    rng = random.Random(seed)
    R = rng.randint(2, 4); C = rng.randint(2, 4)
    base = rng.randint(0, 0xFFFF); k = rng.randint(1, 9)
    L = ['U16 f(){', '  U16 m[%d][%d];' % (R, C), '  U16 i, j, acc;']
    L.append('  for (i=0U; i<%dU; i=(U16)(i+1U))' % R)
    L.append('    for (j=0U; j<%dU; j=(U16)(j+1U))' % C)
    L.append('      m[i][j] = (U16)((U16)(i*%dU) + j + %dU);' % (k, base))
    L.append('  acc = 0U;')
    L.append('  for (i=0U; i<%dU; i=(U16)(i+1U))' % R)
    L.append('    for (j=0U; j<%dU; j=(U16)(j+1U))' % C)
    L.append('      acc = (U16)(acc + m[i][j]);')
    # a transposed read with swapped modded indices (still in-bounds)
    L.append('  for (i=0U; i<%dU; i=(U16)(i+1U))' % C)
    L.append('    for (j=0U; j<%dU; j=(U16)(j+1U))' % R)
    L.append('      acc = (U16)(acc ^ m[j][i]);')
    L.append('  return acc;')
    L.append('}')
    return '\n'.join(L)
if __name__ == '__main__': print(program(int(sys.argv[1])))
