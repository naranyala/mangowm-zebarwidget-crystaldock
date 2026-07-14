// main.cpp - FLTK Hybrid Panel for Wayland
//
// This is an exploration project demonstrating how to build a Wayland panel
// using a hybrid architecture:
//
//   ┌─────────────────────────────────────────────────┐
//   │  Raw Wayland Client (this code)                 │
//   │  ├── wl_display / wl_registry                   │
//   │  ├── zwlr_layer_shell_v1  → panel behavior      │
//   │  └── wl_surface + SHM buffer                    │
//   │       └── FLTK renders widgets via offscreen     │
//   │           Fl_Image_Surface → pixel copy to SHM   │
//   └─────────────────────────────────────────────────┘
//
// Why hybrid?
//   - FLTK doesn't support wlr-layer-shell natively
//   - We use raw Wayland for the panel "container" (layer-shell surface)
//   - We use FLTK for widget rendering (text, shapes, etc.) via offscreen
//   - Best of both worlds: proper panel behavior + FLTK's widget toolkit
//
// Usage:
//   ./fltk-panel [--bottom] [--height N]

#include "wayland_panel.h"
#include "panel_widgets.h"

#include <cstdio>
#include <cstring>
#include <csignal>
#include <unistd.h>

// Global flag for signal handling
static volatile sig_atomic_t g_running = 1;

static void signal_handler(int /*sig*/) {
    g_running = 0;
}

static void print_usage(const char* prog) {
    fprintf(stderr, "Usage: %s [OPTIONS]\n", prog);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  --top        Anchor panel to top edge (default)\n");
    fprintf(stderr, "  --bottom     Anchor panel to bottom edge\n");
    fprintf(stderr, "  --height N   Panel height in pixels (default: 32)\n");
    fprintf(stderr, "  --help       Show this help\n");
}

int main(int argc, char* argv[]) {
    // ── Parse arguments ──
    WaylandPanel::Config config;
    config.height = 32;
    config.anchor_top = true;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--bottom") == 0) {
            config.anchor_top = false;
        } else if (strcmp(argv[i], "--top") == 0) {
            config.anchor_top = true;
        } else if (strcmp(argv[i], "--height") == 0 && i + 1 < argc) {
            config.height = atoi(argv[++i]);
            if (config.height < 20) config.height = 20;
            if (config.height > 100) config.height = 100;
        } else if (strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            print_usage(argv[0]);
            return 1;
        }
    }

    fprintf(stdout, "┌──────────────────────────────────────┐\n");
    fprintf(stdout, "│   FLTK Hybrid Panel for Wayland      │\n");
    fprintf(stdout, "│   Layer: top   Height: %dpx          │\n", config.height);
    fprintf(stdout, "│   Position: %-6s                   │\n", config.anchor_top ? "top" : "bottom");
    fprintf(stdout, "└──────────────────────────────────────┘\n");

    // ── Signal handling ──
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    // ── Initialize Wayland panel ──
    WaylandPanel panel(config);
    if (!panel.init()) {
        fprintf(stderr, "[FATAL] Failed to initialize Wayland panel\n");
        return 1;
    }

    // ── Initialize FLTK widgets ──
    PanelWidgets widgets;
    if (!widgets.init()) {
        fprintf(stderr, "[FATAL] Failed to initialize FLTK widgets\n");
        return 1;
    }

    // ── Connect render callback ──
    // This is called each frame by the Wayland panel.
    // The PanelWidgets class renders using FLTK offscreen,
    // then copies pixels into the Wayland SHM buffer.
    panel.set_render_callback([&widgets, &panel](uint32_t* buffer, int w, int h, int stride) {
        widgets.render(&panel, buffer, w, h, stride);
    });

    // ── Connect click callback ──
    panel.set_click_callback([&widgets, &panel](int x, int y, uint32_t button) {
        widgets.handle_click(&panel, x, y, button);
    });

    // ── Run the event loop ──
    // The panel will continuously:
    //   1. Dispatch Wayland events
    //   2. On frame callback: call our render function
    //   3. Render function uses FLTK to draw widgets offscreen
    //   4. Copy rendered pixels to Wayland SHM buffer
    //   5. Commit the surface
    panel.run();

    fprintf(stdout, "[OK] Panel exited cleanly\n");
    return 0;
}
