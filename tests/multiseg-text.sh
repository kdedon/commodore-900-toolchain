#!/bin/sh
# multiseg-text.sh -- prove `ld -L' multi-segment TEXT: a program whose SHRI
# exceeds one 64K hardware segment links, loads across consecutive segments,
# and its cross-segment CALLs resolve correctly (the enabler for elvis + the
# termio kernel).  Split across .c files so no single object exceeds 64K.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d)
python3 - "$T" <<'PY'
import sys
T = sys.argv[1]
for part in range(3):
    lines = []
    for i in range(part*250, part*250+250):
        lines.append("int fn%d(x) int x; { int a,b,c,d; a=x+%d; b=a*3; c=b-%d; d=c+a*b; return (a^b)+(c&d)+%d; }" % (i,i,i,i))
    open("%s/big%d.c" % (T, part), "w").write("\n".join(lines))
open("%s/bigm.c" % T, "w").write(
  "extern int fn0(),fn740(),fn400();\n"
  "main(){ long s; s=0; s+=fn0(1); s+=fn740(2); s+=fn400(3);\n"
  '  printf("sum=%ld\\n", s); return 0; }\n')
PY
"$H/host/ccz" -i -L -o "$T/big.out" "$T/bigm.c" "$T/big0.c" "$T/big1.c" "$T/big2.c" >/dev/null 2>&1
ts=$(python3 -c "b=open('$T/big.out','rb').read(); print((b[8]|b[9]<<8)<<16 | (b[10]|b[11]<<8))")
got=$("${N2:-$(sh "$H/host/runner.sh")}" -runexec "$T/big.out" 2>/dev/null | grep -oE 'sum=-?[0-9]+')
want=$(gcc -w -o "$T/bigh" "$T/bigm.c" "$T/big0.c" "$T/big1.c" "$T/big2.c" && "$T/bigh")
if [ "$got" = "$want" ] && [ "$ts" -gt 65536 ]; then
	echo "=== multi-segment text: PASS (text=$ts B > 64K, $got == host)"
else
	echo "=== multi-segment text: FAIL (text=$ts got=[$got] want=[$want])"; exit 1
fi
rm -rf "$T"
