#pragma once
#include <cairo/cairo.h>
#include "toplevel.h"

#ifdef __cplusplus
extern "C" {
#endif

void draw_panel_content(cairo_t *cr, int w, int h,
                         struct toplevel_info *toplevels, int toplevel_count);

#ifdef __cplusplus
}
#endif
