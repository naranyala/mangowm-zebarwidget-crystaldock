// panel_widgets.cpp - FLTK offscreen widget rendering for the Wayland panel
//
// Architecture:
//   1. We initialize FLTK's display (it opens its own Wayland connection)
//   2. We use Fl_Image_Surface to render widgets to offscreen RGB buffers
//   3. We convert/copy the rendered pixels to the Wayland SHM buffer
//
// This approach lets us use FLTK's powerful drawing API (text rendering,
// anti-aliased graphics, font handling) while the Wayland layer-shell
// handles the panel behavior.

#include "panel_widgets.h"
#include "system_info.h"
#include "wayland_panel.h"

#include <FL/Fl.H>
#include <FL/Fl_Image_Surface.H>
#include <FL/fl_draw.H>
#include <FL/Fl_RGB_Image.H>
#include <FL/platform.H>
#include <linux/input-event-codes.h>

#include <cstdio>
#include <cstring>
#include <algorithm>
#include <cmath>

// ============================================================================
// ARGB pixel helpers (Wayland uses premultiplied ARGB8888)
// ============================================================================
static inline uint32_t argb(uint8_t a, uint8_t r, uint8_t g, uint8_t b) {
    return ((uint32_t)a << 24) | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
}

static void fill_rect(uint32_t* buf, int buf_w, int stride_bytes,
                      int x, int y, int w, int h, uint32_t color) {
    int stride_px = stride_bytes / 4;
    for (int row = y; row < y + h && row < buf_w; row++) {
        for (int col = x; col < x + w; col++) {
            if (col >= 0 && col < buf_w && row >= 0)
                buf[row * stride_px + col] = color;
        }
    }
}

// ============================================================================
// PanelWidgets
// ============================================================================
PanelWidgets::PanelWidgets() {}

PanelWidgets::~PanelWidgets() {}

bool PanelWidgets::init() {
    if (fltk_initialized_) return true;

    // Initialize FLTK display — this opens FLTK's own Wayland connection.
    // We never create visible FLTK windows; we only use offscreen rendering.
    fl_open_display();
    fltk_initialized_ = true;
    fprintf(stdout, "[OK] FLTK initialized for offscreen rendering\n");
    return true;
}

// ============================================================================
// fltk_render_to_buffer — Render FLTK drawing commands to a region of the
//                         Wayland ARGB buffer using Fl_Image_Surface
// ============================================================================
void PanelWidgets::fltk_render_to_buffer(
        uint32_t* dest, int dest_w, int dest_h, int dest_stride,
        int region_x, int region_y, int region_w, int region_h,
        void (*draw_fn)(int w, int h, void* userdata), void* userdata) {

    // Create an offscreen FLTK surface
    Fl_Image_Surface* surface = new Fl_Image_Surface(region_w, region_h);
    surface->set_current();

    // Execute the drawing commands
    draw_fn(region_w, region_h, userdata);

    // Capture the rendered image
    Fl_RGB_Image* img = surface->image();
    Fl_Display_Device::display_device()->set_current();
    delete surface;

    if (!img) return;

    // Copy FLTK's RGB(A) pixels into our ARGB buffer
    const unsigned char* src = (const unsigned char*)img->data()[0];
    int channels = img->d();  // 3=RGB, 4=RGBA
    int dest_stride_px = dest_stride / 4;

    for (int y = 0; y < region_h && (region_y + y) < dest_h; y++) {
        for (int x = 0; x < region_w && (region_x + x) < dest_w; x++) {
            int src_idx = (y * region_w + x) * channels;
            uint8_t r = src[src_idx];
            uint8_t g = src[src_idx + 1];
            uint8_t b = src[src_idx + 2];
            uint8_t a = (channels >= 4) ? src[src_idx + 3] : 255;

            int dest_idx = (region_y + y) * dest_stride_px + (region_x + x);
            dest[dest_idx] = argb(a, r, g, b);
        }
    }

    delete img;
}

