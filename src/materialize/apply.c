/* Selecting recipes and applying them to the SDK's headers, in memory.
   spec: .superpowers/specs/2026-11-24-recaulk-materialize-design.md "Applying recipes" -- shipyard's
   MavericksSDKMetadata.cmake's semantics: every replacement's old text occurs exactly once in the header as the SDK
   has it, replacements may not overlap, and all of a recipe's replacements apply to that original text. */
#include "materialize.h"
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static const char *str(const struct mz_json *o, const char *key, const char *where) {
    const struct mz_json *v = mz_json_get(o, key);
    if (!v || v->t != MZ_STR || !v->slen) mz_fail("%s has no %s string", where, key);
    return v->s;
}

static const struct mz_json *arr(const struct mz_json *o, const char *key, const char *where) {
    const struct mz_json *v = mz_json_get(o, key);
    if (!v || v->t != MZ_ARR) mz_fail("%s has no %s array", where, key);
    return v;
}

static void only_keys(const struct mz_json *o, const char *where, const char *const *keys) {
    if (!o || o->t != MZ_OBJ) mz_fail("%s is not an object", where);
    for (size_t i = 0; i < o->len; i++) {
        const char *const *k = keys;
        while (*k && strcmp(*k, o->k[i])) k++;
        if (!*k) mz_fail("%s has an unexpected key '%s'", where, o->k[i]);
    }
}

static const struct mz_json *recipe_by_id(const struct mz_json *recipes, const char *id) {
    const struct mz_json *rs = mz_json_get(recipes, "recipes");
    for (size_t i = 0; i < rs->len; i++) {
        const struct mz_json *v = mz_json_get(rs->v[i], "id");
        if (v && v->t == MZ_STR && !strcmp(v->s, id)) return rs->v[i];
    }
    return NULL;
}

static int cmp_str(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }

