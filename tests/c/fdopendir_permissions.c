#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int main(void) {
    char path[] = "/tmp/recaulk-fdopendir.XXXXXX", marker[256];
    assert(mkdtemp(path));
    snprintf(marker, sizeof marker, "%s/marker", path);
    int file = open(marker, O_CREAT | O_RDWR, 0600);
    assert(file >= 0);
    errno = 0;
    assert(fdopendir(file) == NULL && errno == ENOTDIR);
    assert(fcntl(file, F_GETFD) >= 0); /* Failure retains ownership. */
    close(file);
    int fd = open(path, O_RDONLY);
    assert(fd >= 0);
    assert(chmod(path, 0444) == 0);
    DIR *dir = fdopendir(fd);
    assert(dir);
    assert(dirfd(dir) == fd);
    assert(fcntl(fd, F_GETFD) & FD_CLOEXEC);
    for (int pass = 0; pass != 2; ++pass) {
        int found = 0;
        struct dirent *entry;
        errno = 0;
        while ((entry = readdir(dir)))
            found += strcmp(entry->d_name, "marker") == 0;
        assert(errno == 0 && found == 1);
        rewinddir(dir);
    }
    assert(closedir(dir) == 0);
    assert(fcntl(fd, F_GETFD) == -1 && errno == EBADF);
    assert(chmod(path, 0700) == 0);
    assert(unlink(marker) == 0);
    assert(rmdir(path) == 0);
    errno = 0;
    assert(fdopendir(-1) == NULL && errno == EBADF);
    puts("fdopendir readable directory: all passed");
}
