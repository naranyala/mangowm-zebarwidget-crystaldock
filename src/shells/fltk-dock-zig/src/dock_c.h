// dock_c.h — Combined header for Zig @cImport
// Includes real Wayland protocol headers (no glib dependency).
// Forward-declares cairo/pango/rsvg types to avoid glib header pollution.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/timerfd.h>
#include <sys/poll.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <ctype.h>

// Real Wayland headers (these are self-contained, no glib dependency)
#include <wayland-client.h>
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

// Cairo — opaque types with known layout for Zig
typedef struct _cairo { int _opaque; } cairo_t;
typedef struct _cairo_surface { int _opaque; } cairo_surface_t;
typedef struct _cairo_pattern { int _opaque; } cairo_pattern_t;
typedef struct { double x_bearing, y_bearing, width, height, x_advance, y_advance; } cairo_text_extents_t;

#define CAIRO_FORMAT_ARGB32 0
#define CAIRO_STATUS_SUCCESS 0
#define CAIRO_FONT_SLANT_NORMAL 0
#define CAIRO_FONT_WEIGHT_BOLD 1

cairo_surface_t *cairo_image_surface_create(int format, int width, int height);
cairo_surface_t *cairo_image_surface_create_for_data(unsigned char *data, int format, int width, int height, int stride);
cairo_surface_t *cairo_image_surface_create_from_png(const char *filename);
int cairo_image_surface_get_width(cairo_surface_t *surface);
int cairo_image_surface_get_height(cairo_surface_t *surface);
int cairo_format_stride_for_width(int format, int width);
int cairo_surface_status(cairo_surface_t *surface);
void cairo_surface_flush(cairo_surface_t *surface);
void cairo_surface_destroy(cairo_surface_t *surface);
cairo_t *cairo_create(cairo_surface_t *target);
void cairo_destroy(cairo_t *cr);
void cairo_paint(cairo_t *cr);
void cairo_set_source(cairo_t *cr, cairo_pattern_t *source);
void cairo_set_source_rgb(cairo_t *cr, double red, double green, double blue);
void cairo_set_source_rgba(cairo_t *cr, double red, double green, double blue, double alpha);
void cairo_set_source_surface(cairo_t *cr, cairo_surface_t *surface, double x, double y);
void cairo_set_line_width(cairo_t *cr, double width);
void cairo_move_to(cairo_t *cr, double x, double y);
void cairo_line_to(cairo_t *cr, double x, double y);
void cairo_rectangle(cairo_t *cr, double x, double y, double width, double height);
void cairo_arc(cairo_t *cr, double xc, double yc, double radius, double angle1, double angle2);
void cairo_fill(cairo_t *cr);
void cairo_stroke(cairo_t *cr);
void cairo_scale(cairo_t *cr, double sx, double sy);
void cairo_translate(cairo_t *cr, double tx, double ty);
void cairo_select_font_face(cairo_t *cr, const char *family, int slant, int weight);
void cairo_set_font_size(cairo_t *cr, double size);
void cairo_text_extents(cairo_t *cr, const char *utf8, cairo_text_extents_t *extents);
void cairo_show_text(cairo_t *cr, const char *utf8);
cairo_pattern_t *cairo_pattern_create_linear(double x0, double y0, double x1, double y1);
void cairo_pattern_add_color_stop_rgba(cairo_pattern_t *pattern, double offset, double red, double green, double blue, double alpha);
void cairo_pattern_destroy(cairo_pattern_t *pattern);

// Pango
typedef struct _PangoLayout { int _opaque; } PangoLayout;
typedef struct _PangoFontDescription { int _opaque; } PangoFontDescription;

PangoLayout *pango_cairo_create_layout(cairo_t *cr);
PangoFontDescription *pango_font_description_from_string(const char *str);
void pango_font_description_free(PangoFontDescription *desc);
void pango_layout_set_font_description(PangoLayout *layout, const PangoFontDescription *desc);
void pango_layout_set_text(PangoLayout *layout, const char *text, int length);
void pango_layout_get_pixel_size(PangoLayout *layout, int *width, int *height);
void pango_cairo_show_layout(cairo_t *cr, PangoLayout *layout);

// GLib (minimal — only what we need)
typedef int gboolean;
void g_object_unref(void *object);

// librsvg
typedef struct _RsvgHandle { int _opaque; } RsvgHandle;
typedef struct { double length; int unit; } RsvgLength;
typedef struct { double x, y, width, height; } RsvgRectangle;

RsvgHandle *rsvg_handle_new_from_file(const char *file_name, void **error);
void rsvg_handle_get_intrinsic_dimensions(RsvgHandle *handle,
    gboolean *has_width, RsvgLength *width,
    gboolean *has_height, RsvgLength *height,
    gboolean *has_viewbox, RsvgRectangle *viewbox);
gboolean rsvg_handle_render_document(RsvgHandle *handle, cairo_t *cr,
    const RsvgRectangle *viewport, void **error);

// Utility
int dock_create_shm_fd(size_t size);

// Additional headers for panel widgets
#include <sys/statvfs.h>
