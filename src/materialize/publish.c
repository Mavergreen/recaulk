/* The published tree: an SDK-shaped directory, the rewritten headers, a clang VFS overlay and a stamp, staged beside
   --out and published with one rename(2).
   spec: README.md "Materializing an SDK view" "Output layout", "Stamp and caching",
   "Concurrency and atomicity", "Consumer review" */
#include "materialize.h"
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static char *stage; /* removed at exit unless published */

static void rm_tree(const char *path) {
    struct stat st;
    if (lstat(path, &st)) return;
    if (S_ISDIR(st.st_mode)) {
        chmod(path, 0755);
        DIR *d = opendir(path);
        if (d) {
            struct dirent *e;
            while ((e = readdir(d))) {
                if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
                char p[PATH_MAX];
                mz_path(p, sizeof p, "%s/%s", path, e->d_name);
                rm_tree(p);
            }
            closedir(d);
        }
        rmdir(path);
    } else {
        unlink(path);
    }
}

static void cleanup(void) {
    if (stage) rm_tree(stage);
}

static int cmp_str(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }

/* the entries of a directory, sorted, without . and .. */
static char **list_dir(const char *dir, size_t *n) {
    DIR *d = opendir(dir);
    if (!d) mz_fail("cannot read %s: %s", dir, strerror(errno));
    size_t cap = 16;
    char **v = mz_xmalloc(cap * sizeof *v);
    struct dirent *e;
    *n = 0;
    while ((e = readdir(d))) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
        if (*n == cap) {
            cap *= 2;
            v = realloc(v, cap * sizeof *v);
            if (!v) mz_fail("out of memory");
        }
        v[(*n)++] = mz_xstrdup(e->d_name);
    }
    closedir(d);
    qsort(v, *n, sizeof *v, cmp_str);
    return v;
}

static void mkdirs(const char *path) {
    char p[PATH_MAX];
    mz_path(p, sizeof p, "%s", path);
    for (char *s = p + 1; *s; s++)
        if (*s == '/') {
            *s = 0;
            if (mkdir(p, 0755) && errno != EEXIST) mz_fail("cannot make %s: %s", p, strerror(errno));
            *s = '/';
        }
    if (mkdir(p, 0755) && errno != EEXIST) mz_fail("cannot make %s: %s", p, strerror(errno));
    chmod(p, 0755);
}

static void write_file(const char *path, const char *buf, size_t n) {
    FILE *f = fopen(path, "wb");
    if (!f || fwrite(buf, 1, n, f) != n || fclose(f)) mz_fail("cannot write %s: %s", path, strerror(errno));
    chmod(path, 0644);
}

/* spec: README.md "Materializing an SDK view" -- three string values from the SDK's own XML plist */
static int plist_string(const char *plist, const char *key, char *out, size_t outlen) {
    char k[128];
    mz_path(k, sizeof k, "<key>%s</key>", key);
    const char *at = strstr(plist, k);
    if (!at) return -1;
    at += strlen(k);
    while (*at == ' ' || *at == '\t' || *at == '\n' || *at == '\r') at++;
    if (strncmp(at, "<string>", 8)) return -1;
    at += 8;
    const char *end = strstr(at, "</string>");
    if (!end || (size_t)(end - at) >= outlen || memchr(at, '&', (size_t)(end - at)) || memchr(at, '<', (size_t)(end - at)))
        return -1;
    memcpy(out, at, (size_t)(end - at));
    out[end - at] = 0;
    return 0;
}

int mz_settings_json(const char *sdk_real, char **json) {
    char p[PATH_MAX];
    struct stat st;
    mz_path(p, sizeof p, "%s/SDKSettings.json", sdk_real);
    if (!lstat(p, &st)) return 1;
    mz_path(p, sizeof p, "%s/SDKSettings.plist", sdk_real);
    char *plist;
    size_t n;
    if (mz_read_file(p, &plist, &n)) mz_fail("the SDK has neither SDKSettings.json nor %s", p);
    static const char *const keys[] = {"CanonicalName", "MaximumDeploymentTarget", "Version"};
    char vals[3][128];
    for (int i = 0; i < 3; i++)
        if (plist_string(plist, keys[i], vals[i], sizeof vals[i]))
            mz_fail("%s has no plain string %s, which SDKSettings.json needs", p, keys[i]);
    free(plist);
    size_t len = 128 + strlen(vals[0]) + strlen(vals[1]) + strlen(vals[2]);
    *json = mz_xmalloc(len);
    mz_path(*json, len, "{\"CanonicalName\":\"%s\",\"MaximumDeploymentTarget\":\"%s\",\"Version\":\"%s\"}\n",
             vals[0], vals[1], vals[2]);
    return 0;
}

