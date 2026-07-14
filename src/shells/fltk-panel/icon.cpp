#include "icon.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <cairo/cairo.h>
#include <ctype.h>
#include <math.h>
#include <librsvg/rsvg.h>

static const char *desktop_dirs[] = {
  "/usr/share/applications/",
  "/usr/local/share/applications/",
  NULL,
};

static const char *theme_dirs[] = {
  "/usr/share/icons/hicolor/%dx%d/apps/",
  "/usr/local/share/icons/hicolor/%dx%d/apps/",
  "/usr/share/icons/Papirus/%dx%d/apps/",
  "/usr/share/icons/Papirus-Dark/%dx%d/apps/",
  "/usr/share/icons/breeze/apps/%d/",
  "/usr/share/icons/breeze-dark/apps/%d/",
  "/usr/share/icons/gnome/%dx%d/apps/",
  "/usr/share/icons/Adwaita/%dx%d/apps/",
  NULL,
};

static const char *scalable_dirs[] = {
  "/usr/share/icons/hicolor/scalable/apps/",
  "/usr/local/share/icons/hicolor/scalable/apps/",
  "/usr/share/icons/Papirus/scalable/apps/",
  "/usr/share/icons/Papirus-Dark/scalable/apps/",
  "/usr/share/icons/breeze/apps/scalable/",
  "/usr/share/icons/breeze-dark/apps/scalable/",
  "/usr/share/icons/gnome/scalable/apps/",
  "/usr/share/icons/Adwaita/scalable/apps/",
  NULL,
};

static int sizes[] = {48, 32, 24, 22, 16, 64, 96, 128, 256, 0};

static int path_exists(const char *path) {
  FILE *f = fopen(path, "r");
  if (!f) return 0;
  fclose(f);
  return 1;
}

static char *find_desktop_file(const char *app_id) {
  static char buf[512];
  for (int i = 0; desktop_dirs[i]; i++) {
    snprintf(buf, sizeof(buf), "%s%s.desktop", desktop_dirs[i], app_id);
    if (path_exists(buf)) return buf;
  }
  return NULL;
}

static char *read_icon_name(const char *desktop_path) {
  static char icon_name[128];
  FILE *f = fopen(desktop_path, "r");
  if (!f) return NULL;
  char line[512];
  icon_name[0] = 0;
  bool in_desktop_entry = false;
  while (fgets(line, sizeof(line), f)) {
    if (line[0] == '[') {
      in_desktop_entry = (strncmp(line, "[Desktop Entry]", 15) == 0);
      continue;
    }
    if (!in_desktop_entry) continue;
    if (strncmp(line, "Icon=", 5) == 0) {
      size_t len = strlen(line + 5);
      if (len > 0 && line[5 + len - 1] == '\n') line[5 + len - 1] = 0;
      strncpy(icon_name, line + 5, sizeof(icon_name) - 1);
      icon_name[sizeof(icon_name) - 1] = 0;
      break;
    }
  }
  fclose(f);
  return icon_name[0] ? icon_name : NULL;
}

static cairo_surface_t *scale_to_size(cairo_surface_t *src, int size) {
  int w = cairo_image_surface_get_width(src);
  int h = cairo_image_surface_get_height(src);
  if (w == size && h == size) return src;
  cairo_surface_t *scaled = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size, size);
  cairo_t *cr = cairo_create(scaled);
  cairo_scale(cr, (double)size / w, (double)size / h);
  cairo_set_source_surface(cr, src, 0, 0);
  cairo_paint(cr);
  cairo_destroy(cr);
  cairo_surface_destroy(src);
  return scaled;
}

static cairo_surface_t *try_load_png(const char *icon_name) {
  static char buf[1024];

  // Try scalable directories first (SVG/PNG without size)
  for (int i = 0; scalable_dirs[i]; i++) {
    snprintf(buf, sizeof(buf), "%s%s.png", scalable_dirs[i], icon_name);
    cairo_surface_t *surf = cairo_image_surface_create_from_png(buf);
    if (cairo_surface_status(surf) == CAIRO_STATUS_SUCCESS)
      return surf;
    cairo_surface_destroy(surf);
  }

  // Try sized directories
  for (int si = 0; sizes[si]; si++) {
    int s = sizes[si];
    for (int i = 0; theme_dirs[i]; i++) {
      snprintf(buf, sizeof(buf), theme_dirs[i], s, s);
      size_t blen = strlen(buf);
      snprintf(buf + blen, sizeof(buf) - blen, "%s.png", icon_name);
      cairo_surface_t *surf = cairo_image_surface_create_from_png(buf);
      if (cairo_surface_status(surf) == CAIRO_STATUS_SUCCESS)
        return surf;
      cairo_surface_destroy(surf);
    }
  }
  return NULL;
}

