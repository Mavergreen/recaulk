#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <string.h>
#include <unistd.h>
#include <os/system_version.h>

static int read_system_version_plist(char *buf, size_t cap, size_t *len) {
	size_t n = 0;
	int fd = open("/System/Library/CoreServices/SystemVersion.plist", O_RDONLY | O_CLOEXEC);
	if (fd < 0) return errno;
	while (n < cap) {
		ssize_t r = read(fd, buf + n, cap - n);
		if (r < 0 && errno == EINTR) continue;
		if (r < 0) {
			int e = errno;
			close(fd);
			return e;
		}
		if (r == 0) break;
		n += (size_t)r;
	}
	close(fd);
	*len = n;
	return 0;
}

__attribute__((visibility("hidden")))
int (*__recaulk_os_system_version_read)(char *buf, size_t cap, size_t *len) = read_system_version_plist;

static const char *skip_space(const char *p, const char *end) {
	while (p < end && (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')) p++;
	return p;
}

static const char *find(const char *p, const char *end, const char *s) {
	size_t n = strlen(s);
	for (; (size_t)(end - p) >= n; p++)
		if (memcmp(p, s, n) == 0) return p;
	return 0;
}

static int parse(const char *p, const char *end, unsigned int out[3]) {
	static const char key[] = "<key>ProductVersion</key>", open_tag[] = "<string>", close_tag[] = "</string>";
	int i;
	p = find(p, end, key);
	if (!p) return EINVAL;
	p = skip_space(p + sizeof key - 1, end);
	if ((size_t)(end - p) < sizeof open_tag - 1 || memcmp(p, open_tag, sizeof open_tag - 1) != 0) return EINVAL;
	p += sizeof open_tag - 1;
	out[2] = 0;
	for (i = 0; i < 3; i++) {
		unsigned long v = 0;
		const char *start = p;
		while (p < end && *p >= '0' && *p <= '9') {
			v = v * 10 + (unsigned long)(*p++ - '0');
			if (v > UINT_MAX) return EINVAL;
		}
		if (p == start) return EINVAL;
		out[i] = (unsigned int)v;
		if (p < end && *p == '.' && i < 2) {
			p++;
			continue;
		}
		if (i == 0) return EINVAL;
		break;
	}
	if ((size_t)(end - p) < sizeof close_tag - 1 || memcmp(p, close_tag, sizeof close_tag - 1) != 0) return EINVAL;
	return 0;
}

int os_system_version_get_current_version(struct os_system_version_s *version) {
	char buf[8192];
	size_t len = 0;
	unsigned int v[3];
	int saved = errno;
	int rc = __recaulk_os_system_version_read(buf, sizeof buf, &len);
	if (rc == 0 && len > sizeof buf) rc = EINVAL;
	if (rc == 0) rc = parse(buf, buf + len, v);
	errno = saved;
	if (rc != 0) return rc;
	version->major = v[0];
	version->minor = v[1];
	version->patch = v[2];
	return 0;
}
