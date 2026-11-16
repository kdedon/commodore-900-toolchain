extern printf();
int v[] = { -32768, -32767, -1025, -1024, -1023, -17, -16, -15, -9, -8, -7, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 1023, 1024, 1025, 32767, 32766, -32766, 12345, -12345 };
int g;
a(x) int x; { return x % 2 == 0; }
b(x) int x; { return x % 4 != 0; }
c(x) int x; { if (x % 8) return 1; return 0; }
d(x) int x; { return !(x % 16); }
e(x) int x; { g = x; return g % 1024 == 0 ? 5 : 6; }
f(x) int x; { register int y = x; while (y % 32 == 0 && y) y /= 32; return y; }
h(x) int x; { return (x % 16384) == 0; }
i(x) int x; { return x % 8 == 3; }
main() { int n; for (n = 0; n < sizeof v / sizeof v[0]; n++) printf("%d %d %d %d %d %d %d %d %d\n", v[n], a(v[n]), b(v[n]), c(v[n]), d(v[n]), e(v[n]), f(v[n]), h(v[n]), i(v[n])); return 0; }
