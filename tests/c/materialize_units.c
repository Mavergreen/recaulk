/* spec: README.md "Materializing an SDK view" "Left to the builder" -- our own SHA-256 and
   JSON reader, checked against FIPS 180-4's vectors and Recaulk's own recipes.json.
   usage: materialize_units RECIPES_JSON RECIPES_SHA256 */
#include "../../src/materialize/materialize.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int fails;
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); fails++; } } while (0)

static void sha(const char *what, const void *buf, size_t n, const char *want) {
    char hex[65];
    mz_sha256(buf, n, hex);
    CHECK(!strcmp(hex, want), "sha256(%s) = %s, want %s", what, hex, want);
}

static char *slurp(const char *path, size_t *n) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *b = malloc((size_t)len + 1);
    *n = fread(b, 1, (size_t)len, f);
    fclose(f);
    return b;
}

int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: materialize_units RECIPES_JSON RECIPES_SHA256\n"); return 2; }
    char err[256], hex[65];

    printf("== sha256_vectors\n");
    sha("\"\"", "", 0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    sha("\"abc\"", "abc", 3, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    sha("448 bits", "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56,
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
    char *million = malloc(1000000);
    memset(million, 'a', 1000000);
    sha("a x 1000000", million, 1000000, "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");

    printf("== sha256_file\n");
    CHECK(mz_sha256_file(argv[1], hex) == 0 && !strcmp(hex, argv[2]), "sha256 of %s = %s, want %s", argv[1], hex, argv[2]);
    CHECK(mz_sha256_file("/nonexistent/recaulk", hex) != 0, "a missing file hashed");

    printf("== json_strings\n");
    const char *doc = "{\"a\":[1,\"x\\\"\\\\\\n\\u00e9\\ud83d\\ude00\"],\"b\":{}}";
    struct mz_json *j = mz_json_parse(doc, strlen(doc), err, sizeof err);
    CHECK(j != NULL, "parse failed: %s", err);
    if (j) {
        const struct mz_json *a = mz_json_get(j, "a");
        const char want[] = "x\"\\\n\xc3\xa9\xf0\x9f\x98\x80";
        CHECK(a && a->t == MZ_ARR && a->len == 2, "a is not a 2-array");
        CHECK(a && a->len == 2 && a->v[1]->t == MZ_STR && a->v[1]->slen == sizeof want - 1 &&
              !memcmp(a->v[1]->s, want, sizeof want - 1), "the escaped string decoded wrongly");
        CHECK(a && a->v[0]->t == MZ_NUM && a->v[0]->n == 1, "a[0] is not 1");
        const struct mz_json *b = mz_json_get(j, "b");
        CHECK(b && b->t == MZ_OBJ && b->len == 0, "b is not an empty object");
        CHECK(mz_json_get(j, "c") == NULL, "a missing key was found");
    }

    printf("== json_refusals\n");
    const char *badv[] = {"{\"a\":", "{\"a\":1} x", "\"\\u0000\"", "[1,]", "{\"a\" 1}", "\"\\ud83d\"", "\"\x01\"", "{\"a\":1,\"a\":2}", "[{\"x\":{\"k\":1,\"k\":1}}]"};
    for (size_t i = 0; i < sizeof badv / sizeof *badv; i++) {
        err[0] = 0;
        CHECK(mz_json_parse(badv[i], strlen(badv[i]), err, sizeof err) == NULL, "accepted bad JSON #%zu", i);
        CHECK(!strncmp(err, "line 1:", 7), "bad JSON #%zu: error '%s' does not start 'line 1:'", i, err);
    }
    char deep[200];
    memset(deep, '[', 100); memset(deep + 100, ']', 100);
    CHECK(mz_json_parse(deep, 200, err, sizeof err) == NULL, "accepted 100-deep nesting");

    printf("== recipes_json\n");
    size_t n;
    char *rbuf = slurp(argv[1], &n);
    struct mz_json *r = rbuf ? mz_json_parse(rbuf, n, err, sizeof err) : NULL;
    CHECK(r != NULL, "recipes.json did not parse: %s", err);
    if (r) {
        const struct mz_json *s = mz_json_get(r, "schema"), *rs = mz_json_get(r, "recipes");
        CHECK(s && s->t == MZ_NUM && s->n == 1, "schema is not 1");
        CHECK(rs && rs->t == MZ_ARR && rs->len >= 249, "fewer than 249 recipes");
        /* RF2: every old text survives write-then-parse unchanged */
        for (size_t i = 0; rs && i < rs->len; i++) {
            const struct mz_json *reps = mz_json_get(rs->v[i], "replacements");
            for (size_t k = 0; reps && k < reps->len; k++) {
                const struct mz_json *old = mz_json_get(reps->v[k], "old");
                /* platform: open_memstream is 10.13's; a tmpfile reads back the same bytes on 10.9 */
                FILE *m = tmpfile();
                mz_json_write_string(m, old->s, old->slen);
                size_t blen = (size_t)ftell(m);
                char *buf = malloc(blen + 1);
                rewind(m);
                blen = fread(buf, 1, blen, m);
                fclose(m);
                struct mz_json *back = mz_json_parse(buf, blen, err, sizeof err);
                CHECK(back && back->t == MZ_STR && back->slen == old->slen && !memcmp(back->s, old->s, old->slen),
                      "recipe %zu replacement %zu did not round-trip", i, k);
                free(buf);
            }
        }
    }
    if (!fails) printf("materialize-units OK\n");
    return fails ? 1 : 0;
}
