#include <stddef.h>
#include <stdio.h>
#include <unistd.h>

int __recaulk_impl_CCRandomGenerateBytes(void *, size_t);

int main(void) {
  char buf[16];
  int bad = 0;
  alarm(30);
  if (__recaulk_impl_CCRandomGenerateBytes(buf, 0) != 0) { printf("(buf, 0) did not return 0\n"); bad = 1; }
  if (__recaulk_impl_CCRandomGenerateBytes(NULL, 0) != 0) { printf("(NULL, 0) did not return 0\n"); bad = 1; }
  if (__recaulk_impl_CCRandomGenerateBytes(NULL, 16) != -4300) { printf("(NULL, 16) did not return -4300\n"); bad = 1; }
  if (__recaulk_impl_CCRandomGenerateBytes(buf, 16) != 0) { printf("(buf, 16) did not return 0\n"); bad = 1; }
  if (bad) return 1;
  printf("ccrandom ok\n");
  return 0;
}
