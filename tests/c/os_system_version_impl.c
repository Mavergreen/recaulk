#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <os/system_version.h>

int __recaulk_impl_os_system_version_get_current_version(struct os_system_version_s *);
extern int (*__recaulk_os_system_version_read)(char *buf, size_t cap, size_t *len);

#define THREADS 32
#define ROUNDS 200
#define UNTOUCHED 0xdeadbeefu

static int bad;
static const char *feed;
static int feed_error;
static long reads;
static char fixture[8192];

static int fed(char *buf, size_t cap, size_t *len) {
  size_t n;
  __atomic_add_fetch(&reads, 1, __ATOMIC_SEQ_CST);
  if (feed_error) return feed_error;
  n = strlen(feed);
  if (n > cap) n = cap;
  memcpy(buf, feed, n);
  *len = n;
  return 0;
}

static void expect(const char *what, const char *content, int want_rc, unsigned a, unsigned b, unsigned c) {
  struct os_system_version_s v = {UNTOUCHED, UNTOUCHED, UNTOUCHED};
  int rc;
  feed = content;
  feed_error = 0;
  rc = __recaulk_impl_os_system_version_get_current_version(&v);
  if (rc != want_rc) {
    printf("%s: returned %d, want %d\n", what, rc, want_rc);
    bad = 1;
  }
  if (v.major != a || v.minor != b || v.patch != c) {
    printf("%s: reported %u.%u.%u, want %u.%u.%u\n", what, v.major, v.minor, v.patch, a, b, c);
    bad = 1;
  }
}

static const char *plist(const char *value) {
  static char buf[512];
  snprintf(buf, sizeof buf,
           "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\">\n<dict>\n"
           "\t<key>ProductName</key>\n\t<string>Mac OS X</string>\n"
           "\t<key>ProductVersion</key>\n%s\n</dict>\n</plist>\n", value);
  return buf;
}

static void bad_input(const char *what, const char *value) {
  expect(what, plist(value), EINVAL, UNTOUCHED, UNTOUCHED, UNTOUCHED);
}

static pthread_mutex_t gate = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t open_gate = PTHREAD_COND_INITIALIZER;
static int waiting;
static int use_real;

static void *racer(void *arg) {
  int i;
  (void)arg;
  pthread_mutex_lock(&gate);
  if (++waiting == THREADS) pthread_cond_broadcast(&open_gate);
  while (waiting < THREADS) pthread_cond_wait(&open_gate, &gate);
  pthread_mutex_unlock(&gate);
  for (i = 0; i < ROUNDS; i++) {
    struct os_system_version_s v = {0, 0, 0};
    int rc = __recaulk_impl_os_system_version_get_current_version(&v);
    if (rc != 0 || (!use_real && (v.major != 10 || v.minor != 9 || v.patch != 5))) {
      __atomic_store_n(&bad, 1, __ATOMIC_SEQ_CST);
      printf("concurrent call %d: returned %d, reported %u.%u.%u\n", i, rc, v.major, v.minor, v.patch);
      return NULL;
    }
  }
  return NULL;
}

static void race(int real) {
  pthread_t t[THREADS];
  int i;
  int (*saved)(char *, size_t, size_t *) = __recaulk_os_system_version_read;
  use_real = real;
  waiting = 0;
  if (!real) {
    feed = fixture;
    feed_error = 0;
    reads = 0;
    __recaulk_os_system_version_read = fed;
  }
  for (i = 0; i < THREADS; i++)
    if (pthread_create(&t[i], NULL, racer, NULL) != 0) {
      printf("pthread_create failed\n");
      exit(1);
    }
  for (i = 0; i < THREADS; i++) pthread_join(t[i], NULL);
  if (!real && reads != (long)THREADS * ROUNDS) {
    printf("%d threads x %d calls read SystemVersion.plist %ld times: every call must read it, with nothing cached\n",
           THREADS, ROUNDS, reads);
    bad = 1;
  }
  __recaulk_os_system_version_read = saved;
}

