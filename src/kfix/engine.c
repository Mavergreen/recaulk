/* spec: README.md "The kernel-fixes kext" -- a fix changes only bytes it has verified, stands down over its own
   replacement (another kext applied it), and the recaulk_kfix boot-arg turns fixes off */
#include <sys/errno.h>
#include <string.h>
#include "engine.h"

int
kf_check_patch(const struct kf_patch *p, const uint8_t *site, enum kf_state *st, const char **why)
{
	if (memcmp(site, p->expect, p->len) == 0) {
		*st = KF_NOT_APPLIED;
		return 0;
	}
	if (memcmp(site, p->replace, p->len) == 0) {
		*st = KF_FOREIGN;
		return 0;
	}
	*why = "neither the expected bytes nor the replacement at the site";
	return ESRCH;
}

int
kf_uuid_eq(const uint8_t a[16], const uint8_t b[16])
{
	return memcmp(a, b, 16) == 0;
}

static int
is_space(char c)
{
	return c == ' ' || c == '\t' || c == '\n';
}

/* the value [v, v+n) of recaulk_kfix= turns `name` off */
static int
value_disables(const char *v, size_t n, const char *name)
{
	size_t nl = strlen(name);
	if (n == 1 && v[0] == '0')
		return 1;
	while (n > 0) {
		size_t i = 0;
		while (i < n && v[i] != ',')
			i++;
		if (i == nl + 1 && v[0] == '-' && memcmp(v + 1, name, nl) == 0)
			return 1;
		v += i;
		n -= i;
		if (n > 0) {
			v++;
			n--;
		}
	}
	return 0;
}

int
kf_bootarg_disabled(const char *cmdline, const char *name)
{
	static const char key[] = "recaulk_kfix=";
	const char *s = cmdline;
	if (s == NULL)
		return 0;
	while (*s != '\0') {
		while (is_space(*s))
			s++;
		const char *t = s;
		while (*t != '\0' && !is_space(*t))
			t++;
		size_t n = (size_t)(t - s);
		if (n >= sizeof key - 1 && memcmp(s, key, sizeof key - 1) == 0
		    && value_disables(s + sizeof key - 1, n - (sizeof key - 1), name))
			return 1;
		s = t;
	}
	return 0;
}

static int32_t
rd32(const uint8_t *p)
{
	return (int32_t)((uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24);
}

int
kf_find_call(const uint8_t *fn, size_t fnlen, uint64_t fn_addr, uint64_t target, const uint8_t *before,
    size_t nbefore, uint64_t *call_addr, const char **why)
{
	unsigned found = 0;
	uint64_t at = 0;
	for (size_t i = nbefore; i + 5 <= fnlen; i++) {
		if (fn[i] != 0xe8 || memcmp(fn + i - nbefore, before, nbefore) != 0)
			continue;
		if (fn_addr + i + 5 + (uint64_t)(int64_t)rd32(fn + i + 1) != target)
			continue;
		found++;
		at = fn_addr + i;
	}
	if (found != 1) {
		*why = found == 0 ? "no call to the target after the expected bytes" : "more than one matching call";
		return ESRCH;
	}
	*call_addr = at;
	return 0;
}

int
kf_store_ok(uint64_t addr, size_t len)
{
	return len > 0 && len <= 64 && (addr & ~(uint64_t)63) == ((addr + len - 1) & ~(uint64_t)63);
}

int
kf_rel32(uint64_t next_ip, uint64_t target, int32_t *disp)
{
	int64_t d = (int64_t)(target - next_ip);
	if (d < -(int64_t)0x80000000LL || d > (int64_t)0x7fffffffLL)
		return ERANGE;
	*disp = (int32_t)d;
	return 0;
}

int
kf_gap_ok(const uint8_t *pre, size_t need)
{
	if (pre[0] != 0xc3)
		return 0;
	for (size_t i = 1; i <= need; i++)
		if (pre[i] != 0x90)
			return 0;
	return 1;
}

void
kf_trampoline(uint8_t out[KF_TRAMPOLINE_LEN], uint64_t handler)
{
	out[0] = 0xff;
	out[1] = 0x25;
	out[2] = out[3] = out[4] = out[5] = 0;
	for (int i = 0; i < 8; i++)
		out[6 + i] = (uint8_t)(handler >> (8 * i));
}

static int
fbt_ret_like(uint8_t b)
{
	return b == 0xc3 || b == 0xc2 || b == 0xe9 || b == 0xeb || b == 0xea;
}

int
kf_trampoline_fbt_safe(const uint8_t tr[KF_TRAMPOLINE_LEN], uint8_t next)
{
	for (int i = 0; i < KF_TRAMPOLINE_LEN; i++) {
		uint8_t after = i + 1 < KF_TRAMPOLINE_LEN ? tr[i + 1] : next;
		if ((tr[i] == 0x5d || tr[i] == 0xc9) && fbt_ret_like(after))
			return 0;
	}
	return 1;
}
