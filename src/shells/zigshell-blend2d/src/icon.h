// icon.h — Desktop file lookup + PNG icon loading via Blend2D
#ifndef ICON_H
#define ICON_H

#include <stdint.h>
#include <stdbool.h>

struct BLImageCore;

// Initialize the icon system.
void icon_init(void);

// Clear all cached icons.
void icon_clear_cache(void);

// Load an icon for the given app_id. Returns true if found.
// The loaded image is stored in *out_img.
bool icon_load(const char* app_id, int size, struct BLImageCore* out_img);

// Generate a fallback colored circle icon with first letter.
// The result is cached. Returns the cached pointer.
struct BLImageCore* icon_fallback(const char* app_id, int size);

#endif // ICON_H
