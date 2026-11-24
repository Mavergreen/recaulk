/* A small JSON reader (RFC 8259) for recipes.json and profiles.json, and the one string writer the stamp, overlay
   and recipe digest share. Strings decode to UTF-8 bytes; an escaped NUL is refused, so every string is a C string. */
#include "materialize.h"
#include <stdlib.h>
#include <string.h>

#define MAX_DEPTH 64

struct p { const char *s, *end; int line; char *err; size_t errlen; int depth; };

static struct mz_json *bad(struct p *p, const char *why) {
    if (!p->err[0]) snprintf(p->err, p->errlen, "line %d: %s", p->line, why);
    return NULL;
}

static void ws(struct p *p) {
    while (p->s < p->end && (*p->s == ' ' || *p->s == '\t' || *p->s == '\n' || *p->s == '\r')) {
        if (*p->s == '\n') p->line++;
        p->s++;
    }
}

static struct mz_json *node(enum mz_json_type t) {
    struct mz_json *j = mz_xmalloc(sizeof *j);
    memset(j, 0, sizeof *j);
    j->t = t;
    return j;
}

static void push(struct mz_json *j, char *key, struct mz_json *v, size_t *cap) {
    if (j->len == *cap) {
        *cap = *cap ? *cap * 2 : 8;
        j->v = realloc(j->v, *cap * sizeof *j->v);
        j->k = realloc(j->k, *cap * sizeof *j->k);
        if (!j->v || !j->k) mz_fail("out of memory");
    }
    j->k[j->len] = key;
    j->v[j->len++] = v;
}

