#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/timerfd.h>
#include <sys/poll.h>
#include <time.h>
#include <linux/input-event-codes.h>

#include <wayland-client.h>
#include <cairo/cairo.h>
#include <pango/pangocairo.h>
#include <glib.h>

#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

#include "shm.h"
#include "toplevel.h"
#include "render.h"
#include "widget.h"
#include "widgets.h"
#include "menu.h"
#include "dock-render.h"

static struct wl_display *display = NULL;
static struct wl_registry *registry = NULL;
static struct wl_compositor *compositor = NULL;
static struct wl_shm *shm = NULL;
static struct zwlr_layer_shell_v1 *layer_shell = NULL;
static struct zwlr_foreign_toplevel_manager_v1 *toplevel_manager = NULL;
static struct wl_seat *seat = NULL;
static struct wl_pointer *pointer = NULL;

static struct toplevel_info toplevels[MAX_TOPLEVELS];
static int toplevel_count = 0;

static widget_t **widgets = NULL;
static int widget_count = 0;
static panel_ctx_t pctx;
static int widget_x[64];

static int pointer_x = 0, pointer_y = 0;
static struct wl_surface *pointer_surface = NULL;
static int dock_hover_idx = -1;

#define MAX_OUTPUTS 8

struct panel {
  struct wl_surface *surface;
  struct zwlr_layer_surface_v1 *layer_surface;
  int32_t width, height;
  uint32_t scale;
  struct wl_callback *frame_cb;
  bool dirty;
  bool running;
  cairo_surface_t *cairo_surface;
  cairo_t *cairo_cr;
  unsigned char *shm_data;
  struct wl_buffer *buffer;
  int32_t buf_width, buf_height;
  size_t buf_size;
  int timer_fd;
};

struct dock {
  struct wl_surface *surface;
  struct zwlr_layer_surface_v1 *layer_surface;
  int32_t width, height;
  uint32_t scale;
  struct wl_callback *frame_cb;
  bool dirty;
  bool running;
  cairo_surface_t *cairo_surface;
  cairo_t *cairo_cr;
  unsigned char *shm_data;
  struct wl_buffer *buffer;
  int32_t buf_width, buf_height;
  size_t buf_size;
};

static struct panel panel;
static struct dock dock;

static void mark_dirty(void) { panel.dirty = true; dock.dirty = true; }

static void toplevel_handle_title(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle, const char *title) {
  struct toplevel_info *info = (struct toplevel_info*)data;
  strncpy(info->title, title, sizeof(info->title) - 1);
  info->title[sizeof(info->title) - 1] = 0;
  mark_dirty();
}
static void toplevel_handle_app_id(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle, const char *app_id) {
  struct toplevel_info *info = (struct toplevel_info*)data;
  strncpy(info->app_id, app_id, sizeof(info->app_id) - 1);
  info->app_id[sizeof(info->app_id) - 1] = 0;
  mark_dirty();
}
static void toplevel_handle_output_enter(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_output *output) {}
static void toplevel_handle_output_leave(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_output *output) {}
static void toplevel_handle_state(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_array *state) {
  struct toplevel_info *info = (struct toplevel_info*)data;
  info->focused = info->minimized = info->maximized = false;
  uint32_t *s = (uint32_t*)state->data;
  uint32_t *end = s + state->size / sizeof(uint32_t);
  while (s < end) {
    if (*s == ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED) info->focused = true;
    if (*s == ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MINIMIZED) info->minimized = true;
    if (*s == ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MAXIMIZED) info->maximized = true;
    s++;
  }
  mark_dirty();
}
static void toplevel_handle_done(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle) {
  mark_dirty();
}
static void toplevel_handle_closed(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle) {
  int idx = toplevel_find(toplevels, toplevel_count, (void*)handle);
  if (idx >= 0) toplevel_remove_at(toplevels, &toplevel_count, idx);
  mark_dirty();
}
static void toplevel_handle_parent(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle,
    struct zwlr_foreign_toplevel_handle_v1 *parent) {}

