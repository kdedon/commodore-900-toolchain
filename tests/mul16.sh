#!/bin/sh
# mul16.sh -- 16-bit operands take the one-word MULT and DIV.
#
# Shape: a long product of two 16-bit values is one MULT, with the high word
# corrected for an unsigned factor with bit 15 set, and an unsigned word divided
# by an unsigned word is one DIV, or a compare for a divisor with bit 15 set.
# A ?: or comma of such values is such a factor or divisor.
# An unsigned constant over 0x7FFF keeps MULTL, as does a long times a short.
# Values: mul16.py's operations over edge and random operands and a stride of
# all 16-bit values, hashed and compared with the host's.
H="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$H/host"; . "$H/host/publish.sh"	# $BUILD
CC0="$BUILD/z8001/cc0-z8001"; CC1="$BUILD/z8001/cc1-z8001"
CC2="$BUILD/z8001/cc2-z8001"; DIS="$BUILD/tools/loutdis"
CCZ="$H/host/ccz"; N2="${N2:-$(sh "$H/host/runner.sh")}"
[ -n "$N2" ] || exit 2
VAR=800000020800
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

cat > "$T/s.c" <<'EOF2'
short s1, s2; unsigned short u1, u2; unsigned char c1, c2; signed char sc; unsigned uu;
long ss(void) { return (long)s1 * s2; }
long sk(void) { return (long)s1 * 1000; }
long kn(void) { return -7L * s1; }
long bs(void) { return (long)sc * s1; }
long cs(void) { return (long)c1 * s1; }
unsigned long cc(void) { return (unsigned long)c1 * c2; }
unsigned long uk(void) { return (unsigned long)u1 * 15; }
unsigned long ub(void) { return (unsigned long)u1 * 80; }
unsigned long uc(void) { return (unsigned long)u1 * c1; }
unsigned long cu(void) { return (unsigned long)c1 * u1; }
unsigned du(void) { return u1 / c1; }
unsigned ru(void) { return u1 % c1; }
void ad(void) { uu /= c1; }
void ar(void) { uu %= c1; }
unsigned long uu2(void) { return (unsigned long)u1 * u2; }
long su(void) { return (long)s1 * u2; }
long un(void) { return (long)u1 * -7; }
unsigned dw(void) { return u1 / u2; }
unsigned rw(void) { return u1 % u2; }
void aw(void) { uu /= u2; }
void rv(void) { uu %= u2; }
unsigned long uh(void) { return (unsigned long)u1 * 40000; }
unsigned da(void) { return u1 / (u2 & 0x7FFF); }
unsigned long ua(void) { return (unsigned long)u1 * (u2 & 0xFF); }
long sh(void) { return (long)s1 * 16; }
unsigned long qu(void) { return (unsigned long)(uu ? s1 : s2) * u2; }
long qs(void) { return (long)(uu ? s1 : s2) * s2; }
unsigned long qw(void) { return (unsigned long)(uu ? u1 : u2) * u2; }
unsigned long qc(void) { return (unsigned long)(uu++, s1) * u2; }
long qm(void) { return (long)(uu ? u1 : 7) * s2; }
unsigned long qn(void) { return (unsigned long)(uu ? (u1 ? s1 : 3) : (short)c1) * u2; }
unsigned dq(void) { return u1 / (uu ? 10 : 300); }
unsigned rq(void) { return u1 % (uu ? c1 : 7); }
long ls(l, s) long l; short s; { return (l + 1) * s; }
unsigned long lu(l, s) long l; short s; { return (unsigned long)((l + 1) * s); }
EOF2
"$CC0" $VAR "$T/s.c" "$T/s.z0" && "$CC1" $VAR "$T/s.z0" "$T/s.z1" &&
"$CC2" 0012 "$T/s.z1" "$T/s.o" "$T/s.scr" 0 || { echo "  mul16: compile FAIL"; exit 1; }
body() {	# function name -> its instructions
	"$DIS" "$T/s.o" -fn "$1_" | sed 1d
}
shape() {	# name want-regex refuse-regex
	b=$(body "$1")
	if printf '%s\n' "$b" | grep -Eq "$2" && ! printf '%s\n' "$b" | grep -Eq "$3"; then
		printf '  %-4s PASS\n' "$1"
	else
		fail=1; printf '  %-4s FAIL\n' "$1"; printf '%s\n' "$b" | sed 's/^/      /'
	fi
}
for f in ss sk kn bs cs cc; do shape $f ' MULT ' 'MULTL|EXTS |JR '; done
shape uk 'INC +R0,#15' 'MULTL'
for f in uc cu ua; do shape $f ' MULT ' 'MULTL'; done
for f in du ru ad ar da; do shape $f ' DIV ' 'DIVL'; done
shape ub ' MULT ' 'MULTL'
for f in uu2 su un; do shape $f ' MULT ' 'MULTL'; done
for f in dw rw aw rv; do shape $f ' DIV ' 'DIVL'; done
shape uh 'MULTL' ' MULT '
shape sh 'SLLL' 'MULT'
for f in qu qs qw qc qm qn; do shape $f ' MULT ' 'MULTL'; done
for f in dq rq; do shape $f ' DIV ' 'DIVL|JR +PL'; done
for f in ls lu; do shape $f 'MULTL' ' MULT '; done

python3 "$H/tests/mul16.py" "$T" 64 3 7 &&
cc -O1 -o "$T/h" "$T/h.c" && "$T/h" > "$T/want" &&
"$CCZ" -o "$T/t" "$T/t.c" >/dev/null 2>&1 || { echo "  mul16: values build FAIL"; exit 1; }
"$N2" -runexec "$T/t" 2>/dev/null | grep -v '^\[exit' > "$T/got"
if cmp -s "$T/want" "$T/got"; then
	echo "  values PASS ($(wc -l < "$T/want") operations)"
else
	fail=1; echo "  values FAIL"; diff "$T/want" "$T/got" | sed 's/^/      /'
fi
[ $fail = 0 ] && echo "=== mul16: PASS ===" || echo "=== mul16: FAIL ==="
exit $fail
