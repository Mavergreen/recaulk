/* Catch missing exports, permissive parsing, reversed range handling, and errno loss. */
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Also link against the pre-backfill library to demonstrate the missing API. */
extern long long strtonum(const char *, long long, long long, const char **);

int main(void) {
    const struct {
        const char *input;
        long long min, max, want;
        const char *error;
        int errnum;
    } cases[] = {
        {"0", 0, 0, 0, NULL, EDOM},
        {"  +42", -100, 100, 42, NULL, EDOM},
        {"010", 0, 100, 10, NULL, EDOM},
        {"-9223372036854775808", LLONG_MIN, LLONG_MAX, LLONG_MIN, NULL, EDOM},
        {"9223372036854775807", LLONG_MIN, LLONG_MAX, LLONG_MAX, NULL, EDOM},
        {"", 0, 10, 0, "invalid", EINVAL},
        {" ", 0, 10, 0, "invalid", EINVAL},
        {"+", 0, 10, 0, "invalid", EINVAL},
        {"1 ", 0, 10, 0, "invalid", EINVAL},
        {"1x", 0, 10, 0, "invalid", EINVAL},
        {"0x10", 0, 100, 0, "invalid", EINVAL},
        {"5", 10, 0, 0, "invalid", EINVAL},
        {"-1", 0, 10, 0, "too small", ERANGE},
        {"11", 0, 10, 0, "too large", ERANGE},
        {"-9223372036854775809", LLONG_MIN, LLONG_MAX, 0, "too small", ERANGE},
        {"9223372036854775808", LLONG_MIN, LLONG_MAX, 0, "too large", ERANGE},
        {"999999999999999999999x", LLONG_MIN, LLONG_MAX, 0, "invalid", EINVAL}
    };
    unsigned i;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        const char *error = "not cleared";
        long long got;
        errno = EDOM;
        got = strtonum(cases[i].input, cases[i].min, cases[i].max, &error);
        if (got != cases[i].want || errno != cases[i].errnum ||
            (cases[i].error ? (!error || strcmp(error, cases[i].error)) : error != NULL)) {
            fprintf(stderr, "case %u (%s): got %lld, errno %d, error %s\n",
                i, cases[i].input, got, errno, error ? error : "NULL");
            return 1;
        }
    }
    errno = EDOM;
    if (strtonum("7", 0, 10, NULL) != 7 || errno != EDOM) return 2;
    if (strtonum("bad", 0, 10, NULL) != 0 || errno != EINVAL) return 3;
    puts("strtonum: parsing, bounds, error strings, and errno passed");
    return 0;
}
