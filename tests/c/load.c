#include <os/lock.h>
#include <stdio.h>
#include <time.h>
#include <sys/random.h>

int main(void) {
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 1;
  os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
  os_unfair_lock_lock(&lock);
  os_unfair_lock_unlock(&lock);
  unsigned char buf[16];
  if (getentropy(buf, sizeof buf) != 0) return 2;
  puts("recaulk-load ok");
  return 0;
}
