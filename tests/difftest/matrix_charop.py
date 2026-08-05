# matrix_charop.py - ENUMERATED (not random) gcc differential over char compound
# assignment.  Spans the whole operator x signedness x lvalue-shape x value-used
# x operand-value space that `char lv OP= rhs' can take, compiles each program
# through cc0->cc1->n2 -r and through host gcc, and compares the 16-bit result.
#
#   python3 tests/difftest/matrix_charop.py [-v] [--only OP[,OP...]]
#
# Reuses run.py's z8001()/host() (so the type-width prelude and the result
# extraction are the same as the random fuzzer).  Prints one line per failing
# case plus a per-operator pass/fail tally; exit status is non-zero on any
# mismatch or pipeline error.
#
# Notes on oracle soundness.  Every program is free of undefined behaviour:
# divisors are never 0, shift counts are 0..7 and never applied to a negative
# value, and the int-typed intermediate never overflows (char operands are small
# enough).  Storing an out-of-range int into a char, and >> of a negative value,
# are IMPLEMENTATION-DEFINED rather than undefined; both gcc and the original MWC
# back end define them as modular truncation and arithmetic shift, which is the
# behaviour this target must reproduce.
import sys, os, concurrent.futures
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import run as R

# (init, rhs) pairs per operator: signed-char inits, then unsigned-char inits.
VALS = {
 '*=':  ([(5,3),(100,3),(-7,3),(127,2),(0,9),(-128,2),(13,-3),(1,1),(6,1)],
         [(5,3),(200,3),(255,2),(0,9),(13,-3),(6,1)]),
 '/=':  ([(100,3),(-100,3),(100,-3),(-100,-3),(7,7),(0,5),(-128,2),(5,1),(127,1)],
         [(200,3),(200,-3),(7,7),(0,5),(255,2),(5,1)]),
 '%=':  ([(100,7),(-100,7),(100,-7),(-100,-7),(5,5),(0,3),(-128,3),(9,1)],
         [(200,7),(200,-7),(5,5),(0,3),(255,3),(9,1)]),
 '+=':  ([(100,100),(-100,-100),(5,2),(127,1),(-128,-1),(0,0),(-7,3)],
         [(200,100),(5,2),(255,1),(0,0),(7,-3)]),
 '-=':  ([(100,-100),(5,2),(-128,1),(127,-1),(0,0),(-7,3)],
         [(200,-100),(5,2),(0,1),(255,-1),(7,3)]),
 '<<=': ([(3,2),(64,1),(1,7),(100,0),(5,0),(127,1),(9,3)],
         [(3,2),(200,1),(1,7),(200,0),(5,0),(255,1)]),
 '>>=': ([(80,2),(-80,2),(-1,1),(100,0),(-100,0),(127,7),(-128,3)],
         [(80,2),(200,2),(255,1),(200,0),(255,7)]),
 '&=':  ([(15,9),(-1,85),(100,0),(-100,15)],
         [(15,9),(255,85),(200,0)]),
 '|=':  ([(8,5),(0,255),(100,0),(-100,15)],
         [(8,5),(0,255),(200,0)]),
 '^=':  ([(15,9),(-1,255),(100,0),(-100,15)],
         [(15,9),(255,255),(200,0)]),
}

# Program shapes.  Each formats with ty/init/op/rhs and returns the value the
# comparison is made on.  `ev' names what is compared: the STORED lvalue (effect
# context, the compound assign is a statement) or the ASSIGNMENT'S VALUE (the
# result register, which must be the stored char widened back to an int).
SHAPES = {
 'glob-eff':  '%(ty)s g;\nint f(){ g = %(init)d; g %(op)s %(rhs)d; return g; }',
 'glob-val':  '%(ty)s g;\nint f(){ int v; g = %(init)d; v = (g %(op)s %(rhs)d); return v; }',
 'loc-eff':   'int f(){ %(ty)s c; c = %(init)d; c %(op)s %(rhs)d; return c; }',
 'loc-val':   'int f(){ %(ty)s c; int v; c = %(init)d; v = (c %(op)s %(rhs)d); return v; }',
 'deref-eff': '%(ty)s g;\nint f(){ %(ty)s *p; g = %(init)d; p = &g; *p %(op)s %(rhs)d; return g; }',
 'arr-eff':   '%(ty)s a[3];\nint f(){ a[1] = %(init)d; a[1] %(op)s %(rhs)d; return a[1]; }',
 'arr-val':   '%(ty)s a[3];\nint f(){ int v; a[1] = %(init)d; v = (a[1] %(op)s %(rhs)d); return v; }',
 # runtime rhs: the operand comes through a global int, so neither compiler can
 # fold it into an immediate -- this exercises the register/memory rhs rules.
 'rt-eff':    '%(ty)s g; int y;\nint f(){ g = %(init)d; y = %(rhs)d; g %(op)s y; return g; }',
 'rt-val':    '%(ty)s g; int y;\nint f(){ int v; g = %(init)d; y = %(rhs)d; v = (g %(op)s y); return v; }',
 'reg-eff':   '%(ty)s g;\nint f(){ register int y; g = %(init)d; y = %(rhs)d; g %(op)s y; return g; }',
}

def cases(only):
    for op in (only or VALS):
        for si, ty in enumerate(('I8', 'unsigned char')):
            for init, rhs in VALS[op][si]:
                for sh, tmpl in SHAPES.items():
                    yield (op, ty, sh, init, rhs,
                           tmpl % {'ty': ty, 'init': init, 'op': op, 'rhs': rhs})

def one(c):
    op, ty, sh, init, rhs, prog = c
    zs, zv = R.z8001(prog)
    hs, hv = R.host(prog)
    if zs != 'ok' or hs != 'ok':
        return (c, 'ERR', f'{zs}/{hs}', zv if zs != 'ok' else hv)
    return (c, 'ok' if zv == hv else 'MISMATCH', zv, hv)

def main():
    verbose = '-v' in sys.argv
    only = None
    if '--only' in sys.argv:
        only = sys.argv[sys.argv.index('--only') + 1].split(',')
    cs = list(cases(only))
    tally = {}
    bad = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        for c, st, a, b in ex.map(one, cs):
            op, ty, sh, init, rhs, _ = c
            t = tally.setdefault(op, [0, 0, 0])
            if st == 'ok':
                t[0] += 1
                if verbose:
                    print(f'ok       {ty:14s} {sh:10s} ({init}) {op} {rhs}')
            else:
                t[1 if st == 'MISMATCH' else 2] += 1
                bad += 1
                print(f'{st:9s} {ty:14s} {sh:10s} ({init}) {op} {rhs}  z8001={a} host={b}')
    print()
    tp = tf = te = 0
    for op in VALS:
        if op not in tally:
            continue
        p, f, e = tally[op]
        tp += p; tf += f; te += e
        print(f'  {op:4s}  {p:4d} pass  {f:4d} mismatch  {e:4d} pipeline-err')
    print(f'\n=== charop matrix: {tp} pass, {tf} mismatch, {te} pipeline-err '
          f'(of {tp+tf+te} cases) ===')
    sys.exit(1 if bad else 0)

main()
