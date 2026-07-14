// Minimal layer-shell protocol header
// Generated manually for this exploration project
// Based on wlr-layer-shell-unstable-v1.xml

#ifndef WAYLAND_LAYER_SHELL_H
#define WAYLAND_LAYER_SHELL_H

#include <wayland-client.h>

// Forward declare interfaces
struct zwlr_layer_shell_v1;
struct zwlr_layer_surface_v1;

// Layer shell interface
#define ZWLR_LAYER_SHELL_V1_VERSION 4

enum zwlr_layer_shell_v1_layer {
    ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND = 0,
    ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM = 1,
    ZWLR_LAYER_SHELL_V1_LAYER_TOP = 2,
    ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY = 3,
};

struct zwlr_layer_shell_v1_interface {
    struct wl_interface *interface;
    int (*version)(void);
};

struct zwlr_layer_surface_v1_interface {
    struct wl_interface *interface;
    int (*version)(void);
};

// Anchor bits
enum zwlr_layer_surface_v1_anchor {
    ZWLR_LAYER_SURFACE_V1_ANCHOR_NONE = 0,
    ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP = 1,
    ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM = 2,
    ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT = 4,
    ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT = 8,
};

// Function declarations
#ifdef __cplusplus
extern "C" {
#endif

// Bind layer-shell from registry
struct zwlr_layer_shell_v1 *bind_layer_shell(struct wl_registry *registry, uint32_t name);
struct zwlr_layer_surface_v1 *create_layer_surface(
    struct zwlr_layer_shell_v1 *shell,
    struct wl_surface *surface,
    struct wl_output *output,
    enum zwlr_layer_shell_v1_layer layer,
    const char *name_space
);

// Layer surface operations
void zwlr_layer_surface_v1_set_anchor(
    struct zwlr_layer_surface_v1 *surface,
    uint32_t anchor
);

void zwlr_layer_surface_v1_set_size(
    struct zwlr_layer_surface_v1 *surface,
    uint32_t width,
    uint32_t height
);

void zwlr_layer_surface_v1_set_exclusive_zone(
    struct zwlr_layer_surface_v1 *surface,
    int32_t zone
);

void zwlr_layer_surface_v1_set_keyboard_interactivity(
    struct zwlr_layer_surface_v1 *surface,
    uint32_t mode
);

void zwlr_layer_surface_v1_add_listener(
    struct zwlr_layer_surface_v1 *surface,
    const struct zwlr_layer_surface_v1_listener *listener,
    void *data
);

void zwlr_layer_surface_v1_destroy(struct zwlr_layer_surface_v1 *surface);
void zwlr_layer_shell_v1_destroy(struct zwlr_layer_shell_v1 *shell);

// Listener structure
struct zwlr_layer_surface_v1_listener {
    void (*configure)(void *data, struct zwlr_layer_surface_v1 *surface,
                      uint32_t serial, uint32_t width, uint32_t height);
    void (*closed)(void *data, struct zwlr_layer_surface_v1 *surface);
};

#ifdef __cplusplus
}
#endif

#endif // WAYLAND_LAYER_SHELL_H
