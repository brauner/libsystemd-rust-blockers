/* The C side of the m68k layout check in run.sh, see README.md. */
struct S { unsigned char a; unsigned long long b; };
struct D { unsigned char a; double b; };
int a64 = _Alignof(unsigned long long);
int af = _Alignof(double);
int sS = sizeof(struct S);
int sD = sizeof(struct D);