static void put(FILE *f, const char *s) { mz_json_write_string(f, s, strlen(s)); }

/* identity, as --print-stamp prints it and the stamp's leading keys hold */
/* sdk, given and out are NULL for --print-stamp: the caller's cache key carries its own paths */
void mz_print_identity(FILE *f, const char *profile, const char *ids_json, const char *digest, const char *recaulk,
                       const char *sdk_real, const char *given, const char *out) {
    fprintf(f, "{\"schema\":1,\"format\":%d,", MZ_FORMAT);
    if (recaulk) { fputs("\"recaulk\":", f); put(f, recaulk); fputc(',', f); }
    fputs("\"profile\":", f);
    if (profile) put(f, profile); else fputs("null", f);
    fprintf(f, ",\"ids\":%s,\"recipes\":\"%s\"", ids_json, digest);
    if (sdk_real) {
        fputs(",\"sdk\":", f); put(f, sdk_real);
        fputs(",\"given\":", f); put(f, given);
        fputs(",\"out\":", f); put(f, out);
    }
}

/* a path without its trailing slashes, so lstat sees a link as a link */
void mz_strip(char *dst, size_t n, const char *src) {
    if ((size_t)snprintf(dst, n, "%s", src) >= n) mz_fail("path too long: %s", src);
    size_t len = strlen(dst);
    while (len > 1 && dst[len - 1] == '/') dst[--len] = 0;
}

static int eq_str(const struct mz_json *v, const char *s) {
    return s ? v && v->t == MZ_STR && !strcmp(v->s, s) : v && v->t == MZ_NULL;
}

/* the stamp's identity against this run's: 0 equal; otherwise the first key that differs */
static const char *identity_differs(const struct mz_json *st, const char *profile, const struct mz_json *ids,
                                    const char *digest, const char *sdk_real, const char *given, const char *out) {
    const struct mz_json *f = mz_json_get(st, "format");
    if (!f || f->t != MZ_NUM || f->n != MZ_FORMAT) return "format";
    if (!eq_str(mz_json_get(st, "profile"), profile)) return "profile";
    const struct mz_json *si = mz_json_get(st, "ids");
    if (!si || si->t != MZ_ARR || si->len != ids->len) return "ids";
    for (size_t i = 0; i < ids->len; i++)
        if (!eq_str(si->v[i], ids->v[i]->s)) return "ids";
    if (!eq_str(mz_json_get(st, "recipes"), digest)) return "recipes";
    if (!eq_str(mz_json_get(st, "sdk"), sdk_real)) return "sdk";
    /* the overlay names the SDK as given and --out: a tree made for another spelling or place maps other names */
    if (!eq_str(mz_json_get(st, "given"), given)) return "given";
    if (!eq_str(mz_json_get(st, "out"), out)) return "out";
    return NULL;
}

static void verify_tree(const char *out, const struct mz_json *st) {
    const struct mz_json *files = mz_json_get(st, "files");
    if (!files || files->t != MZ_OBJ) mz_fail("%s/stamp.json has no files", out);
    for (size_t i = 0; i < files->len; i++) {
        char p[PATH_MAX], hex[65];
        mz_path(p, sizeof p, "%s/%s", out, files->k[i]);
        if (mz_sha256_file(p, hex) || files->v[i]->t != MZ_STR || strcmp(hex, files->v[i]->s))
            mz_fail("%s/%s does not match its stamp; remove %s to regenerate", out, files->k[i], out);
    }
}

