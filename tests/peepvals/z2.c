extern printf();
int v[] = { -32768, -32767, -1025, -1024, -1023, -17, -16, -15, -9, -8, -7, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 7, 8, 9, 11, 15, 16, 17, 19, 1023, 1024, 1025, 32767, 32766, -32766, 12345, -12345 };
a(x) int x; { return x % 8 == 3; }
b(x) int x; { return x % 8 != 7; }
c(x) int x; { return x % 4 == 1; }
d(x) int x; { if (x % 16 == 15) return 1; return 0; }
e(x) int x; { return x % 8 == -3; }
f(x) int x; { return x % 2 == 1; }
main() { int n; for (n = 0; n < sizeof v / sizeof v[0]; n++) printf("%d %d %d %d %d %d %d\n", v[n], a(v[n]), b(v[n]), c(v[n]), d(v[n]), e(v[n]), f(v[n])); return 0; }
