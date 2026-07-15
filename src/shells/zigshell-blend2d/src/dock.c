// dock.c — Dock rendering via Blend2D (C implementation)
#include "dock.h"
#include "blend2d_render.h"
#include "icon.h"
#include <string.h>
#include <stdlib.h>

#define FOCUS_BAR_H 3

static int icon_x(int slot_idx, int start_x) {
    return start_x + slot_idx * (DOCK_ICON_SIZE + DOCK_PAD);
}

void dock_draw(struct BlendRenderer* renderer, int w, int h,
               const char** app_ids, const char** titles, int* focused,
               int top_count, int hover_idx) {
    if (!renderer) return;

    // Background gradient (two-tone)
    blend_renderer_fill_rect(renderer, 0, 0, (double)w, (double)h / 2.0, 0xFF141419);
    blend_renderer_fill_rect(renderer, 0, (double)h / 2.0, (double)w, (double)h / 2.0, 0xFF0D0D12);

    // Top border
    blend_renderer_fill_rect(renderer, 0, 0, (double)w, 1, 0xFF404045);

    int cy = (h - DOCK_ICON_SIZE) / 2;
    int slot = DOCK_ICON_SIZE + DOCK_PAD;
    int total_w = top_count > 0 ? top_count * slot - DOCK_PAD : 0;
    int start_x = (w - total_w) / 2;
    if (start_x < 0) start_x = 0;

    for (int i = 0; i < top_count; i++) {
        int x = icon_x(i, start_x);

        // Hover highlight
        if (i == hover_idx) {
            blend_renderer_fill_rect(renderer, (double)(x - 4), (double)(cy - 4),
                (double)(DOCK_ICON_SIZE + 8), (double)(DOCK_ICON_SIZE + 8), 0x1FFFFFFF);
        }

        // Load or fallback icon
        struct BLImageCore* icon_img = NULL;
        const char* name = app_ids[i];
        if (!name || !name[0]) name = titles[i];
        if (!name) name = "unknown";

        struct BLImageCore loaded;
        if (icon_load(name, DOCK_ICON_SIZE, &loaded)) {
            icon_img = &loaded;
        } else {
            icon_img = icon_fallback(name, DOCK_ICON_SIZE);
        }

        // Draw icon
        if (icon_img) {
            blend_renderer_draw_image(renderer, icon_img, (double)x, (double)cy);
        }

        // Focus bar
        if (focused && focused[i]) {
            blend_renderer_fill_rect(renderer, (double)(x + 2), (double)(cy - FOCUS_BAR_H),
                (double)(DOCK_ICON_SIZE - 4), (double)FOCUS_BAR_H, 0xFF4C7FBF);
        }
    }
}

int dock_icon_at(int w, int h, int top_count, int mouse_x) {
    (void)h;
    int slot = DOCK_ICON_SIZE + DOCK_PAD;
    int total_w = top_count > 0 ? top_count * slot - DOCK_PAD : 0;
    int start_x = (w - total_w) / 2;
    if (start_x < 0) start_x = 0;

    for (int i = 0; i < top_count; i++) {
        int x = icon_x(i, start_x);
        if (mouse_x >= x && mouse_x < x + DOCK_ICON_SIZE + DOCK_PAD) return i;
    }
    return -1;
}
