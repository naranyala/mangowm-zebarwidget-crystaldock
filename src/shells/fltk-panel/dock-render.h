#pragma once
#include <cairo/cairo.h>
#include "toplevel.h"

#ifdef __cplusplus
extern "C" {
#endif

#define DOCK_ICON_SIZE 28
#define DOCK_HEIGHT 48

void dock_draw(cairo_t *cr, int w, int h,
               struct toplevel_info *tops, int top_count,
               int hover_idx);

int dock_icon_at(int w, int h,
                 struct toplevel_info *tops, int top_count,
                 int mouse_x);

void dock_icon_clear_cache(void);

#ifdef __cplusplus
}
#endif
