#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/fs.h>
#include <linux/input.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>

enum kindish_fd_type { FD_NONE, FD_FRAMEBUFFER, FD_VARLOCAL, FD_TOUCH };
static unsigned char fd_types[4096];

static void remember_fd(int fd, const char *original) {
    if (fd < 0 || fd >= (int)sizeof(fd_types) || !original) return;
    if (!strcmp(original, "/dev/fb0")) fd_types[fd] = FD_FRAMEBUFFER;
    else if (!strcmp(original, "/dev/mmcblk0p9")) fd_types[fd] = FD_VARLOCAL;
    else if (!strcmp(original, "/dev/input/kindish-touch")) fd_types[fd] = FD_TOUCH;
}

static void set_bit(unsigned char *bits, unsigned int bit, size_t size) {
    size_t byte = bit / 8;
    if (byte < size) bits[byte] |= (unsigned char)(1U << (bit % 8));
}

/* qemu-user does not translate the old Xorg evdev ioctl ABI on every host.
 * Answer capability discovery in userspace while leaving read/poll on the
 * real uinput fd. The advertised layout matches kindish_uinput.c. */
static int touch_ioctl(unsigned long request, void *arg) {
    unsigned int nr = _IOC_NR(request);
    size_t size = _IOC_SIZE(request);

    if (request == EVIOCGVERSION) {
        *(int *)arg = EV_VERSION;
        return 0;
    }
    if (request == EVIOCGID) {
        struct input_id *id = arg;
        id->bustype = BUS_USB;
        id->vendor = 0x1949;
        id->product = 0x9981;
        id->version = 1;
        return 0;
    }
    if (nr == _IOC_NR(EVIOCGNAME(0))) {
        snprintf(arg, size, "kindish-zforce");
        return 0;
    }
    if (nr == _IOC_NR(EVIOCGPHYS(0))) {
        snprintf(arg, size, "kindish/input0");
        return 0;
    }
    if (nr == _IOC_NR(EVIOCGUNIQ(0))) {
        if (size) ((char *)arg)[0] = '\0';
        return 0;
    }
    if (nr == _IOC_NR(EVIOCGPROP(0))) {
        memset(arg, 0, size);
        set_bit(arg, INPUT_PROP_DIRECT, size);
        return 0;
    }
    if (nr >= _IOC_NR(EVIOCGBIT(0, 0)) &&
        nr <= _IOC_NR(EVIOCGBIT(EV_MAX, 0))) {
        unsigned int event_type = nr - _IOC_NR(EVIOCGBIT(0, 0));
        memset(arg, 0, size);
        if (event_type == 0) {
            set_bit(arg, EV_SYN, size);
            set_bit(arg, EV_KEY, size);
            set_bit(arg, EV_ABS, size);
        } else if (event_type == EV_KEY) {
            set_bit(arg, BTN_TOUCH, size);
            set_bit(arg, BTN_TOOL_FINGER, size);
        } else if (event_type == EV_ABS) {
            set_bit(arg, ABS_X, size);
            set_bit(arg, ABS_Y, size);
            set_bit(arg, ABS_MT_SLOT, size);
            set_bit(arg, ABS_MT_TOUCH_MAJOR, size);
            set_bit(arg, ABS_MT_POSITION_X, size);
            set_bit(arg, ABS_MT_POSITION_Y, size);
            set_bit(arg, ABS_MT_TRACKING_ID, size);
        }
        return 0;
    }
    if (nr >= _IOC_NR(EVIOCGABS(0)) && nr <= _IOC_NR(EVIOCGABS(ABS_MAX))) {
        unsigned int axis = nr - _IOC_NR(EVIOCGABS(0));
        struct input_absinfo *info = arg;
        memset(info, 0, sizeof(*info));
        switch (axis) {
            case ABS_X:
            case ABS_MT_POSITION_X:
                info->maximum = 1071;
                info->resolution = 12;
                break;
            case ABS_Y:
            case ABS_MT_POSITION_Y:
                info->maximum = 1447;
                info->resolution = 12;
                break;
            case ABS_MT_SLOT:
                info->maximum = 9;
                break;
            case ABS_MT_TRACKING_ID:
                info->maximum = 65535;
                break;
            case ABS_MT_TOUCH_MAJOR:
                info->maximum = 255;
                break;
            default:
                break;
        }
        return 0;
    }
    if (request == EVIOCGRAB) return 0;
    return -1;
}

/*
 * Kindle userspace reads Lab126 identity nodes created by the MT8110 kernel.
 * QEMU's generic host kernel cannot create those procfs nodes, so redirect
 * only those reads to deterministic files in the emulator overlay.
 */
static const char *redirect_path(const char *path) {
    if (!path) return path;
    if (!strcmp(path, "/proc/board_id")) return "/var/local/kindish/proc/board_id";
    else if (!strcmp(path, "/proc/usid")) return "/var/local/kindish/proc/usid";
    else if (!strcmp(path, "/proc/device_type_id")) return "/var/local/kindish/proc/device_type_id";
    else if (!strcmp(path, "/dev/fb0")) return "/var/local/kindish/dev/fb0";
    else if (!strcmp(path, "/dev/mmcblk0p9")) return "/var/local/kindish/dev/varlocal.img";
    return path;
}

