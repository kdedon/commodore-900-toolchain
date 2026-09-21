#!/bin/sh
# multiseg-text.sh -- prove `ld -L' multi-segment TEXT: a program whose SHRI
# exceeds one 64K hardware segment links, loads across consecutive segments,
# and its cross-segment CALLs resolve correctly (the enabler for elvis + the
# termio kernel).  Split across .c files so no single object exceeds 64K.
#
# The second case is the big-text link shape: t3 spans three text segments and
# t4 four, with named modules at fixed places in the link order (fmid+callthru
# after the first filler block, t4h1 beside them, t4h2+t4fpsum after the second,
# ftail+fback+getfp after the last, t4h3 behind them).  `ld -L' places modules
# in link order and moves a module that would cross a 64K boundary whole into
# the next segment, so tools/loutid -s must find every named symbol in SHRI,
# at strictly increasing addresses in link order, main_ in segment 3, and the
# last named module in the highest segment any of the program's own modules
# reach (libc follows them and may go further), with that many segments.  The program then runs and prints what each cross-segment
# route returned, and the host's answer to the same source must match.
set -e
H="$(cd "$(dirname "$0")/.." && pwd)"
B="${C900_TC_BUILD:-$H/host/build}"	# the lane's build dir; see host/publish.sh
T=$(mktemp -d)
python3 - "$T" <<'PY'
import sys
T = sys.argv[1]
for part in range(3):
    lines = []
    for i in range(part*310, part*310+310):
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
want=$(gcc -std=gnu89 -w -o "$T/bigh" "$T/bigm.c" "$T/big0.c" "$T/big1.c" "$T/big2.c" && "$T/bigh")
if [ "$got" = "$want" ] && [ "$ts" -gt 65536 ]; then
	echo "=== multi-segment text: PASS (text=$ts B > 64K, $got == host)"
else
	echo "=== multi-segment text: FAIL (text=$ts got=[$got] want=[$want])"; exit 1
fi

python3 - "$T" <<'PY'
import sys
T = sys.argv[1]
def w(name, text):
    open("%s/%s.c" % (T, name), "w").write(text)
for fi in range(52):
    w("g%d" % fi, "".join(
        "g%d(a, b) int a, b; { int t; t = a * %d + b; t = t ^ (a << 3);"
        " t = t + (b >> 1); t = t - (a & 0x5A5A); return t | (b + %d); }\n"
        % (fi * 56 + j, (fi * 56 + j) % 97 + 1, fi * 56 + j) for j in range(56)))
w("mid", "fmid(a, b) int a, b; { return (a * 51 + b * 3 ^ b << 2) - (a & 0x0F0F); }\n"
         "callthru(fp, a, b) int (*fp)(); int a, b; { return (*fp)(a, b); }\n")
w("c1", "extern int t4h2();\nt4h1(a, b) int a, b; { return t4h2(a, b) + 31; }\n")
w("c2", "extern int g0(), fmid(), t4h3();\n"
        "static int (*t4tab[3])() = { g0, fmid, t4h3 };\n"
        "t4h2(a, b) int a, b; { return t4h3(a, b) + 17; }\n"
        "t4fpsum(a, b) int a, b; { register int i, s; s = 0;"
        " for (i = 0; i < 3; i++) s += (*t4tab[i])(a, b); return s; }\n")
w("tail", "extern int g0(), fmid();\n"
          "ftail(a, b) int a, b; { return (a * 77 + b * 5 ^ a << 4) + (b & 0x3333); }\n"
          "fback(a, b) int a, b; { return g0(a, b) + fmid(a, b) + 777; }\n"
          "int (*getfp())() { return fmid; }\n")
w("c3", "extern int g0();\nt4h3(a, b) int a, b; { return g0(a, b) + 7; }\n")
calls3 = ("printf(\"%d %d %d %d %d\\n\", g0(3, 5), ftail(7, 9), fback(11, 13),"
          " callthru(ftail, 6, 8), (*getfp())(9, 4));")
