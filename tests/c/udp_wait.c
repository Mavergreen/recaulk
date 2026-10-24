#include <recaulk/udp_wait.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static struct sockaddr_in address;
static void add_read(int kq, int fd) {
    struct kevent e;
    EV_SET(&e, fd, EVFILT_READ, EV_ADD, 0, 0, (void *)42);
    assert(kevent(kq, &e, 1, NULL, 0, NULL) == 0);
}
static void send_packet(int fd, int bytes) {
    assert(sendto(fd, "x", bytes, 0, (void *)&address, sizeof address) == bytes);
}
static void *delayed_send(void *arg) {
    usleep(30000);
    send_packet(*(int *)arg, 0);
    return NULL;
}
static void interrupted(int signal) { (void)signal; }
static double now(void) {
    struct timeval t; gettimeofday(&t, NULL);
    return t.tv_sec + t.tv_usec / 1000000.0;
}
int main(void) {
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    assert(s >= 0);
    memset(&address, 0, sizeof address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    assert(bind(s, (void *)&address, sizeof address) == 0);
    socklen_t len = sizeof address;
    assert(getsockname(s, (void *)&address, &len) == 0);
    int kq = kqueue(); assert(kq >= 0); add_read(kq, s);
    struct recaulk_udp_reader reader = {s, (void *)42};
    struct recaulk_udp_wait_state state = {0, 0};
    struct kevent events[4];
    struct timespec zero = {0, 0}, bounded = {0, 20000000};
    char byte;

    send_packet(s, 0);
    assert(__recaulk_kevent_wait_udp(kq, events, 4, &bounded, &reader, 1, &state) == 1);
    assert(events[0].ident == (uintptr_t)s && events[0].filter == EVFILT_READ);
    assert(events[0].data == 0 && events[0].udata == (void *)42);
    assert(recv(s, &byte, 1, 0) == 0);
    assert(__recaulk_kevent_wait_udp(kq, events, 4, &zero, &reader, 1, &state) == 0);
    double start = now();
    assert(__recaulk_kevent_wait_udp(kq, events, 4, &bounded, &reader, 1, &state) == 0);
    assert(now() - start >= 0.01); /* It really waited; not a spurious wakeup. */

    pthread_t sender;
    assert(pthread_create(&sender, NULL, delayed_send, &s) == 0);
    assert(__recaulk_kevent_wait_udp(kq, events, 4, NULL, &reader, 1, &state) == 1);
    assert(pthread_join(sender, NULL) == 0);
    assert(recv(s, &byte, 1, 0) == 0);

    send_packet(s, 1);
    assert(__recaulk_kevent_wait_udp(kq, events, 4, &bounded, &reader, 1, &state) == 1);
    assert(events[0].ident == (uintptr_t)s);
    assert(recv(s, &byte, 1, 0) == 1 && byte == 'x');

    struct kevent timer;
    EV_SET(&timer, 123456, EVFILT_TIMER, EV_ADD | EV_ONESHOT, 0, 10, NULL);
    assert(kevent(kq, &timer, 1, NULL, 0, NULL) == 0);
    assert(__recaulk_kevent_wait_udp(kq, events, 4, NULL, &reader, 1, &state) == 1);
    assert(events[0].filter == EVFILT_TIMER);

    int pipefd[2]; assert(pipe(pipefd) == 0); add_read(kq, pipefd[0]);
    assert(write(pipefd[1], "x", 1) == 1); send_packet(s, 0);
    fd_set pending; FD_ZERO(&pending); FD_SET(s, &pending);
    struct timeval arrival = {1, 0};
    assert(select(s + 1, &pending, NULL, NULL, &arrival) == 1);
    int native = 0, udp = 0;
    for (int i = 0; i < 6; i++) {
        assert(__recaulk_kevent_wait_udp(kq, events, 1, &zero, &reader, 1, &state) == 1);
        native += events[0].ident == (uintptr_t)pipefd[0];
        udp += events[0].ident == (uintptr_t)s;
    }
    assert(native && udp);
    assert(read(pipefd[0], &byte, 1) == 1); assert(recv(s, &byte, 1, 0) == 0);
    close(pipefd[0]); close(pipefd[1]);

    int alias = dup(s); assert(alias >= 0); add_read(kq, alias);
    struct recaulk_udp_reader pair[2] = {{s, (void *)42}, {alias, (void *)44}};
    send_packet(s, 0);
    assert(__recaulk_kevent_wait_udp(kq, events, 1, &bounded, pair, 2, &state) == 1);
    uintptr_t first = events[0].ident;
    assert(__recaulk_kevent_wait_udp(kq, events, 1, &zero, pair, 2, &state) == 1);
    assert(events[0].ident != first);
    assert(recv(s, &byte, 1, 0) == 0); close(alias);

    struct sigaction action;
    memset(&action, 0, sizeof action); action.sa_handler = interrupted;
    sigemptyset(&action.sa_mask); assert(sigaction(SIGALRM, &action, NULL) == 0);
    ualarm(20000, 0); errno = 0;
    assert(__recaulk_kevent_wait_udp(kq, events, 4, NULL, &reader, 1, &state) == -1);
    assert(errno == EINTR);

    struct rlimit limit; assert(getrlimit(RLIMIT_NOFILE, &limit) == 0);
    if (limit.rlim_cur < FD_SETSIZE + 32) {
        limit.rlim_cur = FD_SETSIZE + 32;
        assert(setrlimit(RLIMIT_NOFILE, &limit) == 0);
    }
    struct kevent remove_original;
    EV_SET(&remove_original, s, EVFILT_READ, EV_DELETE, 0, 0, NULL);
    assert(kevent(kq, &remove_original, 1, NULL, 0, NULL) == 0);
    int high = fcntl(s, F_DUPFD, FD_SETSIZE + 10); assert(high > FD_SETSIZE);
    struct recaulk_udp_reader high_reader = {high, (void *)43};
    add_read(kq, high); send_packet(s, 0);
    assert(__recaulk_kevent_wait_udp(kq, events, 4, &bounded, &high_reader, 1, &state) == 1);
    assert(events[0].ident == (uintptr_t)high);
    assert(recv(high, &byte, 1, 0) == 0); close(high);
    assert(__recaulk_kevent_wait_udp(kq, events, 4, &zero, NULL, 0, NULL) == 0);
    errno = 0;
    assert(__recaulk_kevent_wait_udp(kq, events, 0, &zero, &reader, 1, &state) == -1);
    assert(errno == EINVAL);
    close(s); close(kq);
    puts("UDP wait: empty/nonempty, delayed, timer, fairness, EINTR, high fd passed");
}
