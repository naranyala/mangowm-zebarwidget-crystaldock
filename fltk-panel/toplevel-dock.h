// Toplevel window tracker and dock widget for FLTK Wayland panel
// Tracks running windows via wlr-foreign-toplevel-management protocol
// Creates dock buttons for app switching

#ifndef TOPLEVEL_DOCK_H
#define TOPLEVEL_DOCK_H

#include <wayland-client.h>
#include <string>
#include <vector>
#include <functional>

// Include generated protocol header for listener types
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

// Forward declare protocol types
struct zwlr_foreign_toplevel_manager_v1;
struct zwlr_foreign_toplevel_handle_v1;

// Maximum tracked windows
static const int MAX_TOPLEVELS = 64;

// Window info
struct ToplevelInfo {
    zwlr_foreign_toplevel_handle_v1 *handle;
    char title[256];
    char app_id[256];
    bool focused;
    bool minimized;
    bool maximized;
    bool fullscreen;
    bool alive;
};

// Toplevel tracker - manages Wayland protocol for window tracking
class ToplevelTracker {
public:
    ToplevelTracker();
    ~ToplevelTracker();

    // Initialize with Wayland display
    bool init(wl_display *display);

    // Poll for events (call periodically)
    void poll();

    // Get window list
    const std::vector<ToplevelInfo>& get_windows() const { return windows; }
    int count() const { return windows.size(); }

    // Actions
    void activate(zwlr_foreign_toplevel_handle_v1 *handle);
    void close(zwlr_foreign_toplevel_handle_v1 *handle);
    void minimize(zwlr_foreign_toplevel_handle_v1 *handle);
    void maximize(zwlr_foreign_toplevel_handle_v1 *handle);

    // Get seat for activation
    wl_seat *get_seat() const { return seat; }

    // Set callback for window list changes
    void set_change_callback(std::function<void()> cb) { change_callback = cb; }

    // Check if dirty (needs redraw)
    bool is_dirty() const { return dirty; }
    void clear_dirty() { dirty = false; }

private:
    std::vector<ToplevelInfo> windows;
    std::function<void()> change_callback;
    bool dirty = false;

    // Wayland objects
    wl_display *display = nullptr;
    wl_registry *registry = nullptr;
    wl_compositor *compositor = nullptr;
    wl_seat *seat = nullptr;
    zwlr_foreign_toplevel_manager_v1 *manager = nullptr;

    // Find window by handle
    int find_index(zwlr_foreign_toplevel_handle_v1 *handle);

    // Remove window by index
    void remove_at(int index);

    // Static protocol callbacks
    static void registry_global(void *data, wl_registry *registry,
                                 uint32_t name, const char *interface, uint32_t version);
    static void registry_global_remove(void *data, wl_registry *registry, uint32_t name);

    static void manager_toplevel(void *data, zwlr_foreign_toplevel_manager_v1 *manager,
                                  zwlr_foreign_toplevel_handle_v1 *handle);
    static void manager_finished(void *data, zwlr_foreign_toplevel_manager_v1 *manager);

    static void handle_title(void *data, zwlr_foreign_toplevel_handle_v1 *handle,
                              const char *title);
    static void handle_app_id(void *data, zwlr_foreign_toplevel_handle_v1 *handle,
                               const char *app_id);
    static void handle_state(void *data, zwlr_foreign_toplevel_handle_v1 *handle,
                              wl_array *state);
    static void handle_done(void *data, zwlr_foreign_toplevel_handle_v1 *handle);
    static void handle_closed(void *data, zwlr_foreign_toplevel_handle_v1 *handle);
    static void handle_output_enter(void *data, zwlr_foreign_toplevel_handle_v1 *handle,
                                     wl_output *output);
    static void handle_output_leave(void *data, zwlr_foreign_toplevel_handle_v1 *handle,
                                     wl_output *output);

    static const zwlr_foreign_toplevel_manager_v1_listener manager_listener;
    static const zwlr_foreign_toplevel_handle_v1_listener handle_listener;
    static const wl_registry_listener registry_listener;
};

#endif // TOPLEVEL_DOCK_H
