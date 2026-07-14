#include "menu.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include <cairo/cairo.h>
#include <pango/pangocairo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <linux/input-event-codes.h>

#define ROW_H 22
#define PAD   10

static struct wl_display *g_display;
static struct wl_compositor *g_compositor;
static struct wl_shm *g_shm;
static struct zwlr_layer_shell_v1 *g_layer_shell;
static int g_scale = 1;
static int g_screen_w = 1920;

static bool g_open = false;
static struct wl_surface *g_surface = NULL;
static struct zwlr_layer_surface_v1 *g_layer = NULL;
static struct wl_buffer *g_buffer = NULL;
static cairo_surface_t *g_cairo_surface = NULL;
static cairo_t *g_cr = NULL;
static unsigned char *g_shm_data = NULL;
static int g_buf_w = 0, g_buf_h = 0, g_buf_size = 0;
static bool g_configured = false;
static bool g_dirty = false;

static menu_item_t *g_items = NULL;
static int g_n = 0;
static int g_w = 0, g_h = 0;
static int g_hover = -1;

static void layer_configure(void *data, struct zwlr_layer_surface_v1 *surface,
    uint32_t serial, uint32_t w, uint32_t h) {
  g_configured = true;
  zwlr_layer_surface_v1_ack_configure(surface, serial);
  zwlr_layer_surface_v1_set_size(surface, (uint32_t)g_w, (uint32_t)g_h);
}
static void layer_closed(void *data, struct zwlr_layer_surface_v1 *surface) {
  menu_close();
}
static const struct zwlr_layer_surface_v1_listener g_layer_listener = {
  .configure = layer_configure,
  .closed = layer_closed,
};

void menu_init(struct wl_display *display, struct wl_compositor *compositor,
               struct wl_shm *shm, struct zwlr_layer_shell_v1 *layer_shell,
               int scale, int screen_w) {
  g_display = display;
  g_compositor = compositor;
  g_shm = shm;
  g_layer_shell = layer_shell;
  g_scale = scale > 0 ? scale : 1;
  g_screen_w = screen_w > 0 ? screen_w : 1920;
}

void menu_close(void) {
  g_open = false;
  if (g_buffer) { wl_buffer_destroy(g_buffer); g_buffer = NULL; }
  if (g_cr) { cairo_destroy(g_cr); g_cr = NULL; }
  if (g_cairo_surface) { cairo_surface_destroy(g_cairo_surface); g_cairo_surface = NULL; }
  if (g_shm_data) { munmap(g_shm_data, g_buf_size); g_shm_data = NULL; }
  if (g_layer) { zwlr_layer_surface_v1_destroy(g_layer); g_layer = NULL; }
  if (g_surface) { wl_surface_destroy(g_surface); g_surface = NULL; }
  if (g_items) {
    for (int i = 0; i < g_n; i++) {
      free(g_items[i].label);
      free(g_items[i].detail);
      free(g_items[i].cmd);
    }
    free(g_items); g_items = NULL;
  }
  g_n = 0; g_hover = -1; g_configured = false; g_dirty = false;
  g_buf_w = g_buf_h = g_buf_size = 0;
}

static int create_shm_fd(size_t size) {
  int fd = memfd_create("fltk-menu", 0);
  if (fd < 0) return -1;
  if (ftruncate(fd, (off_t)size) < 0) { close(fd); return -1; }
  return fd;
}

// measure label/detail widths to size the menu
static void measure(menu_item_t *items, int n, int *out_w) {
  cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1);
  cairo_t *cr = cairo_create(s);
  PangoLayout *layout = pango_cairo_create_layout(cr);
  PangoFontDescription *font = pango_font_description_from_string("Sans 10");
  pango_layout_set_font_description(layout, font);
  int maxw = 0;
  for (int i = 0; i < n; i++) {
    int w = 0;
    if (!items[i].separator && items[i].label) {
      pango_layout_set_text(layout, items[i].label, -1);
      int tw; pango_layout_get_pixel_size(layout, &tw, NULL);
      w += tw;
    }
    if (!items[i].separator && items[i].detail) {
      pango_layout_set_text(layout, items[i].detail, -1);
      int tw; pango_layout_get_pixel_size(layout, &tw, NULL);
      w += tw + 12;
    }
    if (w > maxw) maxw = w;
  }
  g_object_unref(layout);
  pango_font_description_free(font);
  cairo_destroy(cr);
  cairo_surface_destroy(s);
  *out_w = maxw + PAD * 2;
}

