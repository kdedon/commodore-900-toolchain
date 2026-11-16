extern printf();
int g;
s1(x) int x; { switch (x) { case 1: return 10; case 2: return 20; case 3: return 30; } return -1; }
s2(x) int x; { switch (x) { case 0: return 5; case 4: return 6; case 20: return 7; case 21: return 8; case 37: return 9; default: return 11; } }
s3(x) int x; { register int y = x; switch (y) { case 1: y += 3; break; case 5: y *= 2; break; case 6: y -= 9; break; } return y; }
s4(x) int x; { switch (x) { case -3: return 1; case -2: return 2; case 10: return 3; case 11: return 4; case 30000: return 5; } return 0; }
s5(x) int x; { int r = 0; switch (x & 63) { case 1: r++; case 2: r++; case 9: r++; break; case 15: r = 7; } return r + x; }
s6(x) int x; { if (x == 3) return 1; if (x == 5) return 2; if (x == 6) return 3; return x; }
s7(c) char c; { switch (c) { case 'a': return 1; case 'b': return 2; case 'e': return 3; } return 0; }
s8(x) int x; { g = x; switch (g) { case 1: return g; case 2: return g + 1; case 3: return 4; } return g * 2; }
s9(x) long x; { switch ((int)x) { case 1: return 1; case 2: return 2; case 3: return 3; } return 9; }
main() { int i; for (i = -5; i < 45; i++) printf("%d %d %d %d %d %d %d %d %d %d\n", i, s1(i), s2(i), s3(i), s4(i), s5(i), s6(i), s7(i + 90), s8(i), s9((long)i));
 printf("%d %d %d\n", s4(30000), s4(-3), s2(37)); return 0; }
