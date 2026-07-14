#include "render.h"
#include <pango/pangocairo.h>
#include <time.h>
#include <string.h>
#include <stdio.h>

extern "C" void draw_panel_content(cairo_t *cr, int w, int h,
                         struct toplevel_info *tops, int top_count) {
  // background gradient
  cairo_pattern_t *grad = cairo_pattern_create_linear(0, 0, 0, h);
  cairo_pattern_add_color_stop_rgba(grad, 0, 0.15, 0.15, 0.17, 1);
  cairo_pattern_add_color_stop_rgba(grad, 1, 0.10, 0.10, 0.12, 1);
  cairo_set_source(cr, grad);
  cairo_paint(cr);
  cairo_pattern_destroy(grad);

  // accent line at bottom
  cairo_set_source_rgb(cr, 0.3, 0.5, 0.9);
  cairo_set_line_width(cr, 2);
  cairo_move_to(cr, 0, h - 1);
  cairo_line_to(cr, w, h - 1);
  cairo_stroke(cr);

  // Pango layout for all text
  PangoLayout *layout = pango_cairo_create_layout(cr);
  PangoFontDescription *font = pango_font_description_from_string("Sans 10");
  pango_layout_set_font_description(layout, font);
  int tw, th, x_offset = 10;

  // workspace indicator
  cairo_set_source_rgb(cr, 0.6, 0.6, 0.7);
  pango_layout_set_text(layout, "  1  2  3  4  ", -1);
  pango_layout_get_pixel_size(layout, &tw, &th);
  cairo_move_to(cr, x_offset, (h - th) / 2);
  pango_cairo_show_layout(cr, layout);
  x_offset += tw + 4;

  // toplevel taskbar
  for (int i = 0; i < top_count; i++) {
    const char *title = tops[i].title[0] ? tops[i].title : tops[i].app_id;
    if (!title || !title[0]) title = "(untitled)";
    char buf[96];
    snprintf(buf, sizeof(buf), "  %.60s  ", title);

    if (tops[i].focused) {
      cairo_set_source_rgb(cr, 1, 1, 1);
      cairo_rectangle(cr, x_offset, h - 3, 10, 3);
      cairo_fill(cr);
    } else {
      cairo_set_source_rgb(cr, 0.55, 0.55, 0.55);
    }

    pango_layout_set_text(layout, buf, -1);
    pango_layout_get_pixel_size(layout, &tw, &th);
    cairo_move_to(cr, x_offset, (h - th) / 2);
    pango_cairo_show_layout(cr, layout);
    x_offset += tw + 4;
  }

  // clock on right
  time_t now = time(NULL);
  char ts[64];
  strftime(ts, sizeof(ts), "  %H:%M  ", localtime(&now));
  pango_layout_set_text(layout, ts, -1);
  pango_layout_get_pixel_size(layout, &tw, &th);
  cairo_set_source_rgb(cr, 0.85, 0.85, 0.85);
  cairo_move_to(cr, w - tw - 10, (h - th) / 2);
  pango_cairo_show_layout(cr, layout);

  g_object_unref(layout);
  pango_font_description_free(font);
}
