extern printf();
int g; char gc; int *gp; int a[3];
f1(x) int x; { g = x; x = 0; if (g < 0) x |= 1; if (g >= 0) x |= 2; if (g == 0) x |= 4; if (g > 0) x |= 8; if (g <= 0) x |= 16; return x; }
f2(x) int x; { gc = x; x = 0; if (gc < 0) x |= 1; if (gc >= 0) x |= 2; if (gc == 0) x |= 4; if (gc) x |= 8; return x; }
f3(x) int x; { int y, r = 0; a[1] = x; gp = &a[1]; y = 5; if (*gp < 0) r |= 1; if (*gp >= 0) r |= 2; while (*gp < 0) { (*gp)++; r += 16; if (r > 200) break; } return r + y; }
f4(x) int x; { register int i; int l = x; for (i = 0; l < 0; i++) l += 7; if (l >= 0) i += 100; return i; }
main() { int i, v[] = { -32768, -300, -129, -128, -2, -1, 0, 1, 2, 127, 128, 255, 256, 32767 };
 for (i = 0; i < 14; i++) printf("%d %d %d %d %d\n", v[i], f1(v[i]), f2(v[i]), f3(v[i] % 9), f4(v[i] / 64)); return 0; }
