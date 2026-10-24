#include <netdb.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>

static int check(const char *service) {
    struct addrinfo hints, *addresses = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_flags = AI_NUMERICSERV;
    hints.ai_socktype = SOCK_STREAM;
    int error = getaddrinfo("localhost", service, &hints, &addresses);
    if (error != 0 || addresses == NULL) {
        fprintf(stderr, "numeric service %s: %d\n", service ? service : "(null)", error);
        return 1;
    }
    int failed = 0;
    for (struct addrinfo *a = addresses; a; a = a->ai_next) {
        if (a->ai_family == AF_INET)
            failed |= ((struct sockaddr_in *)a->ai_addr)->sin_port != 0;
        else if (a->ai_family == AF_INET6)
            failed |= ((struct sockaddr_in6 *)a->ai_addr)->sin6_port != 0;
        else failed = 1;
    }
    freeaddrinfo(addresses);
    return failed;
}
int main(void) {
    if (check("0") || check(NULL)) return 1;
    struct addrinfo hints, *addresses = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_flags = AI_NUMERICSERV;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo("localhost", "http", &hints, &addresses) == 0) {
        freeaddrinfo(addresses);
        fputs("AI_NUMERICSERV accepted a named service\n", stderr);
        return 1;
    }
    puts("getaddrinfo numeric-zero: all passed");
    return 0;
}
