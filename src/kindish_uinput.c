#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;

static void stop_running(int signal_number) {
    (void)signal_number;
    running = 0;
}

static void checked_ioctl(int fd, unsigned long request, int value, const char *what) {
    if (ioctl(fd, request, value) < 0) {
        perror(what);
        exit(EXIT_FAILURE);
    }
}

int main(void) {
    int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) {
        perror("open /dev/uinput");
        return EXIT_FAILURE;
    }

    checked_ioctl(fd, UI_SET_EVBIT, EV_KEY, "UI_SET_EVBIT EV_KEY");
    checked_ioctl(fd, UI_SET_KEYBIT, BTN_TOUCH, "UI_SET_KEYBIT BTN_TOUCH");
    checked_ioctl(fd, UI_SET_EVBIT, EV_ABS, "UI_SET_EVBIT EV_ABS");
    checked_ioctl(fd, UI_SET_ABSBIT, ABS_X, "UI_SET_ABSBIT ABS_X");
    checked_ioctl(fd, UI_SET_ABSBIT, ABS_Y, "UI_SET_ABSBIT ABS_Y");
    checked_ioctl(fd, UI_SET_ABSBIT, ABS_MT_SLOT, "UI_SET_ABSBIT ABS_MT_SLOT");
    checked_ioctl(fd, UI_SET_ABSBIT, ABS_MT_TRACKING_ID, "UI_SET_ABSBIT ABS_MT_TRACKING_ID");
    checked_ioctl(fd, UI_SET_ABSBIT, ABS_MT_POSITION_X, "UI_SET_ABSBIT ABS_MT_POSITION_X");
    checked_ioctl(fd, UI_SET_ABSBIT, ABS_MT_POSITION_Y, "UI_SET_ABSBIT ABS_MT_POSITION_Y");

    struct uinput_user_dev device;
    memset(&device, 0, sizeof(device));
    snprintf(device.name, UINPUT_MAX_NAME_SIZE, "kindish-zforce");
    device.id.bustype = BUS_USB;
    device.id.vendor = 0x1949;
    device.id.product = 0x9981;
    device.id.version = 1;
    device.absmin[ABS_X] = 0;
    device.absmax[ABS_X] = 1071;
    device.absmin[ABS_Y] = 0;
    device.absmax[ABS_Y] = 1447;
    device.absmin[ABS_MT_SLOT] = 0;
    device.absmax[ABS_MT_SLOT] = 9;
    device.absmin[ABS_MT_TRACKING_ID] = 0;
    device.absmax[ABS_MT_TRACKING_ID] = 65535;
    device.absmin[ABS_MT_POSITION_X] = 0;
    device.absmax[ABS_MT_POSITION_X] = 1071;
    device.absmin[ABS_MT_POSITION_Y] = 0;
    device.absmax[ABS_MT_POSITION_Y] = 1447;

    if (write(fd, &device, sizeof(device)) != (ssize_t)sizeof(device)) {
        perror("write uinput_user_dev");
        close(fd);
        return EXIT_FAILURE;
    }
    if (ioctl(fd, UI_DEV_CREATE) < 0) {
        perror("UI_DEV_CREATE");
        close(fd);
        return EXIT_FAILURE;
    }

    signal(SIGTERM, stop_running);
    signal(SIGINT, stop_running);
    while (running) {
        pause();
    }

    ioctl(fd, UI_DEV_DESTROY);
    close(fd);
    return EXIT_SUCCESS;
}
