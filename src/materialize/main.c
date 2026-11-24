/* recaulk-materialize's command line. spec: .superpowers/specs/2026-11-24-recaulk-materialize-design.md
   "Command line" -- exit 0 complete, 1 refused (one stderr line), 2 usage. */
#include "materialize.h"
#include <libgen.h>
#include <limits.h>
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

static struct mz_json *load(const char *path, const char *what) {
    char *buf, err[256];
    size_t n;
    if (mz_read_file(path, &buf, &n)) mz_fail("cannot read the %s %s", what, path);
    struct mz_json *j = mz_json_parse(buf, n, err, sizeof err);
    if (!j) mz_fail("%s: %s", path, err);
    return j;
}

/* spec: the design's "Command line" -- the data installed beside the binary, ../share/sdk-metadata/ */
static const char *beside(const char *argv0, const char *name) {
    char self[PATH_MAX];
    if (!realpath(argv0, self)) mz_fail("cannot find this program's own path to look up %s; pass it", name);
    char *dir = mz_xstrdup(dirname(self));
    size_t n = strlen(dir) + strlen(name) + 32;
    char *p = mz_xmalloc(n);
    snprintf(p, n, "%s/../share/sdk-metadata/%s", dir, name);
    return p;
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
    struct mz_json *recipes = load(a.recipes ? a.recipes : beside(argv[0], "recipes.json"), "recipe file");
    struct mz_json *profiles = a.profile ? load(a.profiles ? a.profiles : beside(argv[0], "profiles.json"), "profile file") : NULL;
    const struct mz_json **sel;
    size_t nsel;
    char *ids;
    mz_select(recipes, profiles, &a, &sel, &nsel, &ids);
    char digest[65];
    mz_recipes_digest(sel, nsel, digest);
    if (a.print_stamp) {
        mz_print_identity(stdout, a.profile, ids, digest, NULL, NULL);
        fputs("}\n", stdout);
        return fflush(stdout) ? 1 : 0;
    }

    char sdk_real[PATH_MAX];
    if (!realpath(a.sdk, sdk_real)) mz_fail("--sdk '%s' does not exist", a.sdk);
    const struct mz_json *want = mz_json_get(recipes, "sdk");
    if (!want || want->t != MZ_STR) mz_fail("the recipe file names no sdk");
    char *base = mz_xstrdup(sdk_real), name[PATH_MAX];
    snprintf(name, sizeof name, "%s.sdk", want->s);
    if (strcmp(basename(base), name)) mz_fail("the recipes are for %s, but --sdk resolves to %s", name, sdk_real);

    if (!a.dry_run) mz_existing_out(&a, ids, digest, sdk_real); /* exits 0 on a matching tree */
    struct mz_header *hs;
    size_t nh;
    mz_apply(sdk_real, sel, nsel, &hs, &nh);
    if (a.dry_run) {
        for (size_t i = 0; i < nh; i++) {
            printf("== %s\n", hs[i].rel);
            fwrite(hs[i].text, 1, hs[i].len, stdout);
        }
        return 0;
    }
    mz_publish(&a, sdk_real, hs, nh, ids, digest);
    return 0;
}
