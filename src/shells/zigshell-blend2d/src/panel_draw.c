// panel_draw.c — Widget draw functions (C implementation)
#include "panel_draw.h"
#include "blend2d_render.h"
#include <math.h>

int panel_widget_text(struct BlendRenderer* rend, const char* text, int text_len,
                      int x, int h, double font_size, double cr, double cg, double cb) {
    blend_renderer_set_font_size(rend, font_size);
    uint32_t color = 0xFF000000 | ((uint32_t)(cr * 255) << 16) | ((uint32_t)(cg * 255) << 8) | (uint32_t)(cb * 255);
    TextMetrics tm = blend_renderer_measure_text(rend, text, text_len);
    int y_offset = (h - (int)tm.height) / 2;
    blend_renderer_draw_text(rend, text, text_len, (double)x, (double)y_offset, color);
    return (int)tm.width;
}

void panel_widget_icon_glyph(struct BlendRenderer* rend, const char* glyph, int glyph_len,
                             int x, int h, double cr, double cg, double cb) {
    panel_widget_text(rend, glyph, glyph_len, x, h, 11.0, cr, cg, cb);
}

void panel_ws_draw(struct BlendRenderer* rend, const char* labels, int labels_len, int x, int h) {
    panel_widget_text(rend, labels, labels_len, x, h, 10.0, 0.6, 0.6, 0.7);
}

void panel_cpu_draw(struct BlendRenderer* rend, const char* txt, int txt_len, int x, int h) {
    double bar_w = 60.0, bar_h = (double)(h - 16), bar_y = 8.0;
    blend_renderer_fill_rect(rend, (double)x, bar_y, bar_w, bar_h, 0xFF262633);
    panel_widget_text(rend, txt, txt_len, x + 4, h, 9.0, 1.0, 1.0, 1.0);
}

void panel_mem_draw(struct BlendRenderer* rend, const char* txt, int txt_len, int x, int h) {
    double bar_w = 70.0, bar_h = (double)(h - 16), bar_y = 8.0;
    blend_renderer_fill_rect(rend, (double)x, bar_y, bar_w, bar_h, 0xFF262633);
    panel_widget_text(rend, txt, txt_len, x + 4, h, 9.0, 1.0, 1.0, 1.0);
}

void panel_temp_draw(struct BlendRenderer* rend, const char* txt, int txt_len, int x, int h) {
    panel_widget_icon_glyph(rend, "\xe2\x99\x81", 3, x, h, 0.9, 0.6, 0.4);
    panel_widget_text(rend, txt, txt_len, x + 16, h, 9.0, 0.8, 0.8, 0.82);
}

void panel_disk_draw(struct BlendRenderer* rend, const char* txt, int txt_len, int x, int h) {
    panel_widget_icon_glyph(rend, "\xe2\xa5\xa5", 3, x, h, 0.5, 0.8, 0.6);
    panel_widget_text(rend, txt, txt_len, x + 16, h, 9.0, 0.8, 0.8, 0.82);
}

void panel_bat_draw(struct BlendRenderer* rend, const char* txt, int txt_len, int bat_lvl, int x, int h) {
    double bat_w = 24.0, bat_h = 14.0, bat_y = (double)((h - 14) / 2);
    blend_renderer_draw_border(rend, (double)x, bat_y, bat_w, bat_h, 0xFF9999A6);
    blend_renderer_fill_rect(rend, (double)x + bat_w, bat_y + 4.0, 2.0, bat_h - 8.0, 0xFF9999A6);
    if (bat_lvl >= 0) {
        double fill_w = (bat_w - 4.0) * (double)bat_lvl / 100.0;
        uint32_t c = bat_lvl > 50 ? 0xFF4CCC7F : bat_lvl > 20 ? 0xFFE6B333 : 0xFFE63333;
        blend_renderer_fill_rect(rend, (double)x + 2.0, bat_y + 2.0, fill_w, bat_h - 4.0, c);
    }
    panel_widget_text(rend, txt, txt_len, x + 30, h, 9.0, 0.8, 0.8, 0.82);
}

void panel_vol_draw(struct BlendRenderer* rend, const char* txt, int txt_len, bool muted, int x, int h) {
    panel_widget_icon_glyph(rend, muted ? "\xf0\x9f\x94\x87" : "\xf0\x9f\x94\x8a", 4, x, h, 0.6, 0.8, 0.9);
    panel_widget_text(rend, txt, txt_len, x + 18, h, 9.0, 0.8, 0.8, 0.82);
}

void panel_net_draw(struct BlendRenderer* rend, const char* txt, int txt_len, int x, int h) {
    panel_widget_icon_glyph(rend, "\xf0\x9f\x93\xb6", 4, x, h, 0.5, 0.9, 0.6);
    panel_widget_text(rend, txt, txt_len, x + 18, h, 9.0, 0.8, 0.8, 0.82);
}

void panel_media_draw(struct BlendRenderer* rend, const char* txt, int txt_len, bool playing, int x, int h) {
    if (txt_len == 0) return;
    panel_widget_icon_glyph(rend, playing ? "\xe2\x96\xb6" : "\xe2\x9d\x9c", 3, x, h, 0.9, 0.8, 0.4);
    panel_widget_text(rend, txt, txt_len, x + 18, h, 9.0, 0.85, 0.85, 0.88);
}

void panel_clk_draw(struct BlendRenderer* rend, const char* txt, int txt_len, int x, int h) {
    panel_widget_text(rend, txt, txt_len, x, h, 10.0, 0.85, 0.85, 0.85);
}

void panel_launcher_draw(struct BlendRenderer* rend, int x, int h) {
    panel_widget_icon_glyph(rend, "\xe2\x8c\x98", 3, x + 4, h, 0.8, 0.8, 0.85);
}

void panel_pwr_draw(struct BlendRenderer* rend, int x, int h) {
    panel_widget_icon_glyph(rend, "\xe2\x8f\xbb", 3, x + 4, h, 0.9, 0.5, 0.5);
}

void panel_settings_btn_draw(struct BlendRenderer* rend, int w, int h) {
    int btn_x = w - 32;
    blend_renderer_fill_rect(rend, (double)btn_x, 0, 28, (double)h, 0xCC4D4D59);
    blend_renderer_draw_text(rend, "\xe2\x9a\x99", 3, (double)(btn_x + 8), (double)h / 2.0 - 6, 0xFFD9D9E0);
}