// ============================================================================
// render() — Main render function, called each frame
// ============================================================================
void PanelWidgets::render(WaylandPanel* panel, uint32_t* buffer, int width, int height, int stride) {
    if (!fltk_initialized_) return;

    // 1. Draw background (dark translucent panel)
    draw_background(buffer, width, height, stride);

    // 2. Layout: [PADDING] [Clock] [GAP] [CPU] [GAP] [Memory] ... [Dock] ... [Battery] [PADDING]
    int x_cursor = PADDING;
    int widget_height = height - 4;  // 2px top/bottom margin

    // Left side: Clock
    int clock_width = 120;
    draw_clock(buffer, width, height, stride, x_cursor, clock_width);
    x_cursor += clock_width + WIDGET_GAP;

    // Separator
    fill_rect(buffer, width, stride, x_cursor, 4, 1, height - 8, argb(180, 100, 100, 120));
    x_cursor += 1 + WIDGET_GAP;

    // Center-left: CPU meter
    int cpu_width = 160;
    draw_cpu_meter(buffer, width, height, stride, x_cursor, cpu_width);
    x_cursor += cpu_width + WIDGET_GAP;

    // Separator
    fill_rect(buffer, width, stride, x_cursor, 4, 1, height - 8, argb(180, 100, 100, 120));
    x_cursor += 1 + WIDGET_GAP;

    // Center-right: Memory meter
    int mem_width = 180;
    draw_memory_meter(buffer, width, height, stride, x_cursor, mem_width);
    x_cursor += mem_width + WIDGET_GAP;

    // Separator
    fill_rect(buffer, width, stride, x_cursor, 4, 1, height - 8, argb(180, 100, 100, 120));
    x_cursor += 1 + WIDGET_GAP;

    // Right side: Battery (anchored to right edge)
    int battery_width = 100;
    int battery_x = width - PADDING - battery_width;
    draw_battery(buffer, width, height, stride, battery_x, battery_width);

    // Separator before battery
    fill_rect(buffer, width, stride, battery_x - WIDGET_GAP, 4, 1, height - 8, argb(180, 100, 100, 120));

    // Middle area: Dock
    int dock_width = (battery_x - WIDGET_GAP) - x_cursor - WIDGET_GAP;
    if (dock_width > 0) {
        draw_dock(panel, buffer, width, height, stride, x_cursor, dock_width);
    }
}

// ============================================================================
// draw_background — Dark semi-transparent background
// ============================================================================
void PanelWidgets::draw_background(uint32_t* buf, int w, int h, int stride) {
    int stride_px = stride / 4;
    uint32_t bg_color = argb(220, 30, 30, 40);  // Dark blue-grey, slightly transparent

    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            buf[y * stride_px + x] = bg_color;
        }
    }

    // Bottom border (subtle highlight line)
    uint32_t border_color = argb(255, 60, 60, 80);
    for (int x = 0; x < w; x++) {
        buf[(h - 1) * stride_px + x] = border_color;
    }
}

// ============================================================================
// draw_clock — Render time using FLTK text rendering
// ============================================================================
struct ClockDrawData {
    std::string time_str;
    std::string date_str;
};

static void draw_clock_fn(int w, int h, void* userdata) {
    auto* data = static_cast<ClockDrawData*>(userdata);

    // Transparent background
    fl_color(30, 30, 40);
    fl_rectf(0, 0, w, h);

    // Time text (large, white)
    fl_color(FL_WHITE);
    fl_font(FL_HELVETICA_BOLD, 15);
    fl_draw(data->time_str.c_str(), 4, 18);

    // Date text (smaller, grey)
    fl_color(180, 180, 200);
    fl_font(FL_HELVETICA, 10);
    fl_draw(data->date_str.c_str(), 4, 28);
}

void PanelWidgets::draw_clock(uint32_t* buf, int w, int h, int stride,
                               int x_start, int max_width) {
    ClockDrawData data;
    data.time_str = SystemInfo::current_time("%H:%M:%S");
    data.date_str = SystemInfo::current_date("%a %b %d");

    fltk_render_to_buffer(buf, w, h, stride,
                          x_start, 1, max_width, h - 2,
                          draw_clock_fn, &data);
}

// ============================================================================
// draw_cpu_meter — CPU usage bar with percentage
// ============================================================================
struct MeterDrawData {
    std::string label;
    double percentage;
    uint8_t bar_r, bar_g, bar_b;
};

