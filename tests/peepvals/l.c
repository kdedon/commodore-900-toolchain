extern printf();
long g;
long f0() { return 0L; }
long f1() { return 15L; }
long f2() { return 0x000F000FL; }
long f3() { return 0x00010000L; }
long f4() { return 16L; }
long f5() { return -1L; }
long f6(a) long a; { return a + 3L; }
h(a, b) long a, b; { printf("%ld %ld\n", a, b); }
main() { long l; h(f0(), f1()); h(f2(), f3()); h(f4(), f5()); h(f6(5L), 7L); g = 9L; l = g; h(l, (long)12); return 0; }