FILE *fopen64(const char *path, const char *mode) {
    static FILE *(*real_fopen64)(const char *, const char *);
    if (!real_fopen64) real_fopen64 = dlsym(RTLD_NEXT, "fopen64");
    return real_fopen64(redirect_path(path), mode);
}

FILE *fopen(const char *path, const char *mode) {
    static FILE *(*real_fopen)(const char *, const char *);
    if (!real_fopen) real_fopen = dlsym(RTLD_NEXT, "fopen");
    return real_fopen(redirect_path(path), mode);
}

int open64(const char *path, int flags, ...) {
    static int (*real_open64)(const char *, int, ...);
    mode_t mode = 0;
    if (!real_open64) real_open64 = dlsym(RTLD_NEXT, "open64");
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = (mode_t)va_arg(args, int);
        va_end(args);
        int fd = real_open64(redirect_path(path), flags, mode);
        remember_fd(fd, path);
        return fd;
    }
    int fd = real_open64(redirect_path(path), flags);
    remember_fd(fd, path);
    return fd;
}

int open(const char *path, int flags, ...) {
    static int (*real_open)(const char *, int, ...);
    mode_t mode = 0;
    if (!real_open) real_open = dlsym(RTLD_NEXT, "open");
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = (mode_t)va_arg(args, int);
        va_end(args);
        int fd = real_open(redirect_path(path), flags, mode);
        remember_fd(fd, path);
        return fd;
    }
    int fd = real_open(redirect_path(path), flags);
    remember_fd(fd, path);
    return fd;
}

int openat64(int dirfd, const char *path, int flags, ...) {
    static int (*real_openat64)(int, const char *, int, ...);
    mode_t mode = 0;
    if (!real_openat64) real_openat64 = dlsym(RTLD_NEXT, "openat64");
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = (mode_t)va_arg(args, int);
        va_end(args);
        int fd = real_openat64(dirfd, redirect_path(path), flags, mode);
        remember_fd(fd, path);
        return fd;
    }
    int fd = real_openat64(dirfd, redirect_path(path), flags);
    remember_fd(fd, path);
    return fd;
}

int openat(int dirfd, const char *path, int flags, ...) {
    static int (*real_openat)(int, const char *, int, ...);
    mode_t mode = 0;
    if (!real_openat) real_openat = dlsym(RTLD_NEXT, "openat");
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = (mode_t)va_arg(args, int);
        va_end(args);
        int fd = real_openat(dirfd, redirect_path(path), flags, mode);
        remember_fd(fd, path);
        return fd;
    }
    int fd = real_openat(dirfd, redirect_path(path), flags);
    remember_fd(fd, path);
    return fd;
}

int ioctl(int fd, unsigned long request, ...) {
    static int (*real_ioctl)(int, unsigned long, ...);
    void *arg;
    va_list args;
    va_start(args, request);
    arg = va_arg(args, void *);
    va_end(args);
    if (!real_ioctl) real_ioctl = dlsym(RTLD_NEXT, "ioctl");

    if (fd >= 0 && fd < (int)sizeof(fd_types) && fd_types[fd] == FD_FRAMEBUFFER) {
        if (request == FBIOGET_VSCREENINFO) {
            struct fb_var_screeninfo *v = arg;
            memset(v, 0, sizeof(*v));
            v->xres = v->xres_virtual = 1072;
            v->yres = v->yres_virtual = 1448;
            v->bits_per_pixel = 8;
            v->grayscale = 1;
            v->width = 90;
            v->height = 122;
            return 0;
        }
        if (request == FBIOGET_FSCREENINFO) {
            struct fb_fix_screeninfo *f = arg;
            memset(f, 0, sizeof(*f));
            memcpy(f->id, "kindish", 7);
            f->type = FB_TYPE_PACKED_PIXELS;
            f->visual = FB_VISUAL_STATIC_PSEUDOCOLOR;
            f->line_length = 1072;
            f->smem_len = 1072 * 1448;
            return 0;
        }
        if (request == FBIOPUT_VSCREENINFO || request == FBIOBLANK) return 0;
    }
    if (fd >= 0 && fd < (int)sizeof(fd_types) && fd_types[fd] == FD_VARLOCAL) {
        if (request == BLKGETSIZE) {
            *(unsigned long *)arg = (1024UL * 1024UL * 1024UL) / 512UL;
            return 0;
        }
        if (request == BLKGETSIZE64) {
            *(unsigned long long *)arg = 1024ULL * 1024ULL * 1024ULL;
            return 0;
        }
    }
    if (fd >= 0 && fd < (int)sizeof(fd_types) && fd_types[fd] == FD_TOUCH) {
        int result = touch_ioctl(request, arg);
        if (result == 0) return 0;
    }
    return real_ioctl(fd, request, arg);
}
