extern printf();
int g, h; long gl, hl; int *gp;
f1(x) int x; { int a, b; a = x * 3; g = a; b = g + 1; h = g; return b + h; }
long f2(x) long x; { long l; gl = x + 5; l = gl; hl = gl; return l + hl; }
f3(x) int x; { int a[2]; a[0] = x; g = a[0]; a[1] = a[0] + g; return a[1]; }
f4(x) int x; { long l; l = x; gl = l; h = gl; return h + (int)l; }
f5(x) int x; { g = x; gp = &g; *gp = 7; return g + x; }
main() { int i, v[] = { -32768, -5, 0, 3, 1000, 32767 }; for (i = 0; i < 6; i++) printf("%d %ld %d %d %d\n", f1(v[i]), f2((long)v[i] * 3), f3(v[i]), f4(v[i]), f5(v[i])); return 0; }