calls4 = ("printf(\"%d %d %d %d %d %d\\n\", ftail(7, 9), fback(11, 13), t4h1(5, 12),"
          " t4fpsum(8, 3), callthru(ftail, 6, 8), (*getfp())(9, 4));")
ext = "extern int g0(), ftail(), fback(), callthru(), t4h1(), t4fpsum();\nextern int (*getfp())();\n"
w("main3", ext + "main() { " + calls3 + " return 0; }\n")
w("main4", ext + "main() { " + calls4 + " return 0; }\n")
PY
seq_o() { i=$1; while [ "$i" -le "$2" ]; do printf '%s/g%d.c ' "$T" "$i"; i=$((i+1)); done; }
FA=$(seq_o 0 11); FB=$(seq_o 12 22); FC=$(seq_o 23 33); FD=$(seq_o 34 51)
# link order and the segment count each probe must reach
set -- t3 3 "$T/main3.c $FA $T/mid.c $FB $FC $T/tail.c" "main fmid callthru ftail fback getfp" \
       t4 4 "$T/main4.c $FA $T/mid.c $T/c1.c $FB $T/c2.c $FC $FD $T/tail.c $T/c3.c" \
            "main fmid callthru t4h1 t4h2 t4fpsum ftail fback getfp t4h3"
while [ $# -gt 0 ]; do
	p=$1; nseg=$2; srcs=$3; names=$4; shift 4
	"$H/host/ccz" -i -L -o "$T/$p" $srcs >/dev/null 2>&1
	"$B/tools/loutid" -e -s "$T/$p" > "$T/$p.syms"
	why=$(python3 - "$T/$p.syms" "$nseg" $names <<'PY'
import sys
lines = open(sys.argv[1]).read().split("\n")
nseg, names = int(sys.argv[2]), sys.argv[3:]
text = {}
for l in lines[1:]:
    f = l.split()
    if len(f) == 3 and f[0] == "SHRI":
        text[f[2]] = int(f[1], 16)
own = [a for n, a in text.items()
       if n[:-1] in names or (n[0] == "g" and n[1:-1].isdigit())]
bad = []
if "entry=0x3000000" not in lines[0]:
    bad.append("entry not segment 3: " + lines[0].split()[-1])
missing = [n + "_" for n in names if n + "_" not in text]
if missing:
    bad.append("missing from SHRI: " + " ".join(missing))
else:
    addr = [text[n + "_"] for n in names]
    if any(b <= a for a, b in zip(addr, addr[1:])):
        bad.append("not in link order: " + " ".join("%s=%#x" % (n, a) for n, a in zip(names, addr)))
    top = max(own) >> 24
    if addr[0] >> 24 != 3:
        bad.append("main_ at %#x, not segment 3" % addr[0])
    if addr[-1] >> 24 != top:
        bad.append("%s_ at %#x, not in the last text segment %d" % (names[-1], addr[-1], top))
    if top - 3 + 1 < nseg:
        bad.append("text reaches %d segments, want %d" % (top - 2, nseg))
print("; ".join(bad))
PY
)
	got=$("${N2:-$(sh "$H/host/runner.sh")}" -runexec "$T/$p" 2>/dev/null | grep -E '^-?[0-9]+( -?[0-9]+)+$')
	want=$(gcc -std=gnu89 -w -o "$T/${p}h" $srcs && "$T/${p}h")
	if [ -z "$why" ] && [ -n "$got" ] && [ "$got" = "$want" ]; then
		echo "=== multi-segment text $p: PASS ($nseg segments, $(echo $names | wc -w) symbols placed, [$got] == host)"
	else
		echo "=== multi-segment text $p: FAIL (${why:+$why; }got=[$got] want=[$want])"; exit 1
	fi
done
rm -rf "$T"
