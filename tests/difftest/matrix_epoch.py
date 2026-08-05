# matrix_epoch.py - ENUMERATED (not random) gcc differential over the NTP/UNIX
# epoch arithmetic the SNTP client (os/net/sntp.c) depends on.
#
#   python3 tests/difftest/matrix_epoch.py [-v]
#
# WHY THIS EXISTS.  NTP counts seconds from 1900, UNIX from 1970, and the offset
# between them -- 2208988800 -- is LARGER than LONG_MAX (2147483647).  So is the
# NTP seconds field itself for any date after 1968.  Every step of
#
#       time_t = (long)(ntp_seconds - 2208988800UL)
#
# is therefore unsigned-long arithmetic that CROSSES the 2^31 boundary, and a
# single signed slip anywhere in it lands the machine in 1900 or at a negative
# time_t.  The result is the only part that fits a signed long (a 2026 date is
# 1.78e9).  This matrix pins the whole path: the constant's construction, the
# subtraction, the unsigned comparison used to reject a pre-1970 timestamp, and
# the halves of the 32-bit result as they are actually read back.
#
# Note the constant is built from HEX HALVES, never as a bare decimal:
#       #define NTP_EPOCH (((unsigned long)0x83AAU << 16) | 0x7E80U)
# cc0's ival_t is 16-bit and its constant fold sign-extends, so an unsigned-long-ranged
# decimal literal is exactly the shape whose typing has bitten this port before.
# Both the hex-halves idiom and, separately, a bare decimal are compiled here --
# if the bare-decimal form ever mismatches, that is the front end, not this test.
#
# Values are fed through a NOINLINE-by-construction runtime path (a global array
# written at run time) so what is compared is the CODEGEN, not the shared
# constant folder.
#
# Oracle soundness: unsigned arithmetic wraps by definition in both compilers, so
# every case is free of undefined behaviour.  The one implementation-defined step
# is (long) of an unsigned value above LONG_MAX; gcc and the original MWC back end
# both define it as the modular reinterpretation, which is what this target must
# reproduce -- and the client never relies on it (it rejects such a timestamp).
#
# Reuses run.py's z8001()/host(), so the type-width prelude and the 16-bit result
# extraction are identical to the random fuzzer.
import sys, os, concurrent.futures
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import run as R

EPOCH = 2208988800          # seconds 1900-01-01 .. 1970-01-01

# NTP seconds values, as (hi16, lo16) -- the halves are how the client actually
# assembles the field off the wire, and how the constant is written in the source.
VALS = [
    ('now2026',   0xEE0F, 0x7A00),   # 3993991680 -> 1785002880, a real 2026 date
    ('epoch1970', 0x83AA, 0x7E80),   # exactly the offset       -> 0
    ('justover',  0x83AA, 0x7E81),   # one second after 1970    -> 1
    ('justunder', 0x83AA, 0x7E7F),   # one second BEFORE 1970   -> must be rejected
    ('long_max',  0x7FFF, 0xFFFF),   # 2147483647, below the offset AND at LONG_MAX
    ('long_min',  0x8000, 0x0000),   # 2147483648, first value past LONG_MAX
    ('era_end',   0xFFFF, 0xFFFF),   # 4294967295, the 2036 era rollover
    ('y2036',     0x0000, 0x0001),   # era 1 wrapped to 1, far below the offset
]

# What f() returns.  run.py compares 16 bits, so the 32-bit answer is read back a
# half at a time -- and the halves are checked SEPARATELY on purpose: a lost carry
# out of the low word shows only in the high word.
PROJ = {
    'lo':  '(U16)(d)',
    'hi':  '(U16)(d >> 16)',
    'ge':  '(U16)(n >= EPOCH)',        # the pre-1970 guard, unsigned compare
    'lt':  '(U16)(n < EPOCH)',
    'slo': '(U16)((I32)d)',            # via the signed time_t the client stores
    'shi': '(U16)(((I32)d) >> 16)',
}

# How EPOCH is spelled.  `halves' is the idiom the client uses; `decimal' is the
# form deliberately avoided, kept as a canary on cc0's literal typing.
EPOCH_DEFS = {
    'halves':  '#define EPOCH (((U32)0x83AAU << 16) | 0x7E80U)',
    'decimal': '#define EPOCH ((U32)2208988800)',
}

# The wire value reaches the arithmetic through a global written at run time, so
# neither compiler can constant-fold the subtraction away.
TMPL = '''%(epochdef)s
U32 g;
U32 wire(h, l)
U16 h;
U16 l;
{
\treturn ((U32)h << 16) | (U32)l;
}
int f()
{
\tU32 n, d;
\tg = wire(%(hi)#06x, %(lo)#06x);
\tn = g;
\td = n - EPOCH;
\treturn %(proj)s;
}
'''


def cases():
    for spelling, epochdef in EPOCH_DEFS.items():
        for name, hi, lo in VALS:
            for proj, expr in PROJ.items():
                prog = TMPL % {'epochdef': epochdef, 'hi': hi, 'lo': lo,
                               'proj': expr}
                yield (spelling, name, proj, hi, lo, prog)


def expected(hi, lo, proj):
    """Independent oracle -- gcc is checked against this too, so a shared
    misunderstanding of the arithmetic cannot pass silently."""
    n = (hi << 16) | lo
    d = (n - EPOCH) & 0xFFFFFFFF
    return {'lo': d & 0xFFFF, 'hi': (d >> 16) & 0xFFFF,
            'ge': 1 if n >= EPOCH else 0, 'lt': 1 if n < EPOCH else 0,
            'slo': d & 0xFFFF, 'shi': (d >> 16) & 0xFFFF}[proj]


def one(c):
    spelling, name, proj, hi, lo, prog = c
    zs, zv = R.z8001(prog)
    hs, hv = R.host(prog)
    if zs != 'ok' or hs != 'ok':
        return (c, 'ERR', f'{zs}/{hs}', zv if zs != 'ok' else hv)
    want = expected(hi, lo, proj)
    if hv != want:
        return (c, 'ORACLE', zv, f'{hv} (want {want})')
    return (c, 'ok' if zv == hv else 'MISMATCH', zv, hv)


def main():
    verbose = '-v' in sys.argv
    cs = list(cases())
    tally = {}
    bad = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        for c, st, a, b in ex.map(one, cs):
            spelling, name, proj, hi, lo, _ = c
            t = tally.setdefault(spelling, [0, 0, 0])
            if st == 'ok':
                t[0] += 1
                if verbose:
                    print(f'ok       {spelling:8s} {name:10s} {proj:4s} = {a}')
            else:
                t[1 if st in ('MISMATCH', 'ORACLE') else 2] += 1
                bad += 1
                print(f'{st:9s} {spelling:8s} {name:10s} {proj:4s} '
                      f' z8001={a} host={b}')
    print()
    tp = tf = te = 0
    for spelling in EPOCH_DEFS:
        if spelling not in tally:
            continue
        p, f, e = tally[spelling]
        tp += p; tf += f; te += e
        print(f'  {spelling:8s}  {p:4d} pass  {f:4d} mismatch  {e:4d} pipeline-err')
    print(f'\n=== epoch matrix: {tp} pass, {tf} mismatch, {te} pipeline-err '
          f'(of {tp+tf+te} cases) ===')
    sys.exit(1 if bad else 0)


main()
