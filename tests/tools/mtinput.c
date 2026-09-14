// Test helper: sends pointer and keyboard input to a headless KWin through
// the fake input protocol. KWin must run with KWIN_WAYLAND_NO_PERMISSION_CHECKS=1.
//
//   mtinput move X Y | down BTN | up BTN | click BTN | wheel N | key CODE | press CODE | release CODE | sleep MS ...
//
// BTN is left, right or middle. N is wheel notches, negative scrolls up.
// CODE is a Linux key code (125 is Meta, 42 Shift, 29 Ctrl).
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wayland-client.h>
#include "fake-input-client.h"

static struct org_kde_kwin_fake_input *fake;

static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version)
{
    if (strcmp(interface, org_kde_kwin_fake_input_interface.name) == 0) {
        fake = wl_registry_bind(registry, name, &org_kde_kwin_fake_input_interface, version < 4 ? version : 4);
    }
}

static void global_remove(void *data, struct wl_registry *registry, uint32_t name)
{
}

static const struct wl_registry_listener listener = { global, global_remove };

static unsigned button(const char *name)
{
    if (strcmp(name, "right") == 0) return 273;
    if (strcmp(name, "middle") == 0) return 274;
    return 272;
}

static void pause_ms(long ms)
{
    struct timespec ts = { ms / 1000, (ms % 1000) * 1000000L };
    nanosleep(&ts, NULL);
}

int main(int argc, char **argv)
{
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "mtinput: no wayland display\n");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &listener, NULL);
    wl_display_roundtrip(display);
    if (!fake) {
        fprintf(stderr, "mtinput: the compositor has no org_kde_kwin_fake_input\n");
        return 1;
    }
    org_kde_kwin_fake_input_authenticate(fake, "mtinput", "MindTile tests");
    wl_display_roundtrip(display);

    for (int i = 1; i < argc; i++) {
        const char *cmd = argv[i];
        if (strcmp(cmd, "move") == 0 && i + 2 < argc) {
            org_kde_kwin_fake_input_pointer_motion_absolute(fake, wl_fixed_from_double(atof(argv[i + 1])), wl_fixed_from_double(atof(argv[i + 2])));
            i += 2;
        } else if (strcmp(cmd, "down") == 0 && i + 1 < argc) {
            org_kde_kwin_fake_input_button(fake, button(argv[++i]), 1);
        } else if (strcmp(cmd, "up") == 0 && i + 1 < argc) {
            org_kde_kwin_fake_input_button(fake, button(argv[++i]), 0);
        } else if (strcmp(cmd, "click") == 0 && i + 1 < argc) {
            unsigned b = button(argv[++i]);
            org_kde_kwin_fake_input_button(fake, b, 1);
            wl_display_roundtrip(display);
            pause_ms(40);
            org_kde_kwin_fake_input_button(fake, b, 0);
        } else if (strcmp(cmd, "wheel") == 0 && i + 1 < argc) {
            org_kde_kwin_fake_input_axis(fake, 0, wl_fixed_from_double(15.0 * atof(argv[++i])));
        } else if (strcmp(cmd, "press") == 0 && i + 1 < argc) {
            org_kde_kwin_fake_input_keyboard_key(fake, (uint32_t)atoi(argv[++i]), 1);
        } else if (strcmp(cmd, "release") == 0 && i + 1 < argc) {
            org_kde_kwin_fake_input_keyboard_key(fake, (uint32_t)atoi(argv[++i]), 0);
        } else if (strcmp(cmd, "key") == 0 && i + 1 < argc) {
            uint32_t code = (uint32_t)atoi(argv[++i]);
            org_kde_kwin_fake_input_keyboard_key(fake, code, 1);
            wl_display_roundtrip(display);
            pause_ms(30);
            org_kde_kwin_fake_input_keyboard_key(fake, code, 0);
        } else if (strcmp(cmd, "sleep") == 0 && i + 1 < argc) {
            wl_display_roundtrip(display);
            pause_ms(atol(argv[++i]));
        } else {
            fprintf(stderr, "mtinput: bad command %s\n", cmd);
            return 1;
        }
        wl_display_roundtrip(display);
        pause_ms(20);
    }
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    return 0;
}
