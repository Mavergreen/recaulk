/* recaulk-materialize's command line. spec: .superpowers/specs/2026-11-24-recaulk-materialize-design.md
   "Command line" -- exit 0 complete, 1 refused (one stderr line), 2 usage. */
#include "materialize.h"
#include <stdlib.h>
#include <string.h>

#define USAGE "usage: recaulk-materialize --sdk DIR --out DIR (--profile NAME | --recipe ID...) " \
              "[--recipes FILE] [--profiles FILE] [--verify] | --print-stamp (--profile NAME | --recipe ID...) | --version"

static int usage(char *err, size_t errlen, const char *why, const char *what) {
    if (why)
        snprintf(err, errlen, "%s%s", why, what ? what : "");
    else
        snprintf(err, errlen, "%s", USAGE);
    return 2;
}

int mz_parse_args(int argc, char **argv, struct mz_args *a, char *err, size_t errlen) {
    memset(a, 0, sizeof *a);
    a->ids = calloc((size_t)argc + 1, sizeof *a->ids);
    if (!a->ids) mz_fail("out of memory");
    if (argc < 2) return usage(err, errlen, NULL, NULL);
    for (int i = 1; i < argc; i++) {
        const char *f = argv[i];
        const char **slot = NULL;
        if (!strcmp(f, "--version")) { a->version = 1; continue; }
        if (!strcmp(f, "--print-stamp")) { a->print_stamp = 1; continue; }
        if (!strcmp(f, "--verify")) { a->verify = 1; continue; }
        if (!strcmp(f, "--dry-run")) { a->dry_run = 1; continue; }
        if (!strcmp(f, "--sdk")) slot = &a->sdk;
        else if (!strcmp(f, "--out")) slot = &a->out;
        else if (!strcmp(f, "--profile")) slot = &a->profile;
        else if (!strcmp(f, "--recipes")) slot = &a->recipes;
        else if (!strcmp(f, "--profiles")) slot = &a->profiles;
        else if (!strcmp(f, "--recipe")) slot = &a->ids[a->nids];
        else return usage(err, errlen, "unknown option ", f);
        if (i + 1 >= argc) return usage(err, errlen, "missing value for ", f);
        if (*slot) return usage(err, errlen, "given twice: ", f);
        *slot = argv[++i];
        if (slot == &a->ids[a->nids]) a->nids++;
    }
    if (a->version) return 0;
    const char *paths[] = {a->sdk, a->out, a->recipes, a->profiles};
    for (size_t p = 0; p < sizeof paths / sizeof *paths; p++)
        if (paths[p] && paths[p][0] != '/') {
            snprintf(err, errlen, "'%s' is not an absolute path", paths[p]);
            return 2;
        }
    if (a->profile && a->nids) return usage(err, errlen, "--profile and --recipe are exclusive", NULL);
    if (!a->profile && !a->nids) return usage(err, errlen, NULL, NULL);
    if (a->print_stamp) return 0;
    if (!a->sdk || !a->out) return usage(err, errlen, NULL, NULL);
    return 0;
}

int main(int argc, char **argv) {
    struct mz_args a;
    char err[1024];
    if (mz_parse_args(argc, argv, &a, err, sizeof err)) {
        fprintf(stderr, "recaulk-materialize: %s\n", err);
        return 2;
    }
    if (a.version) {
        printf("recaulk-materialize %s\n", RECAULK_VERSION);
        return 0;
    }
    return 0;
}
