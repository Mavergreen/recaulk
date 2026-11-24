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

/* sha256.c: FIPS 180-4 */
void mz_sha256(const void *buf, size_t n, char hex[65]);
int mz_sha256_file(const char *path, char hex[65]);

/* json.c: a DOM; strings are decoded bytes (no NUL inside), objects keep their key order */
enum mz_json_type { MZ_NULL, MZ_BOOL, MZ_NUM, MZ_STR, MZ_ARR, MZ_OBJ };
struct mz_json {
    enum mz_json_type t;
    char *s;           /* MZ_STR: NUL-terminated copy */
    size_t slen;
    double n;          /* MZ_NUM */
    int b;             /* MZ_BOOL */
    struct mz_json **v; /* MZ_ARR elements, MZ_OBJ values */
    char **k;           /* MZ_OBJ keys */
    size_t len;
};
struct mz_json *mz_json_parse(const char *buf, size_t n, char *err, size_t errlen);
const struct mz_json *mz_json_get(const struct mz_json *obj, const char *key);
void mz_json_write_string(FILE *f, const char *s, size_t n);

/* util.c */
void *mz_xmalloc(size_t n);
char *mz_xstrdup(const char *s);
int mz_read_file(const char *path, char **buf, size_t *n);

#endif