static const struct zwlr_foreign_toplevel_handle_v1_listener toplevel_handle_listener = {
  .title = toplevel_handle_title,
  .app_id = toplevel_handle_app_id,
  .output_enter = toplevel_handle_output_enter,
  .output_leave = toplevel_handle_output_leave,
  .state = toplevel_handle_state,
  .done = toplevel_handle_done,
  .closed = toplevel_handle_closed,
  .parent = toplevel_handle_parent,
};

static void toplevel_manager_toplevel(void *data,
    struct zwlr_foreign_toplevel_manager_v1 *manager,
    struct zwlr_foreign_toplevel_handle_v1 *handle) {
  struct toplevel_info *info = &toplevels[toplevel_add(toplevels, &toplevel_count, (void*)handle)];
  zwlr_foreign_toplevel_handle_v1_add_listener(handle, &toplevel_handle_listener, info);
  mark_dirty();
}
static void toplevel_manager_finished(void *data,
    struct zwlr_foreign_toplevel_manager_v1 *manager) {}

static const struct zwlr_foreign_toplevel_manager_v1_listener toplevel_manager_listener = {
  .toplevel = toplevel_manager_toplevel,
  .finished = toplevel_manager_finished,
};

static void pointer_enter(void *data, struct wl_pointer *p,
    uint32_t serial, struct wl_surface *surface, wl_fixed_t x, wl_fixed_t y) {
  pointer_surface = surface;
  pointer_x = wl_fixed_to_int(x);
  pointer_y = wl_fixed_to_int(y);
  if (menu_is_open() && surface == menu_surface()) {
    menu_on_enter(surface, x, y);
    return;
  }
  if (surface == dock.surface) {
    dock_hover_idx = dock_icon_at(dock.width, dock.height,
                                  toplevels, toplevel_count, pointer_x);
    dock.dirty = true;
  }
}
static void pointer_leave(void *data, struct wl_pointer *p,
    uint32_t serial, struct wl_surface *surface) {
  if (surface == dock.surface) {
    dock_hover_idx = -1;
    dock.dirty = true;
  }
}
static void pointer_motion(void *data, struct wl_pointer *p,
    uint32_t time, wl_fixed_t x, wl_fixed_t y) {
  int nx = wl_fixed_to_int(x), ny = wl_fixed_to_int(y);
  if (nx == pointer_x && ny == pointer_y) return;
  pointer_x = nx; pointer_y = ny;
  if (menu_is_open()) {
    menu_on_motion(x, y);
  } else if (pointer_surface == dock.surface) {
    int idx = dock_icon_at(dock.width, dock.height,
                           toplevels, toplevel_count, pointer_x);
    if (idx != dock_hover_idx) {
      dock_hover_idx = idx;
      dock.dirty = true;
    }
  }
}
static void pointer_button(void *data, struct wl_pointer *p,
    uint32_t serial, uint32_t time, uint32_t button, uint32_t state) {
  if (state != WL_POINTER_BUTTON_STATE_PRESSED || button != BTN_LEFT)
    return;

  if (menu_is_open()) {
    if (pointer_surface == menu_surface())
      menu_on_button(button, state, pointer_x, pointer_y);
    else
      menu_close();
    mark_dirty();
    return;
  }

  if (pointer_surface == panel.surface) {
    for (int i = 0; i < widget_count && i < 64; i++) {
      if (pointer_x >= widget_x[i] &&
          pointer_x < widget_x[i] + widgets[i]->cached_w) {
        if (widgets[i]->menu_open)
          widgets[i]->menu_open(widgets[i], widget_x[i], pointer_y);
        else if (widgets[i]->click)
          widgets[i]->click(widgets[i], button, pointer_x - widget_x[i], pointer_y);
        mark_dirty();
        return;
      }
    }
    return;
  }

  if (pointer_surface == dock.surface) {
    if (dock_hover_idx < 0 || dock_hover_idx >= toplevel_count || !seat)
      return;
    struct toplevel_info *info = &toplevels[dock_hover_idx];
    struct zwlr_foreign_toplevel_handle_v1 *handle =
      (struct zwlr_foreign_toplevel_handle_v1*)info->handle;
    if (info->focused)
      zwlr_foreign_toplevel_handle_v1_set_minimized(handle);
    else
      zwlr_foreign_toplevel_handle_v1_activate(handle, seat);
    dock.dirty = true;
  }
}
static void pointer_axis(void *data, struct wl_pointer *p,
    uint32_t time, uint32_t axis, wl_fixed_t value) {}