static int item_index_at_y(int y) {
  if (y < PAD) return -1;
  int idx = (y - PAD) / ROW_H;
  if (idx < 0 || idx >= g_n) return -1;
  if (g_items[idx].separator) return -1;
  return idx;
}

static void render(void) {
  int w = g_w * g_scale, h = g_h * g_scale;
  int stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, w);
  size_t size = (size_t)stride * (size_t)h;

  if (g_buffer && (g_buf_w != w || g_buf_h != h)) {
    wl_buffer_destroy(g_buffer); g_buffer = NULL;
    cairo_destroy(g_cr); g_cr = NULL;
    cairo_surface_destroy(g_cairo_surface); g_cairo_surface = NULL;
    munmap(g_shm_data, g_buf_size); g_shm_data = NULL;
  }
  if (!g_buffer) {
    int fd = create_shm_fd(size);
    if (fd < 0) return;
    g_shm_data = (unsigned char*)mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
    if (g_shm_data == MAP_FAILED) { close(fd); return; }
    struct wl_shm_pool *pool = wl_shm_create_pool(g_shm, fd, (int32_t)size);
    g_buffer = wl_shm_pool_create_buffer(pool, 0, w, h, stride, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    g_cairo_surface = cairo_image_surface_create_for_data(g_shm_data, CAIRO_FORMAT_ARGB32, w, h, stride);
    g_cr = cairo_create(g_cairo_surface);
    g_buf_w = w; g_buf_h = h; g_buf_size = size;
  }

  cairo_set_source_rgba(g_cr, 0.10, 0.11, 0.15, 0.98);
  cairo_paint(g_cr);

  // border
  cairo_set_source_rgba(g_cr, 0.20, 0.61, 0.86, 0.9);
  cairo_set_line_width(g_cr, 1);
  cairo_rectangle(g_cr, 0.5, 0.5, w - 1, h - 1);
  cairo_stroke(g_cr);

  PangoLayout *layout = pango_cairo_create_layout(g_cr);
  PangoFontDescription *font = pango_font_description_from_string("Sans 10");
  pango_layout_set_font_description(layout, font);

  for (int i = 0; i < g_n; i++) {
    int y = PAD + i * ROW_H;
    int cy = y * g_scale;
    if (g_items[i].separator) {
      cairo_set_source_rgba(g_cr, 0.4, 0.4, 0.45, 0.6);
      cairo_set_line_width(g_cr, 1);
      cairo_move_to(g_cr, PAD * g_scale, cy + (ROW_H*g_scale)/2);
      cairo_line_to(g_cr, (g_w - PAD) * g_scale, cy + (ROW_H*g_scale)/2);
      cairo_stroke(g_cr);
      continue;
    }
    if (i == g_hover) {
      cairo_set_source_rgba(g_cr, 0.20, 0.45, 0.70, 0.5);
      cairo_rectangle(g_cr, 2, cy, w - 4, ROW_H * g_scale);
      cairo_fill(g_cr);
    }
    // label
    cairo_set_source_rgb(g_cr, 0.85, 0.87, 0.90);
    pango_layout_set_text(layout, g_items[i].label ? g_items[i].label : "", -1);
    cairo_move_to(g_cr, PAD * g_scale, cy + (ROW_H*g_scale - 14)/2);
    pango_cairo_show_layout(g_cr, layout);
    // detail (right aligned)
    if (g_items[i].detail) {
      pango_layout_set_text(layout, g_items[i].detail, -1);
      int tw; pango_layout_get_pixel_size(layout, &tw, NULL);
      cairo_move_to(g_cr, (g_w - PAD) * g_scale - tw, cy + (ROW_H*g_scale - 14)/2);
      cairo_set_source_rgb(g_cr, 0.6, 0.65, 0.7);
      pango_cairo_show_layout(g_cr, layout);
    }
  }

  g_object_unref(layout);
  pango_font_description_free(font);
  cairo_surface_flush(g_cairo_surface);

  wl_surface_attach(g_surface, g_buffer, 0, 0);
  wl_surface_damage_buffer(g_surface, 0, 0, g_buf_w, g_buf_h);
  wl_surface_commit(g_surface);
}

