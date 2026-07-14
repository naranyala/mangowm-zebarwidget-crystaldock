#pragma once
#include <cairo/cairo.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct widget widget_t;

struct wl_seat;

struct panel_ctx {
  struct toplevel_info *toplevels;
  int *count;
  struct wl_seat *seat;
  int screen_w;
};
typedef struct panel_ctx panel_ctx_t;

struct widget {
  const char *type;
  char *name;
  void *priv;
  void *ctx;
  int cached_w;
  int side;   // 0 = left-aligned block, 1 = right-aligned block

  int  (*measure)(widget_t *w, int h);
  void (*draw)(widget_t *w, cairo_t *cr, int x, int y, int h);
  void (*update)(widget_t *w);
  bool (*click)(widget_t *w, int btn, int x, int y);
  int  (*menu_open)(widget_t *w, int anchor_x, int y);
  void (*free)(widget_t *w);
};

widget_t *widget_create(const char *type, const char *opts);

widget_t **widget_list_load(const char *path, int *out_count);
widget_t **widget_list_create_default(int *out_count);
void widget_list_free(widget_t **list, int count);

void widget_list_update(widget_t **list, int count);
int  widget_list_width(widget_t **list, int count, int h, int pad);
void widget_list_draw(widget_t **list, int count, cairo_t *cr,
                      int x0, int y, int h, int pad);

int  widget_text(cairo_t *cr, const char *text, int x, int h,
                 const char *font_desc, double r, double g, double b);
void widget_icon_glyph(cairo_t *cr, const char *glyph, int x, int h,
                        double r, double g, double b);

// Hooks the host shell can register so the (pinned) settings widget can
// drive the running process. All are optional; NULL means "unsupported".
extern void (*g_widget_reload_cb)(void);
extern void (*g_widget_restart_cb)(void);
extern void (*g_widget_quit_cb)(void);

#ifdef __cplusplus
}
#endif
