#!/usr/bin/env python3
# mul16.py DIR N SEED [STEP] -> DIR/t.c (Z8001) and DIR/h.c (host reference)
# Integer multiply, divide and remainder, each op hashed over its operands.
# N operand values (edges, then random), every STEP-th 16-bit value against 8 bytes.
import random, sys
d, n, seed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
step = int(sys.argv[4]) if len(sys.argv) > 4 else 1
random.seed(seed)
edge = [0,1,2,3,-1,-2,-3,7,10,80,127,128,255,256,0x7FFE,0x7FFF,-0x8000,-0x7FFF,0x4000,-0x4000,0x1234,-0x1234,100,-100]
vals = edge + [random.randint(-0x8000,0x7FFF) for _ in range(n-len(edge))]
cvals = [0,1,2,3,7,10,100,127,128,200,254,255] + [random.randint(0,255) for _ in range(20)]
# (name, kind, target expr, host expr); a,b short; ua,ub unsigned short; c,d unsigned char; sc signed char
# kind: 'ss' pairs over vals x vals, 'sc' vals x cvals (nonzero d where dividing)
ops = [
 ("lss",  "ss", "(long)a * b",               "(int32_t)a * b"),
 ("lsk1", "s",  "(long)a * 10",              "(int32_t)a * 10"),
 ("lsk2", "s",  "(long)a * -7",              "(int32_t)a * -7"),
 ("lsk3", "s",  "(long)a * 32767",           "(int32_t)a * 32767"),
 ("lsk4", "s",  "(long)a * -32768",          "(int32_t)a * -32768"),
 ("lsk5", "s",  "1000L * a",                 "(int32_t)a * 1000"),
 ("lsc",  "sc", "(long)a * c",               "(int32_t)a * c"),
 ("lscs", "sc", "(long)sc * a",              "(int32_t)sc * a"),
 ("lcc",  "sc", "(long)c * (unsigned char)a","(int32_t)c * (uint8_t)a"),
 ("ulcc", "sc", "(unsigned long)c * d",      "(uint32_t)c * d"),
 ("ulu80","s",  "(unsigned long)ua * 80",    "(uint32_t)ua * 80"),
 ("lu3",  "s",  "(long)ua * 3",              "(int32_t)((uint32_t)ua * 3)"),
 ("ulu7f","s",  "(unsigned long)ua * 0x7FFF","(uint32_t)ua * 0x7FFF"),
 ("ulu1", "s",  "(unsigned long)ua * 1",     "(uint32_t)ua"),
 ("uluc", "sc", "(unsigned long)ua * c",     "(uint32_t)ua * c"),
 ("ulcu", "sc", "(unsigned long)c * ua",     "(uint32_t)c * ua"),
 ("ulcue","sc", "(unsigned long)(unsigned char)(c+1) * ua", "(uint32_t)(uint8_t)(c+1) * ua"),
 ("luu",  "ss", "(unsigned long)ua * ub",    "(uint32_t)ua * ub"),
 ("lsu",  "ss", "(long)a * ub",              "(int32_t)((int64_t)a * ub)"),
 ("lexp", "ss", "(long)(short)(a + b) * (short)(a - b)", "(int32_t)(int16_t)(a + b) * (int16_t)(a - b)"),
 ("lacc", "ss", "acc + (long)a * b",         "(int32_t)((uint32_t)acc + (uint32_t)((int32_t)a * b))"),
 ("ii",   "ss", "a * b",                     "(int16_t)((int32_t)a * b)"),
 ("uu",   "ss", "ua * ub",                   "(uint16_t)((uint32_t)ua * ub)"),
 ("di",   "ssnz","a / b",                    "(int16_t)((int32_t)a / b)"),
 ("ri",   "ssnz","a % b",                    "(int16_t)((int32_t)a % b)"),
 ("du",   "ssnz","ua / ub",                  "(uint16_t)(ua / ub)"),
 ("ru",   "ssnz","ua % ub",                  "(uint16_t)(ua % ub)"),
 ("duc",  "scnz","ua / d",                   "(uint16_t)(ua / d)"),
 ("ruc",  "scnz","ua % d",                   "(uint16_t)(ua % d)"),
 # unsigned char promotes to unsigned int, as in K&R
 ("dsc",  "scnz","a / d",                    "(uint16_t)((uint16_t)a / d)"),
 ("rsc",  "scnz","a % d",                    "(int16_t)(uint16_t)((uint16_t)a % d)"),
 ("ducx", "scnz","ua / (unsigned char)(d | 1)", "(uint16_t)(ua / (uint8_t)(d | 1))"),
 ("adu",  "scnz","(t = ua, t /= d, t)",      "(uint16_t)(ua / d)"),
 ("aru",  "scnz","(t = ua, t %= d, t)",      "(uint16_t)(ua % d)"),
 ("ami",  "ss", "(s = a, s *= b, s)",        "(int16_t)((int32_t)a * b)"),
 ("adi",  "ssnz","(s = a, s /= b, s)",       "(int16_t)((int32_t)a / b)"),
 ("ari",  "ssnz","(s = a, s %= b, s)",       "(int16_t)((int32_t)a % b)"),
 ("adu2", "ssnz","(t = ua, t /= ub, t)",     "(uint16_t)(ua / ub)"),
 ("aru2", "ssnz","(t = ua, t %= ub, t)",     "(uint16_t)(ua % ub)"),
 ("lun",  "s",  "(long)ua * -7",             "(int32_t)((int64_t)ua * -7)"),
 ("lusc", "sc", "(long)ua * sc",             "(int32_t)((int64_t)ua * sc)"),
 ("luh",  "s",  "(unsigned long)ua * 40000", "(uint32_t)ua * 40000"),
 ("lus2", "ss", "(long)ua * (short)(b + 1)", "(int32_t)((int64_t)ua * (int16_t)(b + 1))"),
 ("ulua", "ss", "(unsigned long)ua * (ub & 0x7FF)", "(uint32_t)ua * (ub & 0x7FF)"),
 ("lsau", "ss", "(long)(a & 0xFF) * ub",     "(int32_t)((uint32_t)(a & 0xFF) * ub)"),
 ("uluc2","ss", "(unsigned long)ua * (unsigned char)b", "(uint32_t)ua * (uint8_t)b"),
 ("dua",  "ss7", "ua / (ub & 0x7FFF)",       "(uint16_t)(ua / (ub & 0x7FFF))"),
 ("rua",  "ss7", "ua % (ub & 0x7FFF)",       "(uint16_t)(ua % (ub & 0x7FFF))"),
 ("adua", "ss7", "(t = ua, t /= ub & 0x7FFF, t)", "(uint16_t)(ua / (ub & 0x7FFF))"),
 ("arua", "ss7", "(t = ua, t %= ub & 0x7FFF, t)", "(uint16_t)(ua % (ub & 0x7FFF))"),
 # a long times a widened short is MULTL, not the unsigned-word rule
 ("lls",  "ss", "(acc + a) * b",             "(int32_t)((uint32_t)(acc + a) * (uint32_t)(int32_t)b)"),
 ("llp",  "ss", "(acc | 1) * (short)(a - b)", "(int32_t)((uint32_t)(acc | 1) * (uint32_t)(int32_t)(int16_t)(a - b))"),
 ("llq",  "ss", "(L)((a & 2) ? acc : 5L) * b", "(int32_t)((uint32_t)((a & 2) ? acc : 5) * (uint32_t)(int32_t)b)"),
 # a ?: or comma of 16-bit values is a 16-bit factor or divisor
 ("qsu",  "ss", "(UL)((a & 2) ? a : b) * ub", "(uint32_t)((a & 2) ? a : b) * ub"),
 ("qsc",  "ss", "(UL)(short)((a & 2) ? a + b : b) * ub", "(uint32_t)(int16_t)((a & 2) ? a + b : b) * ub"),
 ("qss",  "ss", "(L)((a & 2) ? a : b) * (short)(a - b)", "(int32_t)((a & 2) ? a : b) * (int16_t)(a - b)"),
 ("qsk",  "ss", "(L)((a & 2) ? a : -100) * b", "(int32_t)((a & 2) ? a : -100) * b"),
 ("qls",  "ss", "(L)((a & 2) ? a : b) * ub",  "(int32_t)((int64_t)((a & 2) ? a : b) * ub)"),
 ("quu",  "ss", "(UL)((a & 2) ? ua : ub) * ub", "(uint32_t)((a & 2) ? ua : ub) * ub"),
 ("quk",  "ss", "(UL)((a & 2) ? ua : 40000u) * ub", "(uint32_t)((a & 2) ? ua : 40000u) * ub"),
 ("qkk",  "ss", "(UL)((a & 2) ? 65535u : 33000u) * ub", "(uint32_t)((a & 2) ? 65535u : 33000u) * ub"),
 ("quc",  "ss", "(UL)((a & 2) ? ua : (unsigned char)b) * ub", "(uint32_t)((a & 2) ? ua : (uint8_t)b) * ub"),
 ("qus",  "ss", "(L)((a & 2) ? ua : ub) * b", "(int32_t)((int64_t)((a & 2) ? ua : ub) * b)"),
 ("qum",  "ss", "(L)((a & 2) ? ua : (b & 0x7F)) * b", "(int32_t)((int64_t)((a & 2) ? ua : (b & 0x7F)) * b)"),
 ("qnn",  "ss", "(UL)((a & 2) ? ((a & 4) ? a : b) : 7) * ub", "(uint32_t)((a & 2) ? ((a & 4) ? a : b) : 7) * ub"),
 ("qcm",  "ss", "(UL)(s = b, (a & 2) ? a : s) * ub", "(uint32_t)((a & 2) ? a : b) * ub"),
 ("qcu",  "ss", "(UL)(t = ub, (a & 2) ? ua : t) * ub", "(uint32_t)((a & 2) ? ua : ub) * ub"),
 ("qbu",  "sc", "(UL)((a & 2) ? c : (unsigned char)a) * ua", "(uint32_t)((a & 2) ? c : (uint8_t)a) * ua"),
 ("qmx",  "ss", "(UL)((a & 2) ? a : ub) * ub", "(uint32_t)(uint16_t)((a & 2) ? (uint16_t)a : ub) * ub"),
 ("qcb",  "ss", "(UL)(unsigned char)((a & 2) ? a : b) * ub", "(uint32_t)(uint8_t)((a & 2) ? a : b) * ub"),
 ("qq",   "ss", "(UL)((a & 2) ? ua : ub) * (UL)((a & 4) ? ub : 1000)", "(uint32_t)((a & 2) ? ua : ub) * (uint32_t)((a & 4) ? ub : 1000)"),
 ("dq",   "ss", "ua / ((a & 2) ? 10 : 300)", "(uint16_t)(ua / ((a & 2) ? 10 : 300))"),
 ("rq",   "scnz", "ua % ((a & 2) ? d : 7)",  "(uint16_t)(ua % ((a & 2) ? d : 7))"),
 ("adq",  "ss", "(t = ua, t /= (a & 2) ? 3 : 1000, t)", "(uint16_t)(ua / ((a & 2) ? 3 : 1000))"),
 ("arq",  "scnz", "(t = ua, t %= (a & 2) ? (unsigned char)(d | 1) : 9, t)", "(uint16_t)(ua % ((a & 2) ? (uint8_t)(d | 1) : 9))"),
 ("dqc",  "ss", "ua / (s = b, (a & 2) ? 5 : 77)", "(uint16_t)(ua / ((a & 2) ? 5 : 77))"),
 ("dqk",  "ss", "ua / ((a & 2) ? 40000u : 7)", "(uint16_t)(ua / ((a & 2) ? 40000u : 7))"),
]
def emit(host):
    o=[]
    if host:
        o.append("#include <stdio.h>\n#include <stdint.h>\ntypedef int32_t L; typedef uint32_t UL;")
    else:
        o.append("typedef long L; typedef unsigned long UL;")
    o.append("short V[%d] = {%s};" % (len(vals), ",".join(str(v) for v in vals)))
    o.append("unsigned char C[%d] = {%s};" % (len(cvals), ",".join(str(v) for v in cvals)))
    for name, kind, te, he in ops:
        e = he if host else te
        if host:
            sig = "UL f_%s(int16_t a, int16_t b, uint8_t d, L acc)" % name
            body = "{ uint16_t ua = a, ub = b, t; int16_t s; uint8_t c = d; int8_t sc = (int8_t)d; (void)ua;(void)ub;(void)t;(void)s;(void)c;(void)sc;(void)acc; return (UL)(%s); }" % e
        else:
            sig = "UL f_%s(a, b, d, acc) short a, b; unsigned char d; L acc;" % name
            body = "{ unsigned short ua = a, ub = b, t; short s; unsigned char c = d; signed char sc = d; return (UL)(%s); }" % e
        o.append(sig + "\n" + body)
    o.append("UL h;\nmix(x) UL x; { h = h * 31 + x; }" if not host else "UL h; void mix(UL x) { h = h * 31 + x; }")
    o.append(("int main(void)" if host else "main()") + "\n{\n\tint i, j;")
    nv, nc = len(vals), len(cvals)
    for name, kind, te, he in ops:
        o.append("\th = 0;")
        if kind in ("ss","ssnz","ss7"):
            cond = {"ss": "", "ssnz": " if (V[j] != 0)", "ss7": " if ((V[j] & 0x7FFF) != 0)"}[kind]
            o.append("\tfor (i = 0; i < %d; i++) for (j = 0; j < %d; j++)%s mix(f_%s(V[i], V[j], 0, (L)V[j] << 8));" % (nv,nv,cond,name))
        elif kind == "s":
            o.append("\tfor (i = 0; i < %d; i++) mix(f_%s(V[i], 0, 0, 0));" % (nv,name))
        else:
            cond = " if (C[j] != 0)" if kind=="scnz" else ""
            o.append("\tfor (i = 0; i < %d; i++) for (j = 0; j < %d; j++)%s mix(f_%s(V[i], 0, C[j], 0));" % (nv,nc,cond,name))
        o.append('\tprintf("%s %%lx\\n", %sh);' % (name, "(unsigned long)" if host else ""))
    xd = [1, 2, 3, 7, 80, 127, 128, 255]
    o.append("\t{ unsigned char XD[8] = {%s}; long k;" % ",".join(map(str, xd)))
    for name, kind, te, he in ops:
        if kind in ("s", "sc", "scnz"):
            o.append("\th = 0; for (k = 0; k < 65536L; k += %d) for (j = 0; j < 8; j++) mix(f_%s((short)k, 0, XD[j], 0));" % (step, name))
            o.append('\tprintf("x%s %%lx\\n", %sh);' % (name, "(unsigned long)" if host else ""))
    o.append("\t}")
    o.append("\treturn 0;\n}")
    return "\n".join(o)+"\n"
open(d + "/t.c", "w").write(emit(False)); open(d + "/h.c", "w").write(emit(True))