/* 0: --out is absent and may be made; exits 0 when it holds a matching tree; refuses anything else */
int mz_existing_out(const struct mz_args *a, const char *ids_json, const char *digest, const char *sdk_real) {
    struct stat st;
    char out[PATH_MAX], given[PATH_MAX], parent[PATH_MAX], preal[PATH_MAX];
    mz_strip(out, sizeof out, a->out);
    mz_strip(given, sizeof given, a->sdk);
    /* spec: README.md "Materializing an SDK view" -- the SDK is never written, so --out may not lie inside it */
    mz_path(parent, sizeof parent, "%s", out);
    *strrchr(parent, '/') = 0;
    if (realpath(*parent ? parent : "/", preal)) {
        size_t sl = strlen(sdk_real);
        if (!strncmp(preal, sdk_real, sl) && (preal[sl] == 0 || preal[sl] == '/'))
            mz_fail("--out %s is inside the SDK %s, which is never written", a->out, sdk_real);
    }
    if (lstat(out, &st)) {
        if (errno != ENOENT) mz_fail("cannot inspect --out %s: %s", a->out, strerror(errno));
        return 0;
    }
    if (S_ISLNK(st.st_mode)) mz_fail("--out %s is a symbolic link; give a path that does not exist", a->out);
    if (!S_ISDIR(st.st_mode)) mz_fail("--out %s exists and is not a directory", a->out);
    char p[PATH_MAX], err[256], *buf;
    size_t n;
    mz_path(p, sizeof p, "%s/stamp.json", a->out);
    if (mz_read_file(p, &buf, &n))
        mz_fail("--out %s exists without a stamp; give a path that does not exist", a->out);
    struct mz_json *stj = mz_json_parse(buf, n, err, sizeof err);
    if (!stj) mz_fail("%s: %s", p, err);
    struct mz_json *ids = mz_json_parse(ids_json, strlen(ids_json), err, sizeof err);
    const char *k = identity_differs(stj, a->profile, ids, digest, sdk_real, given, out);
    if (k) mz_fail("--out %s holds a tree made for another %s; remove it or use another --out", a->out, k);
    if (a->verify) verify_tree(a->out, stj);
    exit(0);
}

struct names { char **name, **ext; size_t n, cap; };

static void add_name(struct names *ns, const char *root, const char *rel, const char *ext) {
    char p[PATH_MAX];
    mz_path(p, sizeof p, "%s/%s", root, rel);
    for (size_t i = 0; i < ns->n; i++)
        if (!strcmp(ns->name[i], p)) return;
    if (ns->n == ns->cap) {
        ns->cap = ns->cap ? ns->cap * 2 : 64;
        ns->name = realloc(ns->name, ns->cap * sizeof *ns->name);
        ns->ext = realloc(ns->ext, ns->cap * sizeof *ns->ext);
        if (!ns->name || !ns->ext) mz_fail("out of memory");
    }
    ns->name[ns->n] = mz_xstrdup(p);
    ns->ext[ns->n++] = mz_xstrdup(ext);
}

static struct names *sort_ns;
static int by_name(const void *a, const void *b) {
    return strcmp(sort_ns->name[*(const size_t *)a], sort_ns->name[*(const size_t *)b]);
}

/* every regular file under dir (relative to base), sorted */
static void walk_files(const char *base, const char *rel, char ***v, size_t *n, size_t *cap) {
    char dir[PATH_MAX];
    mz_path(dir, sizeof dir, "%s%s%s", base, *rel ? "/" : "", rel);
    size_t ne;
    char **es = list_dir(dir, &ne);
    for (size_t i = 0; i < ne; i++) {
        char r[PATH_MAX], full[PATH_MAX];
        mz_path(r, sizeof r, "%s%s%s", rel, *rel ? "/" : "", es[i]);
        mz_path(full, sizeof full, "%s/%s", base, r);
        struct stat st;
        if (lstat(full, &st)) mz_fail("cannot inspect %s", full);
        if (S_ISDIR(st.st_mode)) walk_files(base, r, v, n, cap);
        else if (S_ISREG(st.st_mode)) {
            if (*n == *cap) {
                *cap = *cap ? *cap * 2 : 64;
                *v = realloc(*v, *cap * sizeof **v);
                if (!*v) mz_fail("out of memory");
            }
            (*v)[(*n)++] = mz_xstrdup(r);
        }
        free(es[i]);
    }
    free(es);
}

