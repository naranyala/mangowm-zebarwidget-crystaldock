// panel_draw.h — Widget draw functions (C implementation)
#ifndef PANEL_DRAW_H
#define PANEL_DRAW_H

#include <stdint.h>
#include <stdbool.h>

struct BlendRenderer;

// Text rendering helpers
int panel_widget_text(struct BlendRenderer* rend, const char* text, int text_len,
                      int x, int h, double font_size, double cr, double cg, double cb);
void panel_widget_icon_glyph(struct BlendRenderer* rend, const char* glyph, int glyph_len,
                             int x, int h, double cr, double cg, double cb);

// Widget draw functions
void panel_ws_draw(struct BlendRenderer* rend, const char* labels, int labels_len, int x, int h);
void panel_cpu_draw(struct BlendRenderer* rend, const char* txt, int txt_len, int x, int h);
void panel_mem_draw(struct BlendRenderer* rend, const char* txt, int txt_len, int x, int h);
void panel_temp_draw(struct BlendRenderer* rend, const char* txt, int txt_len, int x, int h);
void panel_disk_draw(struct BlendRenderer* rend, const char* txt, int txt_len, int x, int h);
void panel_bat_draw(struct BlendRenderer* rend, const char* txt, int txt_len, int bat_lvl, int x, int h);
void panel_vol_draw(struct BlendRenderer* rend, const char* txt, int txt_len, bool muted, int x, int h);
void panel_net_draw(struct BlendRenderer* rend, const char* txt, int txt_len, int x, int h);
void panel_media_draw(struct BlendRenderer* rend, const char* txt, int txt_len, bool playing, int x, int h);
void panel_clk_draw(struct BlendRenderer* rend, const char* txt, int txt_len, int x, int h);
void panel_launcher_draw(struct BlendRenderer* rend, int x, int h);
void panel_pwr_draw(struct BlendRenderer* rend, int x, int h);
void panel_settings_btn_draw(struct BlendRenderer* rend, int w, int h);

#endif // PANEL_DRAW_H