static void draw_meter_fn(int w, int h, void* userdata) {
    auto* data = static_cast<MeterDrawData*>(userdata);

    // Background
    fl_color(30, 30, 40);
    fl_rectf(0, 0, w, h);

    // Label
    fl_color(180, 180, 200);
    fl_font(FL_HELVETICA, 11);
    fl_draw(data->label.c_str(), 4, 12);

    // Bar background
    int bar_x = 4;
    int bar_y = 16;
    int bar_w = w - 8;
    int bar_h = h - 20;
    fl_color(50, 50, 60);
    fl_rectf(bar_x, bar_y, bar_w, bar_h);

    // Filled portion
    int fill_w = (int)(bar_w * data->percentage / 100.0);
    fl_color(data->bar_r, data->bar_g, data->bar_b);
    fl_rectf(bar_x, bar_y, fill_w, bar_h);

    // Percentage text on bar
    char pct_str[16];
    snprintf(pct_str, sizeof(pct_str), "%.0f%%", data->percentage);
    fl_color(FL_WHITE);
    fl_font(FL_HELVETICA_BOLD, 10);
    fl_draw(pct_str, bar_x + 4, bar_y + bar_h - 2);
}

void PanelWidgets::draw_cpu_meter(uint32_t* buf, int w, int h, int stride,
                                   int x_start, int max_width) {
    MeterDrawData data;
    data.label = "CPU";
    data.percentage = SystemInfo::cpu_usage();
    // Color: green when low, yellow when medium, red when high
    if (data.percentage < 50.0) {
        data.bar_r = 80; data.bar_g = 200; data.bar_b = 120;  // Green
    } else if (data.percentage < 80.0) {
        data.bar_r = 220; data.bar_g = 180; data.bar_b = 50;  // Yellow
    } else {
        data.bar_r = 220; data.bar_g = 60; data.bar_b = 60;   // Red
    }

    fltk_render_to_buffer(buf, w, h, stride,
                          x_start, 1, max_width, h - 2,
                          draw_meter_fn, &data);
}

// ============================================================================
// draw_memory_meter — Memory usage bar
// ============================================================================
void PanelWidgets::draw_memory_meter(uint32_t* buf, int w, int h, int stride,
                                      int x_start, int max_width) {
    MeterDrawData data;
    char label[64];
    snprintf(label, sizeof(label), "MEM %.1f/%.1fG",
             SystemInfo::memory_used_gb(), SystemInfo::memory_total_gb());
    data.label = label;
    data.percentage = SystemInfo::memory_usage_percent();
    data.bar_r = 100; data.bar_g = 140; data.bar_b = 220;  // Blue

    fltk_render_to_buffer(buf, w, h, stride,
                          x_start, 1, max_width, h - 2,
                          draw_meter_fn, &data);
}

// ============================================================================
// draw_battery — Battery indicator
// ============================================================================
struct BatteryDrawData {
    int percent;
    bool charging;
};

static void draw_battery_fn(int w, int h, void* userdata) {
    auto* data = static_cast<BatteryDrawData*>(userdata);

    // Background
    fl_color(30, 30, 40);
    fl_rectf(0, 0, w, h);

    if (data->percent < 0) {
        // No battery
        fl_color(100, 100, 120);
        fl_font(FL_HELVETICA, 11);
        fl_draw("AC Power", 4, h / 2 + 4);
        return;
    }

    // Battery icon (simple rectangle)
    int bat_x = 4, bat_y = 6;
    int bat_w = w - 24, bat_h = h - 12;

    // Outline
    fl_color(150, 150, 170);
    fl_rect(bat_x, bat_y, bat_w, bat_h);
    // Nub
    fl_rectf(bat_x + bat_w, bat_y + bat_h / 4, 3, bat_h / 2);

    // Fill
    int fill_w = (int)((bat_w - 4) * data->percent / 100.0);
    if (data->percent > 50)
        fl_color(80, 200, 120);
    else if (data->percent > 20)
        fl_color(220, 180, 50);
    else
        fl_color(220, 60, 60);
    fl_rectf(bat_x + 2, bat_y + 2, fill_w, bat_h - 4);

    // Percentage text
    char txt[16];
    snprintf(txt, sizeof(txt), "%d%%%s", data->percent, data->charging ? "+" : "");
    fl_color(FL_WHITE);
    fl_font(FL_HELVETICA, 10);
    fl_draw(txt, bat_x + bat_w + 6, h / 2 + 4);
}

void PanelWidgets::draw_battery(uint32_t* buf, int w, int h, int stride,
                                 int x_start, int max_width) {
    BatteryDrawData data;
    data.percent  = SystemInfo::battery_percent();
    data.charging = SystemInfo::battery_charging();

    fltk_render_to_buffer(buf, w, h, stride,
                          x_start, 1, max_width, h - 2,
                          draw_battery_fn, &data);
}