void mz_publish(const struct mz_args *a, const char *sdk_real, struct mz_header *h, size_t nh, const char *ids_json,
                const char *digest) {
    char out[PATH_MAX], given[PATH_MAX], parent[PATH_MAX], tmp[PATH_MAX], p[PATH_MAX];
    mz_strip(out, sizeof out, a->out);
    mz_strip(given, sizeof given, a->sdk);
    mz_path(parent, sizeof parent, "%s", out);
    *strrchr(parent, '/') = 0;
    struct stat st;
    if (stat(*parent ? parent : "/", &st) || !S_ISDIR(st.st_mode))
        mz_fail("--out's parent %s does not exist", *parent ? parent : "/");

    mz_path(tmp, sizeof tmp, "%s.tmp.XXXXXX", out);
    if (!mkdtemp(tmp)) mz_fail("cannot make a staging directory beside %s: %s", out, strerror(errno));
    stage = mz_xstrdup(tmp);
    atexit(cleanup);
    chmod(stage, 0755);

    /* the rewritten headers */
    for (size_t i = 0; i < nh; i++) {
        mz_path(p, sizeof p, "%s/headers/%s", stage, h[i].rel);
        *strrchr(p, '/') = 0;
        mkdirs(p);
        mz_path(p, sizeof p, "%s/headers/%s", stage, h[i].rel);
        write_file(p, h[i].text, h[i].len);
    }
    if (!nh) { mz_path(p, sizeof p, "%s/headers", stage); mkdirs(p); }

    /* the SDK-shaped directory: one link per top-level SDK entry, and SDKSettings.json */
    const char *sdk_name = strrchr(sdk_real, '/') + 1;
    char view[PATH_MAX], view_out[PATH_MAX];
    mz_path(view, sizeof view, "%s/sdk/%s", stage, sdk_name);
    mz_path(view_out, sizeof view_out, "%s/sdk/%s", out, sdk_name);
    mkdirs(view);
    size_t ne;
    char **es = list_dir(sdk_real, &ne);
    for (size_t i = 0; i < ne; i++) {
        char target[PATH_MAX];
        mz_path(target, sizeof target, "%s/%s", sdk_real, es[i]);
        mz_path(p, sizeof p, "%s/%s", view, es[i]);
        if (symlink(target, p)) mz_fail("cannot link %s: %s", p, strerror(errno));
    }
    char *settings;
    if (!mz_settings_json(sdk_real, &settings)) {
        mz_path(p, sizeof p, "%s/SDKSettings.json", view);
        write_file(p, settings, strlen(settings));
    }

    /* the overlay: every header's names under the view, the SDK as given and its real path */
    struct names ns;
    memset(&ns, 0, sizeof ns);
    const char *roots[] = {view_out, given, sdk_real};
    for (size_t i = 0; i < nh; i++) {
        char ext[PATH_MAX];
        mz_path(ext, sizeof ext, "%s/headers/%s", out, h[i].rel);
        for (size_t r = 0; r < 3; r++) {
            add_name(&ns, roots[r], h[i].rel, ext);
            for (size_t k = 0; k < h[i].naliases; k++) add_name(&ns, roots[r], h[i].aliases[k], ext);
        }
    }
    size_t *order = mz_xmalloc((ns.n ? ns.n : 1) * sizeof *order);
    for (size_t i = 0; i < ns.n; i++) order[i] = i;
    sort_ns = &ns;
    qsort(order, ns.n, sizeof *order, by_name);
    mz_path(p, sizeof p, "%s/overlay.json", stage);
    FILE *f = fopen(p, "wb");
    if (!f) mz_fail("cannot write %s: %s", p, strerror(errno));
    fputs("{\"version\":0,\"case-sensitive\":\"true\",\"roots\":[", f);
    for (size_t i = 0; i < ns.n; i++) {
        fputs(i ? ",\n{\"type\":\"file\",\"name\":" : "\n{\"type\":\"file\",\"name\":", f);
        put(f, ns.name[order[i]]);
        fputs(",\"external-contents\":", f);
        put(f, ns.ext[order[i]]);
        fputc('}', f);
    }
    fputs("\n]}\n", f);
    if (fclose(f)) mz_fail("cannot write %s", p);
    chmod(p, 0644);

    /* the stamp, last */
    char **files = NULL;
    size_t nf = 0, cap = 0;
    walk_files(stage, "", &files, &nf, &cap);
    mz_path(p, sizeof p, "%s/stamp.json", stage);
    f = fopen(p, "wb");
    if (!f) mz_fail("cannot write %s: %s", p, strerror(errno));
    mz_print_identity(f, a->profile, ids_json, digest, RECAULK_VERSION, sdk_real, given, out);
    fputs(",\"archive\":", f);
    put(f, a->archive);
    fputs(",\"files\":{", f);
    for (size_t i = 0; i < nf; i++) {
        char full[PATH_MAX], hex[65];
        mz_path(full, sizeof full, "%s/%s", stage, files[i]);
        if (mz_sha256_file(full, hex)) mz_fail("cannot read %s", full);
        if (i) fputc(',', f);
        put(f, files[i]);
        fprintf(f, ":\"%s\"", hex);
    }
    fputs("}}\n", f);
    if (fclose(f)) mz_fail("cannot write %s", p);
    chmod(p, 0644);

    /* platform: renamex_np(RENAME_EXCL) is 10.12's; rename(2) refuses a non-empty target, and --out was absent */
    if (rename(stage, out)) {
        if (errno == EEXIST || errno == ENOTEMPTY || errno == EISDIR) {
            rm_tree(stage);
            stage = NULL;
            mz_existing_out(a, ids_json, digest, sdk_real); /* a racer won: exits 0 when it made the same tree */
        }
        mz_fail("cannot publish %s: %s", out, strerror(errno));
    }
    free(stage);
    stage = NULL;
}
