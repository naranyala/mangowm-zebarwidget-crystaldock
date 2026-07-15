// icon.c — Desktop file lookup + PNG icon loading via Blend2D
#include "icon.h"
#include "blend2d/blend2d.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>

static const char* desktop_dirs[] = { "/usr/share/applications/", "/usr/local/share/applications/", NULL };
static const char* theme_dirs[] = {
    "/usr/share/icons/hicolor/%dx%d/apps/", "/usr/local/share/icons/hicolor/%dx%d/apps/",
    "/usr/share/icons/Papirus/%dx%d/apps/", "/usr/share/icons/Papirus-Dark/%dx%d/apps/",
    "/usr/share/icons/breeze/apps/%d/", "/usr/share/icons/breeze-dark/apps/%d/",
    "/usr/share/icons/gnome/%dx%d/apps/", "/usr/share/icons/Adwaita/%dx%d/apps/", NULL
};
static const char* scalable_dirs[] = {
    "/usr/share/icons/hicolor/scalable/apps/", "/usr/local/share/icons/hicolor/scalable/apps/",
    "/usr/share/icons/Papirus/scalable/apps/", "/usr/share/icons/Papirus-Dark/scalable/apps/",
    "/usr/share/icons/breeze/apps/scalable/", "/usr/share/icons/breeze-dark/apps/scalable/",
    "/usr/share/icons/gnome/scalable/apps/", "/usr/share/icons/Adwaita/scalable/apps/", NULL
};
static const int icon_sizes[] = { 48, 32, 24, 22, 16, 64, 96, 128, 256 };

#define ICON_CACHE_MAX 64
typedef struct { char app_id[128]; BLImageCore img; bool valid; } CacheEntry;
static CacheEntry icon_cache[ICON_CACHE_MAX], fb_cache[ICON_CACHE_MAX];
static int icon_cache_count, fb_cache_count;

static BLFontFaceCore fb_face;
static bool fb_face_ok, fb_face_tried;
static const char* fallback_fonts[] = {
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf", "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "/usr/share/fonts/noto/NotoSans-Regular.ttf", "/usr/share/fonts/google-noto/NotoSans-Regular.ttf",
    "/usr/share/fonts/gnu-free/FreeSans.ttf", NULL
};

static bool ensure_fb_face(void) {
    if (fb_face_tried) return fb_face_ok;
    fb_face_tried = true;
    for (int i = 0; fallback_fonts[i]; i++)
        if (bl_font_face_create_from_file(&fb_face, fallback_fonts[i], 0) == BL_SUCCESS) { fb_face_ok = true; return true; }
    return false;
}

void icon_init(void) { memset(icon_cache, 0, sizeof(icon_cache)); memset(fb_cache, 0, sizeof(fb_cache)); icon_cache_count = fb_cache_count = 0; }

void icon_clear_cache(void) {
    for (int i = 0; i < icon_cache_count; i++) if (icon_cache[i].valid) bl_image_destroy(&icon_cache[i].img);
    icon_cache_count = 0;
    for (int i = 0; i < fb_cache_count; i++) if (fb_cache[i].valid) bl_image_destroy(&fb_cache[i].img);
    fb_cache_count = 0;
}

static bool path_exists(const char* p) { FILE* f = fopen(p, "r"); if (!f) return false; fclose(f); return true; }

static bool find_desktop_file(const char* app_id, char* buf, int sz) {
    for (int d = 0; desktop_dirs[d]; d++) {
        snprintf(buf, sz, "%s%s.desktop", desktop_dirs[d], app_id);
        if (path_exists(buf)) return true;
        char alt[128]; int al = 0;
        for (const char* p = app_id; *p && al < 127; p++, al++) alt[al] = (*p == '-') ? '.' : *p;
        alt[al] = 0;
        if (al > 0) { snprintf(buf, sz, "%s%s.desktop", desktop_dirs[d], alt); if (path_exists(buf)) return true; }
    }
    return false;
}

static bool read_icon_name(const char* dp, char* out, int osz) {
    char iname[128] = {0}, gname[128] = {0};
    FILE* f = fopen(dp, "r"); if (!f) return false;
    char line[512]; bool in_entry = false;
    while (fgets(line, sizeof(line), f)) {
        size_t len = strlen(line);
        while (len > 0 && (line[len-1]=='\n'||line[len-1]=='\r')) line[--len]=0;
        if (len > 0 && line[0] == '[') { if (in_entry) break; in_entry = true; continue; }
        if (strncmp(line, "Icon=", 5) == 0) snprintf(iname, sizeof(iname), "%s", line+5);
        else if (strncmp(line, "GenericName=", 12) == 0) snprintf(gname, sizeof(gname), "%s", line+12);
    }
    fclose(f);
    if (iname[0]) { snprintf(out, osz, "%s", iname); return true; }
    if (gname[0]) { snprintf(out, osz, "%s", gname); return true; }
    return false;
}

static bool build_path(char* buf, int sz, const char* dir, const char* name, const char* ext) {
    return snprintf(buf, sz, "%s%s%s", dir, name, ext) < sz;
}
static bool build_sized_path(char* buf, int sz, const char* fmt, int s, const char* name, const char* ext) {
    char dir[512]; snprintf(dir, sizeof(dir), fmt, s, s);
    return snprintf(buf, sz, "%s%s%s", dir, name, ext) < sz;
}