static void pointer_frame(void *data, struct wl_pointer *p) {}
static void pointer_axis_source(void *data, struct wl_pointer *p,
    uint32_t axis_source) {}
static void pointer_axis_stop(void *data, struct wl_pointer *p,
    uint32_t time, uint32_t axis) {}
static void pointer_axis_discrete(void *data, struct wl_pointer *p,
    uint32_t axis, int32_t discrete) {}

static const struct wl_pointer_listener pointer_listener = {
  .enter = pointer_enter,
  .leave = pointer_leave,
  .motion = pointer_motion,
  .button = pointer_button,
  .axis = pointer_axis,
  .frame = pointer_frame,
  .axis_source = pointer_axis_source,
  .axis_stop = pointer_axis_stop,
  .axis_discrete = pointer_axis_discrete,
};

static void seat_capabilities(void *data, struct wl_seat *s, uint32_t caps) {
  if (caps & WL_SEAT_CAPABILITY_POINTER) {
    if (!pointer) {
      pointer = wl_seat_get_pointer(s);
      wl_pointer_add_listener(pointer, &pointer_listener, NULL);
    }
  }
}
static void seat_name(void *data, struct wl_seat *s, const char *name) {}

static const struct wl_seat_listener seat_listener = {
  .capabilities = seat_capabilities,
  .name = seat_name,
};

static void registry_global(void *data, struct wl_registry *reg, uint32_t name,
                            const char *iface, uint32_t version) {
  if (!strcmp(iface, "wl_compositor"))
    compositor = (struct wl_compositor*)wl_registry_bind(reg, name, &wl_compositor_interface, 4);
  else if (!strcmp(iface, "wl_shm"))
    shm = (struct wl_shm*)wl_registry_bind(reg, name, &wl_shm_interface, 1);
  else if (!strcmp(iface, zwlr_layer_shell_v1_interface.name))
    layer_shell = (struct zwlr_layer_shell_v1*)wl_registry_bind(reg, name, &zwlr_layer_shell_v1_interface, 1);
  else if (!strcmp(iface, zwlr_foreign_toplevel_manager_v1_interface.name)) {
    toplevel_manager = (struct zwlr_foreign_toplevel_manager_v1*)wl_registry_bind(reg, name, &zwlr_foreign_toplevel_manager_v1_interface, 3);
    zwlr_foreign_toplevel_manager_v1_add_listener(toplevel_manager, &toplevel_manager_listener, NULL);
  }
  else if (!strcmp(iface, "wl_seat")) {
    seat = (struct wl_seat*)wl_registry_bind(reg, name, &wl_seat_interface, 7);
    wl_seat_add_listener(seat, &seat_listener, NULL);
  }
}
static void registry_global_remove(void *data, struct wl_registry *reg, uint32_t name) {}

static const struct wl_registry_listener registry_listener = {
  registry_global,
  registry_global_remove
};