int mz_select(const struct mz_json *recipes, const struct mz_json *profiles, const struct mz_args *a,
              const struct mz_json ***sel, size_t *nsel, char **ids_sorted_json) {
    static const char *const top[] = {"schema", "sdk", "sdk_archive_sha256", "recipes", NULL};
    only_keys(recipes, "the recipe file", top);
    const struct mz_json *schema = mz_json_get(recipes, "schema");
    if (!schema || schema->t != MZ_NUM || schema->n != 1) mz_fail("the recipe file's schema is not 1");
    const struct mz_json *rs = arr(recipes, "recipes", "the recipe file");
    for (size_t i = 0; i < rs->len; i++)
        for (size_t k = 0; k < i; k++)
            if (!strcmp(str(rs->v[i], "id", "a recipe"), str(rs->v[k], "id", "a recipe")))
                mz_fail("recipe id '%s' appears more than once in the recipe file", str(rs->v[i], "id", "a recipe"));

    const char **ids;
    size_t n;
    if (a->profile) {
        const struct mz_json *ps = profiles ? mz_json_get(profiles, "profiles") : NULL;
        const struct mz_json *p = mz_json_get(ps, a->profile);
        if (!p) mz_fail("no profile '%s'", a->profile);
        const struct mz_json *pids = arr(p, "recipes", a->profile);
        /* spec: the design's "Layering" -- a profile carries every recipe id of the profile it names as its base */
        const struct mz_json *base = mz_json_get(p, "base");
        if (base) {
            if (base->t != MZ_STR) mz_fail("profile '%s' has a base that is not a string", a->profile);
            const struct mz_json *bp = mz_json_get(ps, base->s);
            if (!bp || !strcmp(base->s, a->profile)) mz_fail("base '%s' of '%s' is not a profile", base->s, a->profile);
            const struct mz_json *bids = arr(bp, "recipes", base->s);
            for (size_t i = 0; i < bids->len; i++) {
                size_t k = 0;
                while (k < pids->len && !(pids->v[k]->t == MZ_STR && bids->v[i]->t == MZ_STR &&
                                           !strcmp(pids->v[k]->s, bids->v[i]->s)))
                    k++;
                if (k == pids->len)
                    mz_fail("profile '%s' lacks '%s' from its base '%s'", a->profile,
                            bids->v[i]->t == MZ_STR ? bids->v[i]->s : "?", base->s);
            }
        }
        n = pids->len;
        ids = mz_xmalloc(n * sizeof *ids);
        for (size_t i = 0; i < n; i++) {
            if (pids->v[i]->t != MZ_STR) mz_fail("profile '%s' lists a recipe that is not a string", a->profile);
            ids[i] = pids->v[i]->s;
        }
    } else {
        n = (size_t)a->nids;
        ids = a->ids;
    }
    *sel = mz_xmalloc(n * sizeof **sel);
    for (size_t i = 0; i < n; i++) {
        for (size_t k = 0; k < i; k++)
            if (!strcmp(ids[i], ids[k])) mz_fail("recipe id '%s' is selected more than once", ids[i]);
        (*sel)[i] = recipe_by_id(recipes, ids[i]);
        if (!(*sel)[i]) mz_fail("no recipe '%s' in the recipe file", ids[i]);
    }
    *nsel = n;

    char **sorted = mz_xmalloc(n * sizeof *sorted);
    for (size_t i = 0; i < n; i++) sorted[i] = (char *)ids[i];
    qsort(sorted, n, sizeof *sorted, cmp_str);
    FILE *f = tmpfile();
    if (!f) mz_fail("tmpfile: %s", strerror(errno));
    fputc('[', f);
    for (size_t i = 0; i < n; i++) {
        if (i) fputc(',', f);
        mz_json_write_string(f, sorted[i], strlen(sorted[i]));
    }
    fputc(']', f);
    size_t len = (size_t)ftell(f);
    *ids_sorted_json = mz_xmalloc(len + 1);
    rewind(f);
    if (fread(*ids_sorted_json, 1, len, f) != len) mz_fail("tmpfile: short read");
    (*ids_sorted_json)[len] = 0;
    fclose(f);
    free(sorted);
    return 0;
}

/* spec: shipyard's _msm_sdk_file -- a plain relative path, inside the SDK once resolved, a file */
static char *sdk_file(const char *sdk_real, const char *rel, const char *where) {
    size_t n = strlen(rel);
    if (rel[0] == '/' || rel[n - 1] == '/' || strstr(rel, "//") || strpbrk(rel, "\n\r\t\"\\") ||
        !strcmp(rel, ".") || !strcmp(rel, "..") || !strncmp(rel, "./", 2) || !strncmp(rel, "../", 3) ||
        strstr(rel, "/./") || strstr(rel, "/../") || (n >= 2 && !strcmp(rel + n - 2, "/.")) ||
        (n >= 3 && !strcmp(rel + n - 3, "/..")))
        mz_fail("%s '%s' is not a plain path relative to the SDK", where, rel);
    /* spec: the consumer review -- swift's importer overlay owns these */
    if (!strncmp(rel, "usr/include/dispatch/", 21) || !strcmp(rel, "usr/include/pthread/qos.h"))
        mz_fail("%s '%s' is reserved for the toolchain's own overlay", where, rel);
    char joined[PATH_MAX], real[PATH_MAX];
    snprintf(joined, sizeof joined, "%s/%s", sdk_real, rel);
    if (!realpath(joined, real)) mz_fail("%s '%s' does not exist in the SDK", where, rel);
    size_t sl = strlen(sdk_real);
    if (strncmp(real, sdk_real, sl) || real[sl] != '/')
        mz_fail("%s '%s' resolves outside the SDK, to %s", where, rel, real);
    struct stat st;
    if (stat(real, &st) || !S_ISREG(st.st_mode)) mz_fail("%s '%s' is not a regular file", where, rel);
    return mz_xstrdup(real);
}

