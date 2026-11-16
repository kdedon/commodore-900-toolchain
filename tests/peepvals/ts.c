extern printf();
int g; char gc; long gl; int a[4];
f1(x, y) int x, y; { int t; t = x & y; g = t; if (g) return 1; return 2; }
f2(x, y) int x, y; { g = x + y; if (g < 0) return 3; if (g == 0) return 4; return 5; }
f3(x) int x; { gc = x; if (gc) return 6; return 7; }
f4(x) int x; { gl = x; if (gl) return 8; return 9; }
f5(x, y) int x, y; { register int i = x; a[i & 3] = y - x; if (a[i & 3] > 0) return 10; return 11; }
f6(x) int x; { int l; l = x - 5; g = l; while (g) { g = g - 1; if (g & 1) l++; } return l; }
f7(x) int x; { char c; c = x; gc = c; if (gc < 0) return 12; return 13; }
f8(x) long x; { gl = x + 1; if (gl < 0) return 14; return 15; }
main() { int i, v[] = { -32768, -5, -1, 0, 1, 2, 3, 127, 128, 255, 256, 32767 };
 for (i = 0; i < 12; i++) printf("%d %d %d %d %d %d %d %d %d\n", f1(v[i], 6), f2(v[i], 1), f3(v[i]), f4(v[i]), f5(v[i], 3), f6(v[i] & 15), f7(v[i]), f8((long)v[i] * 65536L), v[i]);
 return 0; }
