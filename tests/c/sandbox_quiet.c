/* spec: tests/sandbox-quiet.sh -- inside a (deny default) sandbox, as sshd-auth runs, one Recaulk entry point
 * per run (or the denied control), then prints its pid. sandbox_init is deprecated but is what OpenSSH's
 * sandbox-darwin.c calls. */
#include <sandbox.h>
#include <stdio.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <time.h>
#include <unistd.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

int main(int argc, char **argv) {
    char *err = NULL;
    if (argc != 2) return 2;
    if (sandbox_init("(version 1) (deny default)", 0, &err) != 0) { fprintf(stderr, "sandbox_init: %s\n", err); return 2; }
    const char *c = argv[1];
    int r = 0;
    if (strcmp(c, "pselect") == 0) {
        struct timespec ts = {0, 1000};
        r = pselect(0, NULL, NULL, NULL, &ts, NULL);
    } else if (strcmp(c, "forwarded") == 0) {
        struct timespec ts;
        r = clock_gettime(CLOCK_REALTIME, &ts);
    } else if (strcmp(c, "available") == 0) {
        if (__builtin_available(macOS 10.12, *)) r = 1;
    } else if (strcmp(c, "socketclose") == 0) {
        int sv[2];
        r = socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
        if (r == 0) r = close(sv[0]) | close(sv[1]);
        usleep(20000); /* the helper Recaulk's close starts has started */
    } else if (strcmp(c, "denied") == 0) {
        int mib[2] = {CTL_KERN, KERN_OSRELEASE};
        char rel[32];
        size_t n = sizeof rel;
        r = sysctl(mib, 2, rel, &n, 0, 0);
    } else if (strcmp(c, "none") != 0) {
        return 2;
    }
    printf("%d %d\n", (int)getpid(), r);
    return 0;
}
