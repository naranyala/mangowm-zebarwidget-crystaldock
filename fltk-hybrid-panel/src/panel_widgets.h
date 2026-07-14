#pragma once
// panel_widgets.h - FLTK-based offscreen widget rendering
//
// This module uses FLTK's Fl_Image_Surface to render panel widgets
// (clock, CPU meter, memory meter, etc.) to an offscreen RGBA buffer.
// The rendered pixels are then copied to the Wayland SHM buffer.
//
// This is the "hybrid" part: FLTK handles widget rendering,
// raw Wayland handles the panel surface behavior.

#include <cstdint>

class WaylandPanel;

class PanelWidgets {
public:
    PanelWidgets();
    ~PanelWidgets();

    // Initialize FLTK for offscreen rendering.
    // Must be called once before render().
    bool init();

    // Render all widgets to the given ARGB8888 pixel buffer.
    // The buffer is in Wayland's ARGB format (0xAARRGGBB).
    void render(WaylandPanel* panel, uint32_t* buffer, int width, int height, int stride);

    // Handle a click at (x, y) — returns true if a widget handled it.
    bool handle_click(WaylandPanel* panel, int x, int y, uint32_t button);

private:
    bool fltk_initialized_ = false;

    // Widget layout constants
    static constexpr int PADDING = 8;
    static constexpr int WIDGET_GAP = 16;

    // Internal rendering helpers
    void draw_background(uint32_t* buf, int w, int h, int stride);
    void draw_clock(uint32_t* buf, int w, int h, int stride, int x_start, int max_width);
    void draw_cpu_meter(uint32_t* buf, int w, int h, int stride, int x_start, int max_width);
    void draw_memory_meter(uint32_t* buf, int w, int h, int stride, int x_start, int max_width);
    void draw_battery(uint32_t* buf, int w, int h, int stride, int x_start, int max_width);
    void draw_dock(WaylandPanel* panel, uint32_t* buf, int w, int h, int stride, int x_start, int max_width);

    // FLTK offscreen rendering helper: render FLTK drawing commands to ARGB buffer
    void fltk_render_to_buffer(uint32_t* dest, int dest_w, int dest_h, int dest_stride,
                                int region_x, int region_y, int region_w, int region_h,
                                void (*draw_fn)(int w, int h, void* userdata), void* userdata);
};