static void render_panel(struct panel *p) {
  int w = p->width * (int)p->scale;
  int h = p->height * (int)p->scale;
  if (w <= 0 || h <= 0) return;

  int stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, w);
  size_t size = (size_t)stride * (size_t)h;

  if (p->buffer && (p->buf_width != w || p->buf_height != h)) {
    wl_buffer_destroy(p->buffer); p->buffer = NULL;
    cairo_destroy(p->cairo_cr); p->cairo_cr = NULL;
    cairo_surface_destroy(p->cairo_surface); p->cairo_surface = NULL;
    munmap(p->shm_data, p->buf_size);
    p->shm_data = NULL;
  }

  if (!p->buffer) {
    int fd = create_shm_fd(size);
    if (fd < 0) return;
    p->shm_data = (unsigned char*)mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
    if (p->shm_data == MAP_FAILED) { close(fd); return; }
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, (int32_t)size);
    p->buffer = wl_shm_pool_create_buffer(pool, 0, w, h, stride, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    p->cairo_surface = cairo_image_surface_create_for_data(p->shm_data, CAIRO_FORMAT_ARGB32, w, h, stride);
    p->cairo_cr = cairo_create(p->cairo_surface);
    p->buf_width = w;
    p->buf_height = h;
    p->buf_size = size;
  }

  cairo_pattern_t *grad = cairo_pattern_create_linear(0, 0, 0, h);
  cairo_pattern_add_color_stop_rgba(grad, 0.0, 0.10, 0.11, 0.15, 0.97);
  cairo_pattern_add_color_stop_rgba(grad, 1.0, 0.04, 0.05, 0.07, 0.97);
  cairo_set_source(p->cairo_cr, grad);
  cairo_paint(p->cairo_cr);
  cairo_pattern_destroy(grad);

  cairo_set_source_rgba(p->cairo_cr, 0.20, 0.61, 0.86, 0.9);
  cairo_rectangle(p->cairo_cr, 0, h - 2 * (int)p->scale, w, 2 * (int)p->scale);
  cairo_fill(p->cairo_cr);

  int pad = 12 * (int)p->scale;
  widget_list_width(widgets, widget_count, h, pad);
  int x0 = 10 * (int)p->scale;

  int left_w = 0, right_w = 0;
  for (int i = 0; i < widget_count && i < 64; i++) {
    if (widgets[i]->side) right_w += widgets[i]->cached_w + pad;
    else left_w += widgets[i]->cached_w + pad;
  }
  if (left_w) left_w -= pad;
  if (right_w) right_w -= pad;

  int x = x0;
  for (int i = 0; i < widget_count && i < 64; i++) {
    if (widgets[i]->side) continue;
    widget_x[i] = x;
    x += widgets[i]->cached_w + pad;
  }
  int rx = w - x0 - right_w;
  if (rx < x) rx = x;
  for (int i = 0; i < widget_count && i < 64; i++) {
    if (!widgets[i]->side) continue;
    widget_x[i] = rx;
    rx += widgets[i]->cached_w + pad;
  }

  for (int i = 0; i < widget_count && i < 64; i++)
    widgets[i]->draw(widgets[i], p->cairo_cr, widget_x[i], 0, h);

  cairo_surface_flush(p->cairo_surface);
}

static void render_dock(struct dock *d) {
  int w = d->width * (int)d->scale;
  int h = d->height * (int)d->scale;
  if (w <= 0 || h <= 0) return;

  int stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, w);
  size_t size = (size_t)stride * (size_t)h;

  if (d->buffer && (d->buf_width != w || d->buf_height != h)) {
    wl_buffer_destroy(d->buffer); d->buffer = NULL;
    cairo_destroy(d->cairo_cr); d->cairo_cr = NULL;
    cairo_surface_destroy(d->cairo_surface); d->cairo_surface = NULL;
    munmap(d->shm_data, d->buf_size);
    d->shm_data = NULL;
  }

  if (!d->buffer) {
    int fd = create_shm_fd(size);
    if (fd < 0) return;
    d->shm_data = (unsigned char*)mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
    if (d->shm_data == MAP_FAILED) { close(fd); return; }
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, (int32_t)size);
    d->buffer = wl_shm_pool_create_buffer(pool, 0, w, h, stride, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    d->cairo_surface = cairo_image_surface_create_for_data(d->shm_data, CAIRO_FORMAT_ARGB32, w, h, stride);
    d->cairo_cr = cairo_create(d->cairo_surface);
    d->buf_width = w;
    d->buf_height = h;
    d->buf_size = size;
  }

  dock_draw(d->cairo_cr, w, h, toplevels, toplevel_count, dock_hover_idx);
  cairo_surface_flush(d->cairo_surface);
}

