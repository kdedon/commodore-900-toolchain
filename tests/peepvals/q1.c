extern printf();
int g, a[4], i = 2; char gc;
d(x) int x; { return x / 2; }
ad(x) int x; { x /= 2; return x; }
gd(x) int x; { g = x; g /= 2; return g; }
xd(x) int x; { a[i] = x; a[i] /= 2; return a[i]; }
yd(x) int x; { register int y; y = x; y /= 2; return y; }
unsigned ud(x) int x; { return x / 2; }
long ld(x) int x; { return x / 2; }
cd(x) int x; { char c; c = x; c /= 2; return c; }
gcd(x) int x; { gc = x; return gc /= 2; }
sd(x, y) int x, y; { return (x + y) / 2 + (x - y) / 2; }
qd(x) int x; { return x / 2 ? 1 : 0; }
long ref(x) int x; { long l = x; return l >= 0 ? l >> 1 : -((-l) >> 1); }
main() { long x, bad = 0, sum = 0; int v, w;
 for (x = -32768L; x <= 32767L; x++) { v = (int)x; w = (int)ref(v);
  if (d(v) != w || ad(v) != w || gd(v) != w || xd(v) != w || yd(v) != w || ud(v) != (unsigned)w || ld(v) != (long)w || qd(v) != (w != 0)) { if (bad < 5) printf("bad %d\n", v); bad++; }
  sum += d(v);
  if (v >= -128 && v <= 127 && (cd(v) != w || gcd(v) != w)) { if (bad < 5) printf("badc %d\n", v); bad++; }
  if (sd(v, 7) != (int)(ref(v + 7) + ref(v - 7)) && v < 32700 && v > -32700) { if (bad < 5) printf("bads %d\n", v); bad++; } }
 printf("bad %ld sum %ld\n", bad, sum); return 0; }