struct edit { size_t start, end; const struct mz_json *new; };

static int by_start(const void *a, const void *b) {
    const struct edit *x = a, *y = b;
    return x->start < y->start ? -1 : x->start > y->start;
}

static const char *find(const char *hay, size_t hn, const char *needle, size_t nn, size_t from) {
    for (size_t i = from; nn <= hn && i <= hn - nn; i++)
        if (!memcmp(hay + i, needle, nn)) return hay + i;
    return NULL;
}

void mz_apply(const char *sdk_real, const struct mz_json **sel, size_t nsel, struct mz_header **out, size_t *nout) {
    static const char *const rkeys[] = {"id", "header", "sha256", "aliases", "replacements", NULL};
    static const char *const ekeys[] = {"old", "new", NULL};
    struct mz_header *hs = mz_xmalloc(nsel * sizeof *hs);
    char **reals = mz_xmalloc(nsel * sizeof *reals);
    const char **owner = mz_xmalloc(nsel * sizeof *owner);
    for (size_t i = 0; i < nsel; i++) {
        const struct mz_json *r = sel[i];
        const char *id = str(r, "id", "a recipe");
        char w[512];
        snprintf(w, sizeof w, "recipe '%s'", id);
        only_keys(r, w, rkeys);
        const char *header = str(r, "header", w), *want = str(r, "sha256", w);
        char hw[600];
        snprintf(hw, sizeof hw, "%s header", w);
        char *real = sdk_file(sdk_real, header, hw);
        for (size_t k = 0; k < i; k++)
            if (!strcmp(reals[k], real)) mz_fail("%s edits %s, which recipe '%s' also edits", w, header, owner[k]);
        reals[i] = real;
        owner[i] = id;

        char got[65];
        if (mz_sha256_file(real, got)) mz_fail("%s: cannot read %s", w, header);
        if (strcmp(got, want)) mz_fail("%s: %s has SHA-256 %s, the recipe wants %s", w, header, got, want);

        const struct mz_json *al = arr(r, "aliases", w);
        hs[i].rel = mz_xstrdup(header);
        hs[i].naliases = al->len;
        hs[i].aliases = mz_xmalloc(al->len * sizeof *hs[i].aliases);
        for (size_t k = 0; k < al->len; k++) {
            if (al->v[k]->t != MZ_STR) mz_fail("%s aliases[%zu] is not a string", w, k);
            char aw[600];
            snprintf(aw, sizeof aw, "%s alias", w);
            char *areal = sdk_file(sdk_real, al->v[k]->s, aw);
            if (strcmp(areal, real))
                mz_fail("%s alias '%s' resolves to %s, not to the header %s", w, al->v[k]->s, areal, real);
            free(areal);
            hs[i].aliases[k] = al->v[k]->s;
        }

        char *text;
        size_t tn;
        if (mz_read_file(real, &text, &tn)) mz_fail("%s: cannot read %s", w, header);
        const struct mz_json *reps = arr(r, "replacements", w);
        if (!reps->len) mz_fail("%s has no replacements", w);
        struct edit *ed = mz_xmalloc(reps->len * sizeof *ed);
        size_t total = tn;
        for (size_t k = 0; k < reps->len; k++) {
            char ew[700];
            snprintf(ew, sizeof ew, "%s replacements[%zu]", w, k);
            only_keys(reps->v[k], ew, ekeys);
            const struct mz_json *old = mz_json_get(reps->v[k], "old"), *nw = mz_json_get(reps->v[k], "new");
            if (!old || old->t != MZ_STR || !old->slen || !nw || nw->t != MZ_STR) mz_fail("%s needs old and new strings", ew);
            if (!nw->slen) mz_fail("%s: new is empty", ew);
            if (nw->slen == old->slen && !memcmp(nw->s, old->s, old->slen)) mz_fail("%s changes nothing", ew);
            const char *at = find(text, tn, old->s, old->slen, 0);
            if (!at) mz_fail("%s: '%s' does not occur in %s", w, old->s, header);
            if (find(text, tn, old->s, old->slen, (size_t)(at - text) + 1))
                mz_fail("%s: '%s' occurs more than once in %s", w, old->s, header);
            ed[k].start = (size_t)(at - text);
            ed[k].end = ed[k].start + old->slen;
            ed[k].new = nw;
            for (size_t e = 0; e < k; e++)
                if (ed[k].start < ed[e].end && ed[e].start < ed[k].end)
                    mz_fail("%s: replacements[%zu] and replacements[%zu] overlap in %s", w, e, k, header);
            total += nw->slen;
        }
        qsort(ed, reps->len, sizeof *ed, by_start);
        char *o = mz_xmalloc(total + 1);
        size_t on = 0, from = 0;
        for (size_t k = 0; k < reps->len; k++) {
            memcpy(o + on, text + from, ed[k].start - from);
            on += ed[k].start - from;
            memcpy(o + on, ed[k].new->s, ed[k].new->slen);
            on += ed[k].new->slen;
            from = ed[k].end;
        }
        memcpy(o + on, text + from, tn - from);
        on += tn - from;
        o[on] = 0;
        hs[i].text = o;
        hs[i].len = on;
        free(text);
        free(ed);
    }
    free(owner);
    for (size_t i = 0; i < nsel; i++) free(reals[i]);
    free(reals);
    *out = hs;
    *nout = nsel;
}