void menu_open(int anchor_x, int anchor_y,
               menu_item_t *items, int n, int screen_w) {
  if (g_open) menu_close();
  if (n <= 0) return;

  g_items = (menu_item_t*)calloc((size_t)n, sizeof(menu_item_t));
  // deep-copy items (we own the strings; caller may free its own array)
  for (int i = 0; i < n; i++) {
    g_items[i].label = items[i].label ? strdup(items[i].label) : NULL;
    g_items[i].detail = items[i].detail ? strdup(items[i].detail) : NULL;
    g_items[i].cmd = items[i].cmd ? strdup(items[i].cmd) : NULL;
    g_items[i].separator = items[i].separator;
    g_items[i].activate = items[i].activate;
    g_items[i].arg = items[i].arg;
  }
  g_n = n;

  int content_w = 0;
  measure(g_items, n, &content_w);
  int max_w = (screen_w > 0 ? screen_w : g_screen_w) - 20;
  g_w = content_w > max_w ? max_w : content_w;
  g_h = PAD * 2 + n * ROW_H;

  int x = anchor_x;
  if (x + g_w > (screen_w > 0 ? screen_w : g_screen_w) - 4)
    x = (screen_w > 0 ? screen_w : g_screen_w) - 4 - g_w;
  if (x < 4) x = 4;

  g_surface = wl_compositor_create_surface(g_compositor);
  g_layer = zwlr_layer_shell_v1_get_layer_surface(
      g_layer_shell, g_surface, NULL,
      ZWLR_LAYER_SHELL_V1_LAYER_TOP, "fltk-panel-menu");
  zwlr_layer_surface_v1_add_listener(g_layer, &g_layer_listener, NULL);

  uint32_t anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT;
  zwlr_layer_surface_v1_set_anchor(g_layer, anchor);
  zwlr_layer_surface_v1_set_size(g_layer, (uint32_t)g_w, (uint32_t)g_h);
  zwlr_layer_surface_v1_set_exclusive_zone(g_layer, 0);
  zwlr_layer_surface_v1_set_keyboard_interactivity(g_layer, false);
  wl_surface_commit(g_surface);

  // wait for the configure event (same pattern as the panel init)
  g_configured = false;
  int guard = 0;
  while (!g_configured && guard++ < 8 && !wl_display_get_error(g_display))
    wl_display_dispatch(g_display);

  g_open = true;
  g_hover = -1;
  g_dirty = true;
  (void)anchor_y;
  render();
}

bool menu_is_open(void) { return g_open; }
struct wl_surface *menu_surface(void) { return g_surface; }

void menu_on_enter(struct wl_surface *surface, wl_fixed_t x, wl_fixed_t y) {
  if (!g_open || surface != g_surface) return;
  int idx = item_index_at_y(wl_fixed_to_int(y));
  if (idx != g_hover) { g_hover = idx; g_dirty = true; }
}
void menu_on_motion(wl_fixed_t x, wl_fixed_t y) {
  if (!g_open) return;
  int idx = item_index_at_y(wl_fixed_to_int(y));
  if (idx != g_hover) { g_hover = idx; g_dirty = true; }
}
bool menu_on_button(uint32_t button, uint32_t state, int mx, int my) {
  if (!g_open) return false;
  if (state != WL_POINTER_BUTTON_STATE_PRESSED || button != BTN_LEFT)
    return true;
  int idx = item_index_at_y(my);
  if (idx >= 0) {
    menu_item_t *it = &g_items[idx];
    if (it->activate) it->activate(it->arg);
    else if (it->cmd) system(it->cmd);
  }
  menu_close();
  return true;
}

void menu_commit(void) {
  if (g_open && g_dirty) {
    g_dirty = false;
    render();
  }
}
