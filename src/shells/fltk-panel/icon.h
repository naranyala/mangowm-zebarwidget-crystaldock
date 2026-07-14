#pragma once
#include <cairo/cairo.h>

#ifdef __cplusplus
extern "C" {
#endif

cairo_surface_t *app_icon_load(const char *app_id, int size);
cairo_surface_t *app_icon_fallback(const char *app_id, int size);

#ifdef __cplusplus
}
#endif