void mz_recipes_digest(const struct mz_json **sel, size_t nsel, char hex[65]) {
    const struct mz_json **s = mz_xmalloc(nsel * sizeof *s);
    memcpy(s, sel, nsel * sizeof *s);
    for (size_t i = 1; i < nsel; i++) /* insertion sort by id: profiles are a few hundred recipes */
        for (size_t k = i; k > 0 && strcmp(mz_json_get(s[k - 1], "id")->s, mz_json_get(s[k], "id")->s) > 0; k--) {
            const struct mz_json *t = s[k]; s[k] = s[k - 1]; s[k - 1] = t;
        }
    FILE *f = tmpfile();
    if (!f) mz_fail("tmpfile: %s", strerror(errno));
    fputc('[', f);
    for (size_t i = 0; i < nsel; i++) {
        const struct mz_json *r = s[i];
        static const char *const order[] = {"id", "header", "sha256"};
        if (i) fputc(',', f);
        fputc('{', f);
        for (size_t k = 0; k < 3; k++) {
            const struct mz_json *v = mz_json_get(r, order[k]);
            fprintf(f, "%s\"%s\":", k ? "," : "", order[k]);
            mz_json_write_string(f, v->s, v->slen);
        }
        fputs(",\"aliases\":[", f);
        const struct mz_json *al = mz_json_get(r, "aliases");
        for (size_t k = 0; k < al->len; k++) {
            if (k) fputc(',', f);
            mz_json_write_string(f, al->v[k]->s, al->v[k]->slen);
        }
        fputs("],\"replacements\":[", f);
        const struct mz_json *reps = mz_json_get(r, "replacements");
        for (size_t k = 0; k < reps->len; k++) {
            const struct mz_json *o = mz_json_get(reps->v[k], "old"), *n = mz_json_get(reps->v[k], "new");
            fputs(k ? ",{\"old\":" : "{\"old\":", f);
            mz_json_write_string(f, o->s, o->slen);
            fputs(",\"new\":", f);
            mz_json_write_string(f, n->s, n->slen);
            fputc('}', f);
        }
        fputs("]}", f);
    }
    fputc(']', f);
    size_t len = (size_t)ftell(f);
    char *buf = mz_xmalloc(len);
    rewind(f);
    if (fread(buf, 1, len, f) != len) mz_fail("tmpfile: short read");
    fclose(f);
    mz_sha256(buf, len, hex);
    free(buf);
    free(s);
}
