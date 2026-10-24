/* platform: Darwin DIR streams have the same public layout for both inode ABIs.
 * MacPorts fdopendir reopens "." relative to the descriptor, requiring search
 * permission that POSIX fdopendir does not require. Keep its normal/forwarded
 * path, but allocate an empty libc stream for the permission-denied case.
 * No existing system or MacPorts symbol is redefined. */
#define _DARWIN_NO_64_BIT_INODE 1
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>

typedef DIR *(*open_fd_fn)(int);
typedef DIR *(*open_dir_fn)(const char *, int);
typedef void (*rewind_fn)(DIR *);
typedef int (*close_fn)(DIR *);

static DIR *open_readable_fd(int fd, open_fd_fn original, open_dir_fn allocate,
                             rewind_fn rewind_stream, close_fn close_stream) {
    DIR *dir = original(fd);
    if (dir || errno != EACCES) return dir;
    struct statfs fs;
    /* A union stream needs libc's filesystem-specific duplicate filtering.
     * Preserve the original failure instead of returning incorrect entries. */
    if (fstatfs(fd, &fs) < 0) return NULL;
    if (fs.f_flags & MNT_UNION) { errno = EACCES; return NULL; }
    /* Without DTF_NODUP this allocates an empty stream even if / is a union.
     * Its buffer and telldir state remain owned by the matching libc ABI. */
    dir = allocate("/", DTF_HIDEW);
    if (!dir) return NULL;
    int flags = fcntl(fd, F_GETFD);
    if (flags < 0 || fcntl(fd, F_SETFD, flags | FD_CLOEXEC) < 0) {
        int saved = errno;
        close_stream(dir);
        errno = saved;
        return NULL;
    }
    close(dir->__dd_fd);
    dir->__dd_fd = fd;
    rewind_stream(dir);
    return dir;
}

DIR *__recaulk_fdopendir(int fd) {
    return open_readable_fd(fd, fdopendir, __opendir2, rewinddir, closedir);
}
extern DIR *fdopendir_ino64(int) __asm("_fdopendir$INODE64");
extern DIR *opendir2_ino64(const char *, int) __asm("___opendir2$INODE64");
extern void rewinddir_ino64(DIR *) __asm("_rewinddir$INODE64");
DIR *__recaulk_fdopendir_ino64(int) __asm("___recaulk_fdopendir$INODE64");
DIR *__recaulk_fdopendir_ino64(int fd) {
    return open_readable_fd(fd, fdopendir_ino64, opendir2_ino64,
                            rewinddir_ino64, closedir);
}
