#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define INPUT_DEVICE_NAME "gpio-keys"
#define MAX_INPUT_DEVICES 32

static bool device_has_name(int index, const char *expected)
{
    char path[128];
    char name[128];
    FILE *file;

    snprintf(path, sizeof(path),
             "/sys/class/input/event%d/device/name", index);
    file = fopen(path, "r");
    if (file == NULL) {
        return false;
    }
    if (fgets(name, sizeof(name), file) == NULL) {
        fclose(file);
        return false;
    }
    fclose(file);
    name[strcspn(name, "\r\n")] = '\0';
    return strcmp(name, expected) == 0;
}

static int open_power_button(void)
{
    char path[64];
    int index;

    for (index = 0; index < MAX_INPUT_DEVICES; ++index) {
        int descriptor;

        if (!device_has_name(index, INPUT_DEVICE_NAME)) {
            continue;
        }
        snprintf(path, sizeof(path), "/dev/input/event%d", index);
        descriptor = open(path, O_RDONLY | O_CLOEXEC);
        if (descriptor >= 0) {
            return descriptor;
        }
    }
    return -1;
}

static void notify_powerd(void)
{
    pid_t child = fork();

    if (child == 0) {
        execl("/usr/bin/lipc-set-prop", "lipc-set-prop",
              "com.lab126.powerd", "powerButton", "1", NULL);
        _exit(127);
    }
    if (child > 0) {
        while (waitpid(child, NULL, 0) < 0 && errno == EINTR) {
        }
    }
}

int main(void)
{
    struct input_event event;
    int descriptor = open_power_button();
    int grab = 1;

    if (descriptor < 0) {
        perror("kindish-power-button: gpio-keys");
        return EXIT_FAILURE;
    }

    /* Amazon hardware reports the button through a board-specific HAL.  Own
     * QEMU's generic evdev node so Xorg cannot consume the replacement event. */
    if (ioctl(descriptor, EVIOCGRAB, &grab) < 0) {
        perror("kindish-power-button: EVIOCGRAB");
        close(descriptor);
        return EXIT_FAILURE;
    }

    for (;;) {
        ssize_t count = read(descriptor, &event, sizeof(event));

        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count != (ssize_t)sizeof(event)) {
            break;
        }
        if (event.type == EV_KEY && event.code == KEY_POWER &&
            event.value == 1) {
            notify_powerd();
        }
    }

    close(descriptor);
    return EXIT_FAILURE;
}
