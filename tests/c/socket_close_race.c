/* spec: tests/socket-close-race.sh -- a reader thread enters read (tcp), accept or recv (udp) on a socket while
 * the main thread dup2s /dev/null over it, or closes it, at once, ITERATIONS times. A watchdog thread exits 3,
 * naming the iteration, if one close or dup2 is still blocked after 2 s, since a stuck one may never return.
 *   usage: socket_close_race tcp|accept|udp dup2|close ITERATIONS */
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static int fd, accepting, udp;
static volatile int closing, entering, iteration;

static double now(void) { struct timeval t; gettimeofday(&t, 0); return t.tv_sec + t.tv_usec / 1e6; }

static void *reader(void *unused) {
    char b[16];
    (void)unused;
    entering = 1;
    if (accepting) accept(fd, 0, 0);
    else if (udp) recv(fd, b, sizeof b, 0);
    else read(fd, b, sizeof b);
    return 0;
}

static void *watchdog(void *unused) {
    (void)unused;
    for (;;) {
        double s = now();
        while (closing) {
            if (now() - s > 2) { printf("FAIL: blocked >2 s closing at iteration %d\n", iteration); fflush(stdout); _exit(3); }
            usleep(10000);
        }
        usleep(1000);
    }
}

int main(int argc, char **argv) {
    if (argc != 4) return 2;
    int use_close = !strcmp(argv[2], "close"), n = atoi(argv[3]), devnull = open("/dev/null", O_RDONLY);
    accepting = !strcmp(argv[1], "accept");
    udp = !strcmp(argv[1], "udp");
    pthread_t w;
    pthread_create(&w, 0, watchdog, 0);
    for (int i = 1; i <= n; i++) {
        struct sockaddr_in sa;
        socklen_t sl = sizeof sa;
        int l = -1, c = -1;
        memset(&sa, 0, sizeof sa);
        sa.sin_family = AF_INET;
        sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        if (udp) {
            fd = socket(AF_INET, SOCK_DGRAM, 0);
            bind(fd, (void *)&sa, sizeof sa);
        } else {
            l = socket(AF_INET, SOCK_STREAM, 0);
            bind(l, (void *)&sa, sizeof sa);
            listen(l, 1);
            fd = l;
            if (!accepting) {
                getsockname(l, (void *)&sa, &sl);
                c = socket(AF_INET, SOCK_STREAM, 0);
                if (connect(c, (void *)&sa, sizeof sa) != 0) { perror("connect (test setup)"); return 4; }
                fd = accept(l, 0, 0);
            }
        }
        entering = 0;
        iteration = i;
        pthread_t r;
        pthread_create(&r, 0, reader, 0);
        while (!entering) ;
        closing = 1;
        if (use_close) close(fd);
        else dup2(devnull, fd);
        closing = 0;
        if (!use_close) close(fd);
        pthread_join(r, 0);
        if (c >= 0) {
            /* platform: an abortive close leaves no TIME_WAIT, so thousands of loopback connections do not
             * run out of ports */
            struct linger lg = {1, 0};
            setsockopt(c, SOL_SOCKET, SO_LINGER, &lg, sizeof lg);
            close(c);
        }
        if (l >= 0 && l != fd) close(l);
    }
    printf("ok %s %s: %d closes\n", argv[1], argv[2], n);
    return 0;
}
