#include "dock-render.h"
#include "icon.h"
#include <cairo/cairo.h>
#include <pango/pangocairo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define PAD 8
#define FOCUS_BAR_H 3

struct icon_cache_entry {
  char app_id[128];
  cairo_surface_t *surf;
};

#define ICON_CACHE_MAX 64
static struct icon_cache_entry icon_cache[ICON_CACHE_MAX];
static int icon_cache_count = 0;

void dock_icon_clear_cache(void) {
  for (int i = 0; i < icon_cache_count; i++) {
    if (icon_cache[i].surf) cairo_surface_destroy(icon_cache[i].surf);
  }
  icon_cache_count = 0;
}

static cairo_surface_t *get_icon(const char *app_id, int size) {
  for (int i = 0; i < icon_cache_count; i++) {
    if (!strcmp(icon_cache[i].app_id, app_id))
      return icon_cache[i].surf;
  }

  cairo_surface_t *surf = app_icon_load(app_id, size);
  if (!surf) surf = app_icon_fallback(app_id, size);

  if (icon_cache_count < ICON_CACHE_MAX) {
    strncpy(icon_cache[icon_cache_count].app_id, app_id,
            sizeof(icon_cache[0].app_id) - 1);
    icon_cache[icon_cache_count].surf = surf;
    icon_cache_count++;
  }

  return surf;
}

// Return the x-offset of a given icon slot (used by both draw and hit-test).
// start_x is the left edge of the centered icon row.
static int icon_x(int slot_idx, int start_x) {
  return start_x + slot_idx * (DOCK_ICON_SIZE + PAD);
}

void dock_draw(cairo_t *cr, int w, int h,
               struct toplevel_info *tops, int top_count,
               int hover_idx) {
  // background gradient (slightly different from top panel)
  cairo_pattern_t *grad = cairo_pattern_create_linear(0, 0, 0, h);
  cairo_pattern_add_color_stop_rgba(grad, 0, 0.08, 0.08, 0.10, 1);
  cairo_pattern_add_color_stop_rgba(grad, 1, 0.05, 0.05, 0.07, 1);
  cairo_set_source(cr, grad);
  cairo_paint(cr);
  cairo_pattern_destroy(grad);

  // subtle top border line
  cairo_set_source_rgb(cr, 0.25, 0.25, 0.27);
  cairo_set_line_width(cr, 1);
  cairo_move_to(cr, 0, 0.5);
  cairo_line_to(cr, w, 0.5);
  cairo_stroke(cr);

  int cy = (h - DOCK_ICON_SIZE) / 2;

  // center the running-apps icon row horizontally
  int slot = DOCK_ICON_SIZE + PAD;
  int total_w = top_count > 0 ? top_count * slot - PAD : 0;
  int start_x = (w - total_w) / 2;
  if (start_x < 0) start_x = 0;

  for (int i = 0; i < top_count; i++) {
    int x = icon_x(i, start_x);
    int icon_y = cy;

    cairo_surface_t *icon_surf = get_icon(
      tops[i].app_id[0] ? tops[i].app_id : tops[i].title,
      DOCK_ICON_SIZE);

    if (!icon_surf) continue;

    // hover highlight
    if (i == hover_idx) {
      cairo_set_source_rgba(cr, 1, 1, 1, 0.12);
      cairo_rectangle(cr, x - 4, icon_y - 4,
                      DOCK_ICON_SIZE + 8, DOCK_ICON_SIZE + 8);
      cairo_fill(cr);
    }

    // draw the icon
    cairo_set_source_surface(cr, icon_surf, x, icon_y);
    cairo_paint(cr);

    // focus indicator bar above the icon
    if (tops[i].focused) {
      cairo_set_source_rgb(cr, 0.3, 0.5, 0.9);
      cairo_rectangle(cr, x + 2, cy - FOCUS_BAR_H,
                      DOCK_ICON_SIZE - 4, FOCUS_BAR_H);
      cairo_fill(cr);
    }
  }
}

int dock_icon_at(int w, int h,
                 struct toplevel_info *tops, int top_count,
                 int mouse_x) {
  int slot = DOCK_ICON_SIZE + PAD;
  int total_w = top_count > 0 ? top_count * slot - PAD : 0;
  int start_x = (w - total_w) / 2;
  if (start_x < 0) start_x = 0;
  for (int i = 0; i < top_count; i++) {
    int x = icon_x(i, start_x);
    if (mouse_x >= x && mouse_x < x + DOCK_ICON_SIZE + PAD)
      return i;
  }
  return -1;
}
