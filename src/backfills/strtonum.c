/*
 * strtonum -- bounded decimal conversion with the BSD error contract.
 * Custom backfill: not supplied by the pinned macports-legacy-support.
 * The generated forwarding layer prefers the native API on newer macOS.
 */
#include <errno.h>
#include <limits.h>
#include <stdlib.h>

long long strtonum(const char *text, long long min, long long max,
                  const char **errorp) {
    const char *error = NULL;
    int saved_errno = errno;
    int failure_errno = EINVAL;
    long long value = 0;
    char *end;

    if (min > max) {
        error = "invalid";
    } else {
        errno = 0;
        value = strtoll(text, &end, 10);
        if (text == end || *end != '\0') {
            error = "invalid";
        } else if ((errno == ERANGE && value == LLONG_MIN) || value < min) {
            error = "too small";
            failure_errno = ERANGE;
        } else if ((errno == ERANGE && value == LLONG_MAX) || value > max) {
            error = "too large";
            failure_errno = ERANGE;
        }
    }
    if (errorp) *errorp = error;
    errno = error ? failure_errno : saved_errno;
    return error ? 0 : value;
}