int main(int argc, char **argv) {
  FILE *f;
  size_t n;
  struct os_system_version_s v = {0, 0, 0};
  int rc;
  int (*real)(char *, size_t, size_t *) = __recaulk_os_system_version_read;
  alarm(60);
  if (argc != 3) {
    printf("usage: os_system_version_impl FIXTURE EXPECTED|-\n");
    return 2;
  }
  f = fopen(argv[1], "r");
  if (!f) {
    printf("cannot open %s\n", argv[1]);
    return 2;
  }
  n = fread(fixture, 1, sizeof fixture - 1, f);
  fclose(f);
  fixture[n] = 0;

  errno = 12345;
  rc = __recaulk_impl_os_system_version_get_current_version(&v);
  if (rc != 0) { printf("the real SystemVersion.plist: returned %d\n", rc); bad = 1; }
  if (errno != 12345) { printf("a successful call changed errno to %d\n", errno); bad = 1; }
  printf("real: %u.%u.%u\n", v.major, v.minor, v.patch);
  if (strcmp(argv[2], "-") != 0) {
    char got[64];
    snprintf(got, sizeof got, "%u.%u.%u", v.major, v.minor, v.patch);
    if (strcmp(got, argv[2]) != 0) { printf("the real SystemVersion.plist reported %s, want %s\n", got, argv[2]); bad = 1; }
  } else if (v.major < 10) {
    printf("the real SystemVersion.plist reported major %u\n", v.major);
    bad = 1;
  }

  __recaulk_os_system_version_read = fed;
  expect("the 10.9.5 SystemVersion.plist", fixture, 0, 10, 9, 5);
  expect("two components", plist("\t<string>10.9</string>"), 0, 10, 9, 0);
  expect("an 11.3 release", plist("<string>11.3.1</string>"), 0, 11, 3, 1);
  expect("whitespace around the string", plist("\n\t \r\n<string>10.12.6</string>"), 0, 10, 12, 6);
  expect("no cache: a later call reads again", plist("<string>27.0.1</string>"), 0, 27, 0, 1);

  feed_error = ENOENT;
  {
    struct os_system_version_s u = {UNTOUCHED, UNTOUCHED, UNTOUCHED};
    rc = __recaulk_impl_os_system_version_get_current_version(&u);
    if (rc != ENOENT) { printf("a missing SystemVersion.plist: returned %d, want ENOENT\n", rc); bad = 1; }
    if (u.major != UNTOUCHED || u.minor != UNTOUCHED || u.patch != UNTOUCHED) {
      printf("a missing SystemVersion.plist: the version was written to\n");
      bad = 1;
    }
  }
  feed_error = 0;

  expect("an empty file", "", EINVAL, UNTOUCHED, UNTOUCHED, UNTOUCHED);
  expect("no ProductVersion key", "<plist><dict><key>ProductName</key><string>Mac OS X</string></dict></plist>",
         EINVAL, UNTOUCHED, UNTOUCHED, UNTOUCHED);
  expect("a truncated file", "<plist><dict><key>ProductVersion</key><string>10.9", EINVAL, UNTOUCHED, UNTOUCHED, UNTOUCHED);
  expect("ProductUserVisibleVersion only",
         "<plist><dict><key>ProductUserVisibleVersion</key><string>10.9.5</string></dict></plist>",
         EINVAL, UNTOUCHED, UNTOUCHED, UNTOUCHED);
  bad_input("an integer value", "<integer>10</integer>");
  bad_input("an empty string", "<string></string>");
  bad_input("one component", "<string>10</string>");
  bad_input("a trailing dot", "<string>10.</string>");
  bad_input("an empty component", "<string>10..9</string>");
  bad_input("four components", "<string>10.9.5.1</string>");
  bad_input("a letter", "<string>10.9b</string>");
  bad_input("a sign", "<string>-10.9</string>");
  bad_input("a component past UINT_MAX", "<string>10.4294967296</string>");
  bad_input("an unterminated string", "<string>10.9.5");

  race(0);
  __recaulk_os_system_version_read = real;
  race(1);

  if (bad) return 1;
  printf("os_system_version_impl: all passed\n");
  return 0;
}
