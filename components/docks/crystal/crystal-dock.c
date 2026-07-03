/* docks/crystal/crystal-dock.c - Crystal Wayland dock */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>
#include "widget.h"

/* Crystal dock state */
typedef struct {
    wayland_display_t *display;
    wayland_surface_t *surface;
    
    /* Widget instances (app icons) */
    struct {
        char *name;
        char *class;
        int icon_width;
        int icon_height;
        bool focused;
    } *widgets;
    int widget_count;
    
    /* Dock configuration */
    int height;
    char position;  /* 't'op, 'b'ottom */
    bool auto_hide;
    widget_theme_t theme;
} crystal_dock_t;

static crystal_dock_t state;
static volatile sig_atomic_t running = 1;

/* Signal handler */
static void signal_handler(int sig) {
    if (sig == SIGHUP) {
        char *home = getenv("HOME");
        if (home) {
            char path[256];
            snprintf(path, sizeof(path), "%s/.config/labwc/themerc-override", home);
            theme_load_from_ini(&state.theme, path);
        }
    } else {
        running = 0;
    }
}

/* Render dock widget (application icon) */
static void render_dock_widget(cairo_t *cr, PangoLayout *layout, const char *name, 
                               bool focused, int x, int y, int width, int height,
                               const widget_theme_t *theme) {
    /* Dock background */
    if (focused) {
        double r, g, b, a;
        hex_to_rgba(theme->accent, &r, &g, &b, &a);
        cairo_set_source_rgba(cr, r, g, b, 0.2);
        cairo_rectangle(cr, x, y, width, height);
        cairo_fill(cr);
    }
    
    /* Icon placeholder (could be loaded from icon theme) */
    cairo_set_source_rgba(cr, 0.6, 0.6, 0.6, 1.0);
    cairo_rectangle(cr, x + 8, y + 8, width - 16, height - 16);
    cairo_fill(cr);
    
    /* Application name */
    PangoFontDescription *desc = pango_font_description_from_string("JetBrains Mono");
    pango_font_description_set_size(desc, 10 * PANGO_SCALE);
    pango_layout_set_font_description(layout, desc);
    pango_layout_set_text(layout, name, -1);
    
    double r, g, b, a;
    hex_to_rgba(theme->fg, &r, &g, &b, &a);
    cairo_set_source_rgba(cr, r, g, b, 1.0);
    
    PangoRectangle ink;
    pango_layout_get_pixel_extents(layout, &ink, NULL);
    
    int text_x = x + (width - ink.width) / 2;
    int text_y = y + height - 8;
    cairo_move_to(cr, text_x, text_y);
    pango_cairo_show_layout(cr, layout);
    
    pango_font_description_free(desc);
}

/* Render the entire dock */
static void render_dock(crystal_dock_t *dock) {
    if (!dock->surface) return;
    
    cairo_surface_t *cairo_surface = wayland_surface_get_cairo(dock->surface);
    if (!cairo_surface) return;
    
    cairo_t *cr = cairo_create(cairo_surface);
    if (!cr) return;
    
    int width, height;
    wayland_surface_get_size(dock->surface, &width, &height);
    
    /* Background */
    cairo_set_source_rgba(cr, 0.1, 0.1, 0.1, 0.95);
    cairo_paint(cr);
    
    /* Create layout for text rendering */
    PangoLayout *layout = pango_cairo_create_layout(cr);
    
    /* Render dock widgets */
    int x = 12;
    for (int i = 0; i < dock->widget_count; i++) {
        int widget_width = 64;
        render_dock_widget(cr, layout, dock->widgets[i].name, dock->widgets[i].focused,
                          x, 12, widget_width, height - 24);
        x += widget_width + 8;
    }
    
    g_object_unref(layout);
    cairo_destroy(cr);
}

/* Initialize dock */
static int init_crystal_dock(crystal_dock_t *dock) {
    /* Load theme */
    theme_init_default(&dock->theme);
    char *home = getenv("HOME");
    if (home) {
        char path[256];
        snprintf(path, sizeof(path), "%s/.config/labwc/themerc-override", home);
        theme_load_from_ini(&dock->theme, path);
    }
    
    /* Default dock config */
    dock->height = 56;
    dock->position = 'b';
    dock->auto_hide = false;
    
    /* Create Wayland display */
    dock->display = wayland_display_create();
    if (!dock->display) return -1;
    
    /* Create layer surface */
    layer_anchor_t anchor = LAYER_ANCHOR_LEFT | LAYER_ANCHOR_RIGHT;
    if (dock->position == 't') {
        anchor = LAYER_ANCHOR_TOP | LAYER_ANCHOR_LEFT | LAYER_ANCHOR_RIGHT;
    } else {
        anchor = LAYER_ANCHOR_BOTTOM | LAYER_ANCHOR_LEFT | LAYER_ANCHOR_RIGHT;
    }
    
    dock->surface = wayland_surface_create(
        dock->display,
        LAYER_TOP,
        anchor,
        dock->height,
        1920,
        dock->height
    );
    
    if (!dock->surface) {
        wayland_display_destroy(dock->display);
        return -1;
    }
    
    /* Initialize sample widgets */
    dock->widget_count = 4;
    dock->widgets = calloc(dock->widget_count, sizeof(*dock->widgets));
    
    if (dock->widgets) {
        const char *names[] = {"foot", "foot", "thunar", "rofi"};
        for (int i = 0; i < dock->widget_count; i++) {
            dock->widgets[i].name = strdup(names[i]);
            dock->widgets[i].class = NULL;
            dock->widgets[i].icon_width = 48;
            dock->widgets[i].icon_height = 48;
            dock->widgets[i].focused = (i == 0);
        }
    }
    
    return 0;
}

/* Cleanup dock */
static void cleanup_crystal_dock(crystal_dock_t *dock) {
    if (dock->widgets) {
        for (int i = 0; i < dock->widget_count; i++) {
            free(dock->widgets[i].name);
            free(dock->widgets[i].class);
        }
        free(dock->widgets);
    }
    
    if (dock->surface) wayland_surface_destroy(dock->surface);
    if (dock->display) wayland_display_destroy(dock->display);
}

/* Main loop */
static void run_crystal_dock(crystal_dock_t *dock) {
    struct timespec last_update = {0, 0};
    struct timespec now;
    
    while (running) {
        clock_gettime(CLOCK_MONOTONIC, &now);
        
        if (now.tv_sec != last_update.tv_sec) {
            /* Update dock state (focus, etc.) */
            last_update = now;
        }
        
        render_dock(dock);
        wayland_surface_commit(dock->surface);
        wl_display_dispatch(dock->display->display);
        
        usleep(100000);
    }
}

/* Entry point */
int main(int argc, char *argv[]) {
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    signal(SIGHUP, signal_handler);

    
    if (init_crystal_dock(&state) != 0) {
        fprintf(stderr, "Failed to initialize crystal dock\n");
        return 1;
    }
    
    fprintf(stderr, "crystal-dock: starting\n");
    
    run_crystal_dock(&state);
    
    cleanup_crystal_dock(&state);
    fprintf(stderr, "crystal-dock: stopped\n");
    
    return 0;
}