static void panel_configure(void *data,
    struct zwlr_layer_surface_v1 *surface, uint32_t serial,
    uint32_t w, uint32_t h) {
  if ((int)w != panel.width || (int)h != panel.height) {
    panel.width = w;
    panel.height = h;
    panel.dirty = true;
  }
  zwlr_layer_surface_v1_ack_configure(surface, serial);
  zwlr_layer_surface_v1_set_size(surface, 0, (uint32_t)panel.height);
}
static void panel_closed(void *data,
    struct zwlr_layer_surface_v1 *surface) {
  panel.running = false;
}
static const struct zwlr_layer_surface_v1_listener panel_surface_listener = {
  .configure = panel_configure,
  .closed = panel_closed,
};

static void dock_configure(void *data,
    struct zwlr_layer_surface_v1 *surface, uint32_t serial,
    uint32_t w, uint32_t h) {
  if ((int)w != dock.width || (int)h != dock.height) {
    dock.width = w;
    dock.height = h;
    dock.dirty = true;
  }
  zwlr_layer_surface_v1_ack_configure(surface, serial);
  zwlr_layer_surface_v1_set_size(surface, 0, (uint32_t)dock.height);
}
static void dock_closed(void *data,
    struct zwlr_layer_surface_v1 *surface) {
  dock.running = false;
}
static const struct zwlr_layer_surface_v1_listener dock_surface_listener = {
  .configure = dock_configure,
  .closed = dock_closed,
};

static void panel_frame_done(void *data, struct wl_callback *cb, uint32_t time) {
  wl_callback_destroy(cb);
  panel.frame_cb = NULL;
}
static const struct wl_callback_listener panel_frame_listener = {
  .done = panel_frame_done,
};

static void dock_frame_done(void *data, struct wl_callback *cb, uint32_t time) {
  wl_callback_destroy(cb);
  dock.frame_cb = NULL;
}
static const struct wl_callback_listener dock_frame_listener = {
  .done = dock_frame_done,
};

static void reload_config(void) {
  if (widgets) { widget_list_free(widgets, widget_count); widgets = NULL; }
  char *cfg_path = g_build_filename(g_get_user_config_dir(),
      "fltk-panel", "widgets.conf", NULL);
  widgets = widget_list_load(cfg_path, &widget_count);
  g_free(cfg_path);
  if (!widgets)
    widgets = widget_list_create_default(&widget_count);
  for (int i = 0; i < widget_count; i++)
    widgets[i]->ctx = &pctx;
  mark_dirty();
}

static void shell_quit(void) { panel.running = false; dock.running = false; }
static void shell_restart(void) {
  system("fltk-cpp-shell &");
  panel.running = false;
  dock.running = false;
}