static cairo_surface_t *try_load_svg(const char *icon_name, int size) {
  static char buf[1024];

  // Try scalable directories first
  for (int i = 0; scalable_dirs[i]; i++) {
    snprintf(buf, sizeof(buf), "%s%s.svg", scalable_dirs[i], icon_name);
    if (!path_exists(buf)) continue;

    RsvgHandle *handle = rsvg_handle_new_from_file(buf, NULL);
    if (!handle) continue;

    gboolean has_w, has_h, has_vb;
    RsvgLength rsvg_w, rsvg_h;
    RsvgRectangle vb = {0, 0, (double)size, (double)size};
    rsvg_handle_get_intrinsic_dimensions(handle,
        &has_w, &rsvg_w, &has_h, &rsvg_h,
        &has_vb, &vb);

    double sw, sh;
    if (has_vb) {
      sw = vb.width;
      sh = vb.height;
    } else if (has_w && has_h) {
      sw = rsvg_w.length;
      sh = rsvg_h.length;
    } else {
      sw = sh = size;
    }
    if (sw <= 0 || sh <= 0) { sw = sh = size; }

    cairo_surface_t *surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size, size);
    cairo_t *cr = cairo_create(surf);
    double scale = fmin((double)size / sw, (double)size / sh);
    double ox = (size - sw * scale) / 2;
    double oy = (size - sh * scale) / 2;
    cairo_translate(cr, ox, oy);
    cairo_scale(cr, scale, scale);
    RsvgRectangle viewport = {0, 0, sw, sh};
    rsvg_handle_render_document(handle, cr, &viewport, NULL);
    cairo_destroy(cr);
    g_object_unref(handle);
    return surf;
  }

  // Try sized directories
  for (int si = 0; sizes[si]; si++) {
    int s = sizes[si];
    for (int i = 0; theme_dirs[i]; i++) {
      snprintf(buf, sizeof(buf), theme_dirs[i], s, s);
      size_t blen = strlen(buf);
      snprintf(buf + blen, sizeof(buf) - blen, "%s.svg", icon_name);
      if (!path_exists(buf)) continue;

      RsvgHandle *handle = rsvg_handle_new_from_file(buf, NULL);
      if (!handle) continue;

      gboolean has_w, has_h, has_vb;
      RsvgLength rsvg_w, rsvg_h;
      RsvgRectangle vb = {0, 0, (double)size, (double)size};
      rsvg_handle_get_intrinsic_dimensions(handle,
          &has_w, &rsvg_w, &has_h, &rsvg_h,
          &has_vb, &vb);

      double sw, sh;
      if (has_vb) {
        sw = vb.width;
        sh = vb.height;
      } else if (has_w && has_h) {
        sw = rsvg_w.length;
        sh = rsvg_h.length;
      } else {
        sw = sh = size;
      }
      if (sw <= 0 || sh <= 0) { sw = sh = size; }

      cairo_surface_t *surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size, size);
      cairo_t *cr = cairo_create(surf);
      double scale = fmin((double)size / sw, (double)size / sh);
      double ox = (size - sw * scale) / 2;
      double oy = (size - sh * scale) / 2;
      cairo_translate(cr, ox, oy);
      cairo_scale(cr, scale, scale);
      RsvgRectangle viewport = {0, 0, sw, sh};
      rsvg_handle_render_document(handle, cr, &viewport, NULL);
      cairo_destroy(cr);
      g_object_unref(handle);
      return surf;
    }
  }
  return NULL;
}

cairo_surface_t *app_icon_load(const char *app_id, int size) {
  const char *icon_name = app_id;

  char *desktop = find_desktop_file(app_id);
  if (desktop) {
    char *name = read_icon_name(desktop);
    if (name) icon_name = name;
  }

  cairo_surface_t *surf = try_load_png(icon_name);
  if (surf) return scale_to_size(surf, size);

  surf = try_load_svg(icon_name, size);
  if (surf) return surf;

  // Try app_id directly as icon name
  if (icon_name != app_id) {
    surf = try_load_png(app_id);
    if (surf) return scale_to_size(surf, size);

    surf = try_load_svg(app_id, size);
    if (surf) return surf;
  }

  return NULL;
}

static double hue_for_string(const char *s) {
  unsigned h = 0;
  for (const char *p = s; *p; p++) h = h * 31 + (unsigned char)*p;
  return (h % 360) / 360.0;
}

cairo_surface_t *app_icon_fallback(const char *app_id, int size) {
  cairo_surface_t *surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size, size);
  cairo_t *cr = cairo_create(surf);

  double hue = hue_for_string(app_id);
  double r, g, b;
  {
    double h6 = hue * 6;
    int sext = (int)h6;
    double frac = h6 - sext;
    double v = 0.6, s = 0.7;
    double p = v * (1 - s);
    double q = v * (1 - s * frac);
    double t = v * (1 - s * (1 - frac));
    switch (sext % 6) {
      case 0: r = v; g = t; b = p; break;
      case 1: r = q; g = v; b = p; break;
      case 2: r = p; g = v; b = t; break;
      case 3: r = p; g = q; b = v; break;
      case 4: r = t; g = p; b = v; break;
      default: r = v; g = p; b = q; break;
    }
  }

  cairo_set_source_rgb(cr, r, g, b);
  double cx = size / 2.0, cy = size / 2.0, rad = size / 2.0 - 2;
  cairo_arc(cr, cx, cy, rad, 0, 2 * M_PI);
  cairo_fill(cr);

  cairo_set_source_rgb(cr, 1, 1, 1);
  cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
  cairo_set_font_size(cr, size * 0.55);

  char letter[2] = {app_id[0] ? (char)toupper(app_id[0]) : '?', 0};
  if (letter[0] == 0) letter[0] = '?';
  cairo_text_extents_t te;
  cairo_text_extents(cr, letter, &te);
  cairo_move_to(cr, cx - te.width / 2 - te.x_bearing, cy - te.height / 2 - te.y_bearing);
  cairo_show_text(cr, letter);

  cairo_destroy(cr);
  return surf;
}
