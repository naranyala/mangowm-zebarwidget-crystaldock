#include "widget.h"
#include "widgets.h"
#include <cairo/cairo.h>
#include <pango/pangocairo.h>
#include <stdlib.h>
#include <string.h>

static widget_t *(*registry[])(const char *opts) = {
  w_workspaces_create,
  w_toplevel_create,
  w_launcher_create,
  w_cpu_create,
  w_mem_create,
  w_temp_create,
  w_disk_create,
  w_battery_create,
  w_volume_create,
  w_network_create,
  w_media_create,
  w_clock_create,
  w_power_create,
  w_settings_create,
  NULL,
};

static const char *registry_types[] = {
  "workspaces",
  "toplevel",
  "launcher",
  "cpu",
  "mem",
  "temp",
  "disk",
  "battery",
  "volume",
  "network",
  "media",
  "clock",
  "power",
  "settings",
  NULL,
};

void (*g_widget_reload_cb)(void) = NULL;
void (*g_widget_restart_cb)(void) = NULL;
void (*g_widget_quit_cb)(void) = NULL;

widget_t *widget_create(const char *type, const char *opts) {
  widget_t *w = NULL;
  for (int i = 0; registry_types[i]; i++) {
    if (!strcmp(type, registry_types[i])) {
      w = registry[i](opts ? opts : "");
      break;
    }
  }
  if (!w) return NULL;
  w->side = 0;
  if (opts) {
    const char *p = strstr(opts, "side");
    if (p) {
      p = strchr(p, '=');
      if (p) {
        p++;
        while (*p == ' ' || *p == '\t') p++;
        if (!strncmp(p, "right", 5)) w->side = 1;
      }
    }
  }
  return w;
}

// Ensure exactly one settings widget is present (it is pinned and cannot be
// removed from the panel via config). If the config omitted it, append one.
static void ensure_settings_widget(widget_t ***plist, int *pcount) {
  widget_t **list = *plist;
  int count = *pcount;
  for (int i = 0; i < count; i++)
    if (!strcmp(list[i]->type, "settings"))
      return;  // already present — do not duplicate
  widget_t *s = w_settings_create(NULL);
  if (!s) return;
  s->side = 1;  // right block
  list = (widget_t**)realloc(list, (size_t)(count + 1) * sizeof(widget_t*));
  if (!list) { free(s); return; }
  list[count++] = s;
  *plist = list;
  *pcount = count;
}

widget_t **widget_list_load(const char *path, int *out_count) {
  widget_t **list = config_load_widgets(path, out_count);
  if (!list) return NULL;
  ensure_settings_widget(&list, out_count);
  return list;
}

void widget_list_free(widget_t **list, int count) {
  for (int i = 0; i < count; i++) {
    if (list[i]->free) list[i]->free(list[i]);
    free(list[i]->name);
    free(list[i]);
  }
  free(list);
}

void widget_list_update(widget_t **list, int count) {
  for (int i = 0; i < count; i++)
    if (list[i]->update) list[i]->update(list[i]);
}

int widget_list_width(widget_t **list, int count, int h, int pad) {
  int total = 0;
  for (int i = 0; i < count; i++) {
    int w = list[i]->measure ? list[i]->measure(list[i], h) : 0;
    list[i]->cached_w = w;
    total += w + pad;
  }
  return total;
}

void widget_list_draw(widget_t **list, int count, cairo_t *cr,
                      int x0, int y, int h, int pad) {
  int x = x0;
  for (int i = 0; i < count; i++) {
    int w = list[i]->cached_w;
    if (list[i]->draw) list[i]->draw(list[i], cr, x, y, h);
    x += w + pad;
  }
}

int widget_text(cairo_t *cr, const char *text, int x, int h,
                const char *font_desc, double r, double g, double b) {
  PangoLayout *layout = pango_cairo_create_layout(cr);
  PangoFontDescription *font = pango_font_description_from_string(font_desc);
  pango_layout_set_font_description(layout, font);
  pango_layout_set_text(layout, text, -1);
  int tw, th;
  pango_layout_get_pixel_size(layout, &tw, &th);
  cairo_set_source_rgb(cr, r, g, b);
  cairo_move_to(cr, x, (h - th) / 2);
  pango_cairo_show_layout(cr, layout);
  g_object_unref(layout);
  pango_font_description_free(font);
  return tw;
}

void widget_icon_glyph(cairo_t *cr, const char *glyph, int x, int h,
                       double r, double g, double b) {
  PangoLayout *layout = pango_cairo_create_layout(cr);
  PangoFontDescription *font = pango_font_description_from_string("Sans 11");
  pango_layout_set_font_description(layout, font);
  pango_layout_set_text(layout, glyph, -1);
  int tw, th;
  pango_layout_get_pixel_size(layout, &tw, &th);
  cairo_set_source_rgb(cr, r, g, b);
  cairo_move_to(cr, x, (h - th) / 2);
  pango_cairo_show_layout(cr, layout);
  g_object_unref(layout);
  pango_font_description_free(font);
}

widget_t **widget_list_create_default(int *out_count) {
  const char *names[] = {
    "workspaces", "toplevel", "launcher",
    "cpu", "mem", "temp", "disk", "battery",
    "volume", "network", "media", "clock", "power"
  };
  int n = (int)(sizeof(names) / sizeof(names[0]));
  // +2: room for the pinned settings widget and a trailing NULL
  widget_t **list = (widget_t**)calloc((size_t)n + 2, sizeof(widget_t*));
  int k = 0;
  for (int i = 0; i < n; i++) {
    widget_t *w = widget_create(names[i], NULL);
    if (!w) continue;
    // system stats, clock and power go to the right block by default
    if (!strcmp(names[i], "cpu") || !strcmp(names[i], "mem") ||
        !strcmp(names[i], "temp") || !strcmp(names[i], "disk") ||
        !strcmp(names[i], "battery") || !strcmp(names[i], "volume") ||
        !strcmp(names[i], "network") || !strcmp(names[i], "media") ||
        !strcmp(names[i], "clock") || !strcmp(names[i], "power"))
      w->side = 1;
    list[k++] = w;
  }
  // Pinned settings widget (always present on the right block).
  widget_t *s = w_settings_create(NULL);
  if (s) { s->side = 1; list[k++] = s; }
  *out_count = k;
  return list;
}
