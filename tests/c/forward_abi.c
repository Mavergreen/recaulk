#include <dlfcn.h>
#include <stdio.h>

int mgfwd_varargs(const char *fmt, ...);
double mgfwd_float(double a, float b, int c, double d, double e, double f, double g, double h,
                   double i, double j);
int mgfwd_regs_probe(void);
extern void *__recaulk_slot_mgfwd_varargs;

/* platform: the System V x86_64 ABI lets a callee overwrite every argument register; this stands
   in for a dlsym that does, so a trampoline that fails to restore one is caught */
void *mgfwd_clobbering_dlsym(void *handle, const char *name) {
  void *p = dlsym(handle, name);
  __asm__ volatile(
      "pcmpeqd %%xmm0, %%xmm0\n\tpcmpeqd %%xmm1, %%xmm1\n\tpcmpeqd %%xmm2, %%xmm2\n\t"
      "pcmpeqd %%xmm3, %%xmm3\n\tpcmpeqd %%xmm4, %%xmm4\n\tpcmpeqd %%xmm5, %%xmm5\n\t"
      "pcmpeqd %%xmm6, %%xmm6\n\tpcmpeqd %%xmm7, %%xmm7\n\tpcmpeqd %%xmm8, %%xmm8\n\t"
      "pcmpeqd %%xmm9, %%xmm9\n\tpcmpeqd %%xmm10, %%xmm10\n\tpcmpeqd %%xmm11, %%xmm11\n\t"
      "pcmpeqd %%xmm12, %%xmm12\n\tpcmpeqd %%xmm13, %%xmm13\n\tpcmpeqd %%xmm14, %%xmm14\n\t"
      "pcmpeqd %%xmm15, %%xmm15\n\t"
      "movq $-1, %%rdi\n\tmovq $-1, %%rsi\n\tmovq $-1, %%rdx\n\tmovq $-1, %%rcx\n\t"
      "movq $-1, %%r8\n\tmovq $-1, %%r9\n\tmovq $-1, %%r10\n\tmovq $-1, %%r11"
      ::: "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7",
          "xmm8", "xmm9", "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "xmm15",
          "rdi", "rsi", "rdx", "rcx", "r8", "r9", "r10", "r11");
  return p;
}

/* platform: keeps r10, r11 and all 128 bits of xmm8 and xmm15 live across a call to the forwarded
   mgfwd_nop, as a caller relying on more than the C ABI may; returns a bit per register lost */
__asm__(".text\n"
        ".globl _mgfwd_regs_probe\n"
        "_mgfwd_regs_probe:\n"
        "  pushq %rbp\n"
        "  movq %rsp, %rbp\n"
        "  movabsq $0x1010101010101010, %r10\n"
        "  movabsq $0x1111111111111111, %r11\n"
        "  movabsq $0x0808080808080808, %rax\n"
        "  movq %rax, %xmm8\n"
        "  punpcklqdq %xmm8, %xmm8\n"
        "  movabsq $0x1515151515151515, %rax\n"
        "  movq %rax, %xmm15\n"
        "  punpcklqdq %xmm15, %xmm15\n"
        "  callq _mgfwd_nop\n"
        "  xorl %eax, %eax\n"
        "  movabsq $0x1010101010101010, %rcx\n"
        "  cmpq %rcx, %r10\n"
        "  je 1f\n"
        "  orl $1, %eax\n"
        "1:\n"
        "  movabsq $0x1111111111111111, %rcx\n"
        "  cmpq %rcx, %r11\n"
        "  je 2f\n"
        "  orl $2, %eax\n"
        "2:\n"
        "  movabsq $0x0808080808080808, %rcx\n"
        "  movq %rcx, %xmm0\n"
        "  punpcklqdq %xmm0, %xmm0\n"
        "  pcmpeqb %xmm8, %xmm0\n"
        "  pmovmskb %xmm0, %edx\n"
        "  cmpl $0xffff, %edx\n"
        "  je 3f\n"
        "  orl $4, %eax\n"
        "3:\n"
        "  movabsq $0x1515151515151515, %rcx\n"
        "  movq %rcx, %xmm0\n"
        "  punpcklqdq %xmm0, %xmm0\n"
        "  pcmpeqb %xmm15, %xmm0\n"
        "  pmovmskb %xmm0, %edx\n"
        "  cmpl $0xffff, %edx\n"
        "  je 4f\n"
        "  orl $8, %eax\n"
        "4:\n"
        "  popq %rbp\n"
        "  ret\n");

int main(void) {
  int k;
  for (k = 0; k < 2; k++)
    printf("varargs %d\n", mgfwd_varargs("abcde", 1, 2, 3, 4, 5));
  __recaulk_slot_mgfwd_varargs = 0;
  for (k = 0; k < 2; k++)
    printf("varargs-fp %d\n", mgfwd_varargs("ff", 3.0, 4.0));
  for (k = 0; k < 2; k++)
    printf("float %g\n", mgfwd_float(1.5, 2.25f, 3, 4.5, 5.5, 6.5, 7.5, 8.5, 9.5, 10.5));
  for (k = 0; k < 2; k++)
    printf("regs %d\n", mgfwd_regs_probe());
  return 0;
}
