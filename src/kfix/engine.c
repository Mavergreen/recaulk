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
