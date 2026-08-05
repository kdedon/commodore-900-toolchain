import subprocess, sys, os, re, tempfile, signal
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.abspath(HERE+'/../..')
O=ROOT+'/host/build/z8001'; VAR='800000000800'
N2=os.environ.get('N2', os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'host', 'build', 'n2z8001'))     # the simulator (n2z8001); it runs linked binaries
Z8_DEF='#define U16 unsigned\n#define I16 int\n#define I32 long\n#define U32 unsigned long\n#define I8 char\n'
HO_DEF='#define U16 unsigned short\n#define I16 short\n#define I32 int\n#define U32 unsigned int\n#define I8 signed char\n'
class _R:
    def __init__(s,rc,out,err=''): s.returncode=rc; s.stdout=out; s.stderr=err
def sh(cmd,timeout=15):
    # Run each command in its OWN process group (start_new_session) so a timeout can kill
    # the WHOLE group. With shell=True the command is `sh -c <cmd>'; subprocess's own
    # timeout would kill only that shell, ORPHANING its child -- e.g. a non-terminating
    # generated host binary `h' that then spins forever. killpg reaps the entire tree.
    p=subprocess.Popen(cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                       text=True,start_new_session=True)
    try:
        out,err=p.communicate(timeout=timeout)
        return _R(p.returncode,out,err)
    except subprocess.TimeoutExpired:
        try: os.killpg(os.getpgid(p.pid),signal.SIGKILL)
        except (ProcessLookupError,PermissionError): pass
        try: p.communicate(timeout=5)
        except Exception: pass
        return _R(124,'','timeout')
# The code under test is always cc2-z8001's: the generated program is compiled, linked by
# ld into a real l.out and executed with `-runobjint', with n2z8001 acting only as the CPU.
# gcc compiling the same program with 16-bit types is the oracle -- an INDEPENDENT one,
# which is the property that matters here.  (This harness once had a second mode that ran
# a Go re-implementation of the backend instead; comparing two of our own encoders to each
# other could only ever find disagreements, never a shared misreading of C.)
AS=ROOT+'/host/build/as-z8001'; LD=ROOT+'/host/build/ld-z8001'
_SS=None
def _ssobj():
    # `SS = 0': the segment-base symbol crt0 would normally define.  Bare generated
    # programs link without crt0, so the harness supplies it once per run.
    global _SS
    if _SS is None:
        d=tempfile.mkdtemp(); open(d+'/ss.s','w').write('\t.globl\tSS\nSS = 0\n')
        sh(f'{AS} -o {d}/ss.o {d}/ss.s'); _SS=d+'/ss.o'
    return _SS
def z8001(prog):
    with tempfile.TemporaryDirectory() as d:
        open(d+'/t.c','w').write(Z8_DEF+prog)
        if sh(f'{O}/cc0-z8001 {VAR} {d}/t.c {d}/t.z0').returncode: return ('cc0err',None)
        if sh(f'{O}/cc1-z8001 {VAR} {d}/t.z0 {d}/t.z1').returncode: return ('cc1err',None)
        if sh(f'{O}/cc2-z8001 0010 {d}/t.z1 {d}/t.o {d}/scr 0').returncode: return ('cc2err',None)
        if sh(f'{LD} -R 0x200 -e f_ -o {d}/a {d}/t.o {_ssobj()}').returncode: return ('lderr',None)
        r=sh(f'{N2} -runobjint {d}/a')
        m=re.search(r'R1 = (-?\d+)',r.stdout)
        if not m: return ('runerr',r.stdout[-200:])
        return ('ok', int(m.group(1))&0xFFFF)
def host(prog):
    with tempfile.TemporaryDirectory() as d:
        src=HO_DEF+prog+'\n#include <stdio.h>\nint main(){printf("%u\\n",(unsigned short)f());return 0;}\n'
        open(d+'/t.c','w').write(src)
        if sh(f'gcc -w -O0 -o {d}/h {d}/t.c').returncode: return ('gccerr',None)
        r=sh(f'{d}/h'); 
        try: return ('ok', int(r.stdout.strip())&0xFFFF)
        except: return ('runerr',r.stdout)
def main():
    n=int(sys.argv[1]) if len(sys.argv)>1 else 200
    start=int(sys.argv[2]) if len(sys.argv)>2 else 0
    miss=0; err=0; ok=0
    for s in range(start,start+n):
        prog=sh(f'python3 {os.environ.get("GEN",HERE+"/gen.py")} {s}').stdout
        zs,zv=z8001(prog); hs,hv=host(prog)
        if zs!='ok' or hs!='ok':
            err+=1
            if zs not in('ok',) and zs in('cc0err','cc1err','cc2err','lderr','runerr'):
                print(f'[seed {s}] PIPELINE {zs}/{hs}'); 
            continue
        if zv!=hv:
            miss+=1
            print(f'[seed {s}] MISMATCH z8001={zv} host={hv}\n{prog}\n---')
            if miss>=8: print('(stopping after 8 mismatches)'); break
        else: ok+=1
    print(f'\n=== {ok} match, {miss} MISMATCH, {err} pipeline-err (of {n} seeds) ===')
# Importable: z8001()/host() are reused by the enumerated matrices (matrix_charop.py).
if __name__=='__main__':
    main()
