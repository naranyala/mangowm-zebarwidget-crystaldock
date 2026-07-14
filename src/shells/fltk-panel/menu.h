#pragma once
#include <wayland-client.h>
#include <stdbool.h>

struct wl_display;
struct wl_compositor;
struct wl_shm;
struct zwlr_layer_shell_v1;

typedef struct menu_item {
  char *label;
  char *detail;     // optional right-aligned text
  bool separator;   // draw a separator instead of a row
  char *cmd;        // shell command run on activate (optional)
  void (*activate)(void *arg);  // custom callback (optional)
  void *arg;
} menu_item_t;

void menu_init(struct wl_display *display, struct wl_compositor *compositor,
               struct wl_shm *shm, struct zwlr_layer_shell_v1 *layer_shell,
               int scale, int screen_w);

// anchor at (anchor_x, anchor_y); anchor_y is usually the panel height.
void menu_open(int anchor_x, int anchor_y,
               menu_item_t *items, int n, int screen_w);
void menu_close(void);
bool menu_is_open(void);
struct wl_surface *menu_surface(void);

// pointer routing (called from the global seat pointer listener)
void menu_on_enter(struct wl_surface *surface, wl_fixed_t x, wl_fixed_t y);
void menu_on_motion(wl_fixed_t x, wl_fixed_t y);
// returns true if the button press was consumed by the menu
bool menu_on_button(uint32_t button, uint32_t state, int mx, int my);

// commit a pending redraw (call once per main-loop iteration)
void menu_commit(void);