int main(int argc, char **argv) {
  setbuf(stdout, NULL);
  setbuf(stderr, NULL);
  memset(&panel, 0, sizeof(panel));
  memset(&dock, 0, sizeof(dock));
  panel.running = dock.running = true;
  panel.width = 0;   panel.height = 36;   panel.scale = 1;  panel.timer_fd = -1;
  dock.width = 0;    dock.height = DOCK_HEIGHT; dock.scale = 1; dock_hover_idx = -1;

  g_widget_reload_cb = reload_config;
  g_widget_quit_cb = shell_quit;
  g_widget_restart_cb = shell_restart;

  display = wl_display_connect(NULL);
  if (!display) {
    fprintf(stderr, "fltk-cpp-shell: failed to connect to Wayland display\n");
    return 1;
  }

  registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &registry_listener, NULL);
  wl_display_roundtrip(display);
  wl_display_roundtrip(display);

  if (!compositor || !shm || !layer_shell) {
    fprintf(stderr, "fltk-cpp-shell: missing required Wayland globals\n");
    return 1;
  }

  if (toplevel_manager) {
    wl_display_roundtrip(display);
    fprintf(stderr, "fltk-cpp-shell: toplevel management enabled\n");
  } else {
    fprintf(stderr, "fltk-cpp-shell: no toplevel manager (taskbar/dock disabled)\n");
  }

  pctx.toplevels = toplevels;
  pctx.count = &toplevel_count;
  pctx.seat = seat;
  char *cfg_path = g_build_filename(g_get_user_config_dir(),
      "fltk-panel", "widgets.conf", NULL);
  widgets = widget_list_load(cfg_path, &widget_count);
  g_free(cfg_path);
  if (!widgets) {
    fprintf(stderr, "fltk-cpp-shell: no widget config, using built-in defaults\n");
    widgets = widget_list_create_default(&widget_count);
  }
  for (int i = 0; i < widget_count; i++)
    widgets[i]->ctx = &pctx;

  panel.surface = wl_compositor_create_surface(compositor);
  panel.layer_surface = zwlr_layer_shell_v1_get_layer_surface(
      layer_shell, panel.surface, NULL,
      ZWLR_LAYER_SHELL_V1_LAYER_TOP, "fltk-panel");
  zwlr_layer_surface_v1_add_listener(panel.layer_surface, &panel_surface_listener, NULL);
  {
    uint32_t anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP
                    | ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT
                    | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    zwlr_layer_surface_v1_set_anchor(panel.layer_surface, anchor);
    zwlr_layer_surface_v1_set_size(panel.layer_surface, 0, 36);
    zwlr_layer_surface_v1_set_exclusive_zone(panel.layer_surface, 36);
    zwlr_layer_surface_v1_set_keyboard_interactivity(panel.layer_surface, false);
    wl_surface_commit(panel.surface);
  }

  dock.surface = wl_compositor_create_surface(compositor);
  dock.layer_surface = zwlr_layer_shell_v1_get_layer_surface(
      layer_shell, dock.surface, NULL,
      ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM, "fltk-dock");
  zwlr_layer_surface_v1_add_listener(dock.layer_surface, &dock_surface_listener, NULL);
  {
    uint32_t anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM
                    | ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT
                    | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    zwlr_layer_surface_v1_set_anchor(dock.layer_surface, anchor);
    zwlr_layer_surface_v1_set_size(dock.layer_surface, 0, DOCK_HEIGHT);
    zwlr_layer_surface_v1_set_exclusive_zone(dock.layer_surface, DOCK_HEIGHT);
    zwlr_layer_surface_v1_set_keyboard_interactivity(dock.layer_surface, false);
    wl_surface_commit(dock.surface);
  }

  int ret = 0;
  while ((panel.width == 0 || dock.width == 0) && ret >= 0 && !wl_display_get_error(display))
    ret = wl_display_dispatch(display);

  if (wl_display_get_error(display)) {
    fprintf(stderr, "fltk-cpp-shell: Wayland protocol error during init\n");
    panel.running = dock.running = false;
  }

  if (panel.width == 0) panel.width = 1920;
  if (panel.height == 0) panel.height = 36;
  if (dock.width == 0) dock.width = 1920;
  if (dock.height == 0) dock.height = DOCK_HEIGHT;

  pctx.screen_w = panel.width;
  menu_init(display, compositor, shm, layer_shell, panel.scale, panel.width);

  fprintf(stderr, "fltk-cpp-shell: surfaces created (panel %dx%d, dock %dx%d)\n",
          panel.width, panel.height, dock.width, dock.height);

  panel.timer_fd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK);
  if (panel.timer_fd >= 0) {
    struct itimerspec ts = {
      .it_interval = { .tv_sec = 1, .tv_nsec = 0 },
      .it_value = { .tv_sec = 1, .tv_nsec = 0 },
    };
    timerfd_settime(panel.timer_fd, 0, &ts, NULL);
  }

  panel.dirty = dock.dirty = true;

  int wl_fd = wl_display_get_fd(display);
  struct pollfd pfds[2];

  while (panel.running && dock.running) {
    if (panel.dirty) {
      render_panel(&panel);
      wl_surface_attach(panel.surface, panel.buffer, 0, 0);
      wl_surface_damage_buffer(panel.surface, 0, 0, panel.buf_width, panel.buf_height);
      if (panel.frame_cb) wl_callback_destroy(panel.frame_cb);
      panel.frame_cb = wl_surface_frame(panel.surface);
      wl_callback_add_listener(panel.frame_cb, &panel_frame_listener, NULL);
      wl_surface_commit(panel.surface);
      panel.dirty = false;
    }

    if (dock.dirty) {
      render_dock(&dock);
      wl_surface_attach(dock.surface, dock.buffer, 0, 0);
      wl_surface_damage_buffer(dock.surface, 0, 0, dock.buf_width, dock.buf_height);
      if (dock.frame_cb) wl_callback_destroy(dock.frame_cb);
      dock.frame_cb = wl_surface_frame(dock.surface);
      wl_callback_add_listener(dock.frame_cb, &dock_frame_listener, NULL);
      wl_surface_commit(dock.surface);
      dock.dirty = false;
    }

    menu_commit();
    wl_display_flush(display);

    pfds[0].fd = wl_fd;
    pfds[0].events = POLLIN;
    pfds[1].fd = panel.timer_fd;
    pfds[1].events = POLLIN;

    if (poll(pfds, 2, 3000) > 0) {
      if (pfds[0].revents & POLLIN)
        wl_display_dispatch(display);
      if (pfds[1].revents & POLLIN) {
        uint64_t exp;
        read(panel.timer_fd, &exp, sizeof(exp));
        widget_list_update(widgets, widget_count);
        panel.dirty = true;
      }
    } else {
      wl_display_dispatch_pending(display);
    }
  }

  if (panel.buffer) wl_buffer_destroy(panel.buffer);
  if (panel.cairo_cr) cairo_destroy(panel.cairo_cr);
  if (panel.cairo_surface) cairo_surface_destroy(panel.cairo_surface);
  if (panel.shm_data) munmap(panel.shm_data, panel.buf_size);
  if (panel.frame_cb) wl_callback_destroy(panel.frame_cb);
  if (panel.layer_surface) zwlr_layer_surface_v1_destroy(panel.layer_surface);
  if (panel.surface) wl_surface_destroy(panel.surface);

  if (dock.buffer) wl_buffer_destroy(dock.buffer);
  if (dock.cairo_cr) cairo_destroy(dock.cairo_cr);
  if (dock.cairo_surface) cairo_surface_destroy(dock.cairo_surface);
  if (dock.shm_data) munmap(dock.shm_data, dock.buf_size);
  if (dock.frame_cb) wl_callback_destroy(dock.frame_cb);
  if (dock.layer_surface) zwlr_layer_surface_v1_destroy(dock.layer_surface);
  if (dock.surface) wl_surface_destroy(dock.surface);

  dock_icon_clear_cache();
  widget_list_free(widgets, widget_count);
  menu_close();
  if (display) wl_display_disconnect(display);

  fprintf(stderr, "fltk-cpp-shell: exiting\n");
  return 0;
}