static int hex4(struct p *p, unsigned *u) {
    if (p->end - p->s < 4) return -1;
    *u = 0;
    for (int i = 0; i < 4; i++) {
        char c = *p->s++;
        *u <<= 4;
        if (c >= '0' && c <= '9') *u |= (unsigned)(c - '0');
        else if (c >= 'a' && c <= 'f') *u |= (unsigned)(c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') *u |= (unsigned)(c - 'A' + 10);
        else return -1;
    }
    return 0;
}

static struct mz_json *string(struct p *p) {
    p->s++; /* opening quote */
    size_t cap = 64, len = 0;
    char *b = mz_xmalloc(cap);
    for (;;) {
        if (p->s >= p->end) { free(b); return bad(p, "unterminated string"); }
        unsigned char c = (unsigned char)*p->s++;
        unsigned char out[4];
        size_t n = 1;
        if (c == '"') break;
        if (c < 0x20) { free(b); return bad(p, "control character in string"); }
        out[0] = c;
        if (c == '\\') {
            if (p->s >= p->end) { free(b); return bad(p, "unterminated escape"); }
            char e = *p->s++;
            switch (e) {
            case '"': case '\\': case '/': out[0] = (unsigned char)e; break;
            case 'b': out[0] = '\b'; break;
            case 'f': out[0] = '\f'; break;
            case 'n': out[0] = '\n'; break;
            case 'r': out[0] = '\r'; break;
            case 't': out[0] = '\t'; break;
            case 'u': {
                unsigned u, lo;
                if (hex4(p, &u)) { free(b); return bad(p, "bad \\u escape"); }
                if (u >= 0xdc00 && u <= 0xdfff) { free(b); return bad(p, "lone low surrogate"); }
                if (u >= 0xd800 && u <= 0xdbff) {
                    if (p->end - p->s < 6 || p->s[0] != '\\' || p->s[1] != 'u') { free(b); return bad(p, "lone high surrogate"); }
                    p->s += 2;
                    if (hex4(p, &lo) || lo < 0xdc00 || lo > 0xdfff) { free(b); return bad(p, "bad surrogate pair"); }
                    u = 0x10000 + ((u - 0xd800) << 10) + (lo - 0xdc00);
                }
                if (u == 0) { free(b); return bad(p, "NUL in string"); }
                if (u < 0x80) out[0] = (unsigned char)u;
                else if (u < 0x800) { out[0] = (unsigned char)(0xc0 | u >> 6); out[1] = (unsigned char)(0x80 | (u & 0x3f)); n = 2; }
                else if (u < 0x10000) {
                    out[0] = (unsigned char)(0xe0 | u >> 12); out[1] = (unsigned char)(0x80 | ((u >> 6) & 0x3f));
                    out[2] = (unsigned char)(0x80 | (u & 0x3f)); n = 3;
                } else {
                    out[0] = (unsigned char)(0xf0 | u >> 18); out[1] = (unsigned char)(0x80 | ((u >> 12) & 0x3f));
                    out[2] = (unsigned char)(0x80 | ((u >> 6) & 0x3f)); out[3] = (unsigned char)(0x80 | (u & 0x3f)); n = 4;
                }
                break;
            }
            default: free(b); return bad(p, "bad escape");
            }
        }
        if (len + n + 1 > cap) {
            cap *= 2;
            b = realloc(b, cap);
            if (!b) mz_fail("out of memory");
        }
        memcpy(b + len, out, n);
        len += n;
    }
    b[len] = 0;
    struct mz_json *j = node(MZ_STR);
    j->s = b;
    j->slen = len;
    return j;
}

static struct mz_json *value(struct p *p);

static struct mz_json *container(struct p *p, int obj) {
    if (++p->depth > MAX_DEPTH) return bad(p, "nested too deeply");
    struct mz_json *j = node(obj ? MZ_OBJ : MZ_ARR);
    size_t cap = 0;
    p->s++;
    ws(p);
    if (p->s < p->end && *p->s == (obj ? '}' : ']')) { p->s++; p->depth--; return j; }
    for (;;) {
        char *key = NULL;
        ws(p);
        if (obj) {
            if (p->s >= p->end || *p->s != '"') return bad(p, "expected a key");
            struct mz_json *k = string(p);
            if (!k) return NULL;
            key = k->s;
            free(k);
            ws(p);
            if (p->s >= p->end || *p->s != ':') return bad(p, "expected ':'");
            p->s++;
        }
        struct mz_json *v = value(p);
        if (!v) return NULL;
        push(j, key, v, &cap);
        ws(p);
        if (p->s < p->end && *p->s == ',') { p->s++; continue; }
        if (p->s < p->end && *p->s == (obj ? '}' : ']')) { p->s++; break; }
        return bad(p, obj ? "expected ',' or '}'" : "expected ',' or ']'");
    }
    p->depth--;
    return j;
}

static struct mz_json *number(struct p *p) {
    const char *st = p->s;
    if (p->s < p->end && *p->s == '-') p->s++;
    if (p->s >= p->end || *p->s < '0' || *p->s > '9') return bad(p, "bad value");
    while (p->s < p->end && ((*p->s >= '0' && *p->s <= '9') || *p->s == '.' || *p->s == 'e' || *p->s == 'E' ||
                             *p->s == '+' || *p->s == '-'))
        p->s++;
    char tmp[64];
    size_t n = (size_t)(p->s - st);
    if (n >= sizeof tmp) return bad(p, "number too long");
    memcpy(tmp, st, n);
    tmp[n] = 0;
    char *e;
    double d = strtod(tmp, &e);
    if (*e) return bad(p, "bad number");
    struct mz_json *j = node(MZ_NUM);
    j->n = d;
    return j;
}

static int lit(struct p *p, const char *w) {
    size_t n = strlen(w);
    if ((size_t)(p->end - p->s) < n || memcmp(p->s, w, n)) return 0;
    p->s += n;
    return 1;
}

static struct mz_json *value(struct p *p) {
    ws(p);
    if (p->s >= p->end) return bad(p, "unexpected end");
    switch (*p->s) {
    case '{': return container(p, 1);
    case '[': return container(p, 0);
    case '"': return string(p);
    }
    if (lit(p, "true")) { struct mz_json *j = node(MZ_BOOL); j->b = 1; return j; }
    if (lit(p, "false")) return node(MZ_BOOL);
    if (lit(p, "null")) return node(MZ_NULL);
    return number(p);
}

struct mz_json *mz_json_parse(const char *buf, size_t n, char *err, size_t errlen) {
    struct p p = {buf, buf + n, 1, err, errlen, 0};
    err[0] = 0;
    struct mz_json *j = value(&p);
    if (!j) return NULL;
    ws(&p);
    if (p.s != p.end) return bad(&p, "trailing data");
    return j;
}

const struct mz_json *mz_json_get(const struct mz_json *obj, const char *key) {
    if (!obj || obj->t != MZ_OBJ) return NULL;
    for (size_t i = 0; i < obj->len; i++)
        if (!strcmp(obj->k[i], key)) return obj->v[i];
    return NULL;
}

void mz_json_write_string(FILE *f, const char *s, size_t n) {
    fputc('"', f);
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        if (c == '"' || c == '\\') { fputc('\\', f); fputc(c, f); }
        else if (c == '\n') fputs("\\n", f);
        else if (c == '\t') fputs("\\t", f);
        else if (c < 0x20) fprintf(f, "\\u%04x", c);
        else fputc(c, f);
    }
    fputc('"', f);
}
