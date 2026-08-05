#!/bin/sh
# gensrc.sh N OUT - synthesize N benign functions into OUT (a large C file)
n="$1"; out="$2"
: > "$out"
i=0
while [ "$i" -lt "$n" ]; do
	cat >> "$out" <<EOF
int	g$i;
int
fn$i(a, b)
int a;
int b;
{
	register int	t;

	t = a + b * $i;
	g$i = t;
	if (t > 100)
		return (t - g$i);
	return (t + 1);
}
EOF
	i=$((i+1))
done
