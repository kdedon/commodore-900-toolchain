extern printf();
struct s { char a, b; int c; } q = { -5, 7, 300 }, *qp = &q;
int g = 1234; char gc = -2; unsigned char uc = 200;
h(a, b, c, d) int a, b, c, d; { printf("%d %d %d %d\n", a, b, c, d); }
f1() { int t = g; h(t, qp->a, qp->b, qp->c); }
f2() { h(g, gc, uc, g + 1); }
f3() { register struct s *p = qp; h(p->c, p->a, p->b, p->c); }
main() { f1(); f2(); f3(); return 0; }
