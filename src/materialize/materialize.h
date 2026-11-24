/* recaulk-materialize: applies Recaulk's SDK recipes to a user's own SDK.
   spec: .superpowers/specs/2026-11-24-recaulk-materialize-design.md */
#ifndef RECAULK_MATERIALIZE_H
#define RECAULK_MATERIALIZE_H
#include <stddef.h>
#include <stdio.h>

#ifndef RECAULK_VERSION
#define RECAULK_VERSION "dev"
#endif
#define MZ_FORMAT 1

struct mz_args {
    const char *sdk, *out, *profile, *recipes, *profiles;
    const char **ids;
    int nids;
    int print_stamp, verify, version, dry_run;
};

int mz_parse_args(int argc, char **argv, struct mz_args *a, char *err, size_t errlen);
void mz_fail(const char *fmt, ...) __attribute__((noreturn, format(printf, 1, 2)));
#endif
