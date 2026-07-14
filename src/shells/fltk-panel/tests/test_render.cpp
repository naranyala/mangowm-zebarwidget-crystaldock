#include <glib.h>
#include <cairo/cairo.h>
#include <string.h>
#include "../render.h"
#include "../toplevel.h"

// Helper: create a Cairo surface with ARGB32 pixel buffer
static cairo_surface_t *make_surface(int w, int h, unsigned char **out_data, int *out_stride) {
  *out_stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, w);
  *out_data = (unsigned char*)g_malloc0((size_t)(*out_stride) * h);
  return cairo_image_surface_create_for_data(*out_data, CAIRO_FORMAT_ARGB32, w, h, *out_stride);
}

static void test_gradient_background(void) {
  int w = 200, h = 36, stride;
  unsigned char *data;
  cairo_surface_t *surf = make_surface(w, h, &data, &stride);
  cairo_t *cr = cairo_create(surf);

  draw_panel_content(cr, w, h, NULL, 0);

  // Sample at mid-width (x=100), mid-height (row 16) to avoid accent line at bottom
  // Gradient goes from (0.15,0.15,0.17) top to (0.10,0.10,0.12) bottom
  // At row 16 (44%): ≈ (0.128, 0.128, 0.148) → (32, 32, 38) in 8-bit
  int mid_ofs = 16 * stride + 100 * 4;
  int mr = data[mid_ofs + 2];
  int mg = data[mid_ofs + 1];
  int mb = data[mid_ofs + 0];
  g_assert_cmpint(mr, >=, 25); g_assert_cmpint(mr, <=, 45);
  g_assert_cmpint(mg, >=, 25); g_assert_cmpint(mg, <=, 45);
  g_assert_cmpint(mb, >=, 30); g_assert_cmpint(mb, <=, 50);

  // Top row (row 0) should be close to lighter (0.15) stop
  int top_ofs = 0 * stride + 100 * 4;
  g_assert_cmpint(data[top_ofs + 2], >, data[mid_ofs + 2]); // top R > mid R
  g_assert_cmpint(data[top_ofs + 1], >, data[mid_ofs + 1]); // top G > mid G

  cairo_destroy(cr);
  cairo_surface_destroy(surf);
  g_free(data);
}

static void test_accent_line(void) {
  int w = 200, h = 36, stride;
  unsigned char *data;
  cairo_surface_t *surf = make_surface(w, h, &data, &stride);
  cairo_t *cr = cairo_create(surf);

  draw_panel_content(cr, w, h, NULL, 0);

  // The accent line is at row 35 (h-1), blue (0.3, 0.5, 0.9)
  int y = h - 1;
  int line_ofs = y * stride + 50 * 4;
  int lb = data[line_ofs + 0];
  int lg = data[line_ofs + 1];
  int lr = data[line_ofs + 2];

  // Blue: 0.9*255 ≈ 229, Green: 0.5*255 ≈ 127, Red: 0.3*255 ≈ 76
  g_assert_cmpint(lb, >=, 150); // strong blue
  g_assert_cmpint(lg, >=, 80);  // moderate green

  // Compare to background far from line (row 0): bottom has MORE blue
  int bg_ofs = 0 * stride + 50 * 4;
  g_assert(data[line_ofs + 0] > data[bg_ofs + 0]); // bottom more blue

  cairo_destroy(cr);
  cairo_surface_destroy(surf);
  g_free(data);
}

static void test_toplevel_text_renders(void) {
  int w = 400, h = 36, stride;
  unsigned char *data;
  cairo_surface_t *surf = make_surface(w, h, &data, &stride);
  cairo_t *cr = cairo_create(surf);

  struct toplevel_info tops[2];
  memset(tops, 0, sizeof(tops));
  tops[0].focused = true;
  strcpy(tops[0].title, "Terminal");
  tops[1].focused = false;
  strcpy(tops[1].title, "Browser");

  draw_panel_content(cr, w, h, tops, 2);

  // The focused toplevel draws a white focus indicator rect at (x_offset, h-3, 10, 3)
  // After workspace text "  1  2  3  4  " (~62px) + initial 10px + gap 4px:
  //   x_offset ≈ 10 + 62 + 4 = 76
  // Focus rect: (76, 33, 10, 3) → x=76..86, y=33..35
  // Search for bright (near-white) pixels there
  bool found_focus = false;
  for (int y = h - 3; y < h; y++) {
    for (int x = 70; x < 100; x++) {
      int ofs = y * stride + x * 4;
      int r = data[ofs + 2], g = data[ofs + 1], b = data[ofs + 0];
      if (r > 200 && g > 200 && b > 200) {
        found_focus = true;
        goto found;
      }
    }
  }
found:
  g_assert(found_focus);

  cairo_destroy(cr);
  cairo_surface_destroy(surf);
  g_free(data);
}

static void test_workspace_text(void) {
  int w = 200, h = 36, stride;
  unsigned char *data;
  cairo_surface_t *surf = make_surface(w, h, &data, &stride);
  cairo_t *cr = cairo_create(surf);

  draw_panel_content(cr, w, h, NULL, 0);

  // Workspace text "  1  2  3  4  " is drawn at x=10, gray (0.6,0.6,0.7)
  // Text is vertically centered: y = (36 - th) / 2 ≈ 10 for Sans 10 (~16px height)
  // Search middle rows (8-20) for brighter pixels from text
  bool found_text = false;
  for (int y = 8; y < 20; y++) {
    for (int x = 10; x < 120; x++) {
      int ofs = y * stride + x * 4;
      int r = data[ofs + 2], g = data[ofs + 1], b = data[ofs + 0];
      // Text gray (153,153,178) is much brighter than gradient at these rows
      if (r > 80 && g > 80 && b > 80) {
        found_text = true;
        goto done;
      }
    }
  }
done:
  g_assert(found_text);

  cairo_destroy(cr);
  cairo_surface_destroy(surf);
  g_free(data);
}

static void test_empty_panel(void) {
  int w = 100, h = 20, stride;
  unsigned char *data;
  cairo_surface_t *surf = make_surface(w, h, &data, &stride);
  cairo_t *cr = cairo_create(surf);

  // Draw with no toplevels
  draw_panel_content(cr, w, h, NULL, 0);

  // Surface should have non-zero pixels (gradient + text + line)
  bool has_pixels = false;
  for (int i = 0; i < stride * h; i++) {
    if (data[i] != 0) { has_pixels = true; break; }
  }
  g_assert(has_pixels);

  cairo_destroy(cr);
  cairo_surface_destroy(surf);
  g_free(data);
}

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, NULL);
  g_test_add_func("/render/gradient_background", test_gradient_background);
  g_test_add_func("/render/accent_line", test_accent_line);
  g_test_add_func("/render/toplevel_text", test_toplevel_text_renders);
  g_test_add_func("/render/workspace_text", test_workspace_text);
  g_test_add_func("/render/empty_panel", test_empty_panel);
  return g_test_run();
}