// ============================================================================
// handle_click — Route click to widget regions
// ============================================================================
// ============================================================================
// handle_click() — Updated to handle dock clicks
// ============================================================================
bool PanelWidgets::handle_click(WaylandPanel* panel, int x, int y, uint32_t button) {
    printf("[Click] x=%d, y=%d button=%d\n", x, y, button);

    // Simplistic click detection for the dock
    // Our layout puts the dock between the memory meter and the battery.
    // Let's re-calculate its position roughly based on the render sizes:
    int x_cursor = PADDING + 120 + WIDGET_GAP + 1 + WIDGET_GAP + 160 + WIDGET_GAP + 1 + WIDGET_GAP + 180 + WIDGET_GAP + 1 + WIDGET_GAP;
    int battery_x = panel->width() - PADDING - 100;
    int dock_width = (battery_x - WIDGET_GAP) - x_cursor - WIDGET_GAP;

    if (x >= x_cursor && x <= x_cursor + dock_width) {
        // Find which window was clicked
        if (!panel->windows().empty()) {
            int win_width = 150;
            int max_windows = dock_width / (win_width + 4);
            int visible_windows = std::min((int)panel->windows().size(), max_windows);
            if (visible_windows == 0) visible_windows = panel->windows().size();
            
            // Adjust win_width if they don't fit
            if (visible_windows * (win_width + 4) > dock_width) {
                win_width = (dock_width / visible_windows) - 4;
            }

            for (int i = 0; i < visible_windows; i++) {
                int wx = x_cursor + i * (win_width + 4);
                if (x >= wx && x <= wx + win_width) {
                    WindowInfo* win = panel->windows()[i];
                    if (button == BTN_LEFT) {
                        if (win->activated) {
                            // If it's already active, we could minimize it (not supported directly by standard toplevel activate without minimize request)
                        } else {
                            panel->activate_window(win);
                        }
                    } else if (button == BTN_RIGHT) {
                        panel->close_window(win);
                    }
                    return true;
                }
            }
        }
    }

    return false;
}

// ============================================================================
// draw_dock — Draws running apps via WaylandPanel's window list
// ============================================================================
void PanelWidgets::draw_dock(WaylandPanel* panel, uint32_t* buf, int w, int h, int stride, int x_start, int max_width) {
    if (!panel) return;
    const auto& windows = panel->windows();
    if (windows.empty()) return;

    struct DockData {
        const std::vector<WindowInfo*>* wins;
    } data = { &windows };

    fltk_render_to_buffer(buf, w, h, stride, x_start, 2, max_width, h - 4,
        [](int rw, int rh, void* userdata) {
            auto* d = static_cast<DockData*>(userdata);
            
            fl_font(FL_HELVETICA, 12);
            int win_width = 150;
            int num_wins = d->wins->size();
            
            // simple layout
            int max_wins = rw / (win_width + 4);
            int visible = std::min(num_wins, max_wins);
            if (visible == 0) return;
            
            if (visible * (win_width + 4) > rw) {
                win_width = (rw / visible) - 4;
            }

            for (int i = 0; i < visible; i++) {
                WindowInfo* win = (*d->wins)[i];
                int wx = i * (win_width + 4);
                
                // Draw button background
                if (win->activated) {
                    fl_color(60, 140, 220); // Active color
                } else if (win->minimized) {
                    fl_color(40, 40, 40); // Minimized color
                } else {
                    fl_color(80, 80, 80); // Inactive color
                }
                
                fl_rectf(wx, 0, win_width, rh);
                fl_color(100, 100, 100);
                fl_rect(wx, 0, win_width, rh);

                // Draw text
                fl_color(FL_WHITE);
                
                std::string display_text = win->title.empty() ? win->app_id : win->title;
                if (display_text.empty()) display_text = "Unknown";
                
                // Truncate text if needed
                int tw = 0, th = 0;
                fl_measure(display_text.c_str(), tw, th, 0);
                if (tw > win_width - 8) {
                    while (display_text.length() > 3 && tw > win_width - 16) {
                        display_text.pop_back();
                        fl_measure((display_text + "...").c_str(), tw, th, 0);
                    }
                    display_text += "...";
                }

                fl_draw(display_text.c_str(), wx + 4, rh - 8);
            }
        },
        &data);
}