static bool try_load_png(const char* icon_name, BLImageCore* out) {
    char buf[1024];
    for (int d = 0; scalable_dirs[d]; d++) {
        if (!build_path(buf, sizeof(buf), scalable_dirs[d], icon_name, ".png")) continue;
        if (bl_image_read_from_file(out, buf, NULL) == BL_SUCCESS) return true;
    }
    for (int s = 0; s < (int)(sizeof(icon_sizes)/sizeof(icon_sizes[0])); s++)
        for (int d = 0; theme_dirs[d]; d++) {
            if (!build_sized_path(buf, sizeof(buf), theme_dirs[d], icon_sizes[s], icon_name, ".png")) continue;
            if (bl_image_read_from_file(out, buf, NULL) == BL_SUCCESS) return true;
        }
    return false;
}

static void cache_icon(const char* id, BLImageCore img) {
    if (icon_cache_count >= ICON_CACHE_MAX) return;
    int len = (int)strlen(id); if (len > 127) len = 127;
    memcpy(icon_cache[icon_cache_count].app_id, id, len);
    icon_cache[icon_cache_count].app_id[len] = 0;
    icon_cache[icon_cache_count].img = img;
    icon_cache[icon_cache_count].valid = true;
    icon_cache_count++;
}
static void cache_fallback(const char* id, BLImageCore img) {
    if (fb_cache_count >= ICON_CACHE_MAX) return;
    int len = (int)strlen(id); if (len > 127) len = 127;
    memcpy(fb_cache[fb_cache_count].app_id, id, len);
    fb_cache[fb_cache_count].app_id[len] = 0;
    fb_cache[fb_cache_count].img = img;
    fb_cache[fb_cache_count].valid = true;
    fb_cache_count++;
}

static uint32_t hue_for(const char* s) { uint32_t h = 0; for (; *s; s++) h = h * 31 + (uint32_t)(unsigned char)*s; return h % 360; }

BLImageCore* icon_fallback(const char* app_id, int size) {
    for (int i = 0; i < fb_cache_count; i++)
        if (strcmp(fb_cache[i].app_id, app_id) == 0 && fb_cache[i].valid) return &fb_cache[i].img;

    BLImageCore img; bl_image_init_as(&img, size, size, BL_FORMAT_PRGB32);
    BLContextCore ctx; bl_context_init_as(&ctx, &img, NULL);

    uint32_t hue = hue_for(app_id);
    double h6 = (double)hue * 6.0 / 360.0; int sext = (int)h6; double frac = h6 - (double)sext;
    double v = 0.6, s = 0.7, p = v*(1-s), q = v*(1-s*frac), t = v*(1-s*(1-frac)), r, g, b;
    switch (sext % 6) { case 0: r=v;g=t;b=p;break; case 1: r=q;g=v;b=p;break; case 2: r=p;g=v;b=t;break;
        case 3: r=p;g=q;b=v;break; case 4: r=t;g=p;b=v;break; default: r=v;g=p;b=q;break; }
    uint32_t color = 0xFF000000 | ((uint32_t)(r*255)<<16) | ((uint32_t)(g*255)<<8) | (uint32_t)(b*255);

    double cx = (double)size/2, cy = (double)size/2, rad = (double)size/2-2, k = 0.5522847498;
    BLPathCore path; bl_path_init(&path);
    bl_path_move_to(&path, cx+rad, cy);
    bl_path_cubic_to(&path, cx+rad, cy+rad*k, cx+rad*k, cy+rad, cx, cy+rad);
    bl_path_cubic_to(&path, cx-rad*k, cy+rad, cx-rad, cy+rad*k, cx-rad, cy);
    bl_path_cubic_to(&path, cx-rad, cy-rad*k, cx-rad*k, cy-rad, cx, cy-rad);
    bl_path_cubic_to(&path, cx+rad*k, cy-rad, cx+rad, cy-rad*k, cx+rad, cy);
    bl_path_close(&path);
    bl_context_set_fill_style_rgba32(&ctx, color);
    BLPoint o = {0,0}; bl_context_fill_path_d(&ctx, &o, &path); bl_path_destroy(&path);

    if (app_id[0]) {
        char letter[2] = { (char)toupper((unsigned char)app_id[0]), 0 };
        BLGlyphBufferCore gb; bl_glyph_buffer_init(&gb);
        bl_glyph_buffer_set_text(&gb, letter, 1, BL_TEXT_ENCODING_UTF8);
        ensure_fb_face();
        if (fb_face_ok) {
            BLFontCore font; bl_font_create_from_face(&font, &fb_face, (float)(size*0.55));
            bl_font_shape(&font, &gb);
            const BLGlyphRun* gr = bl_glyph_buffer_get_glyph_run(&gb);
            bl_context_set_fill_style_rgba32(&ctx, 0xFFFFFFFF);
            BLPoint to = { cx-4, cy+4 }; bl_context_fill_glyph_run_d(&ctx, &to, &font, gr);
            bl_font_destroy(&font);
        }
        bl_glyph_buffer_destroy(&gb);
    }
    bl_context_end(&ctx); bl_context_destroy(&ctx);
    cache_fallback(app_id, img);
    return &fb_cache[fb_cache_count-1].img;
}

bool icon_load(const char* app_id, int size, BLImageCore* out) {
    for (int i = 0; i < icon_cache_count; i++)
        if (strcmp(icon_cache[i].app_id, app_id) == 0 && icon_cache[i].valid) { *out = icon_cache[i].img; return true; }

    char desktop_path[512], icon_name[128] = {0};
    const char* name = app_id;
    if (find_desktop_file(app_id, desktop_path, sizeof(desktop_path)))
        if (read_icon_name(desktop_path, icon_name, sizeof(icon_name))) name = icon_name;

    if (try_load_png(name, out)) { cache_icon(app_id, *out); return true; }
    if (name != app_id && try_load_png(app_id, out)) { cache_icon(app_id, *out); return true; }
    return false;
}
