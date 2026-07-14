// Toplevel window tracker using wlr-foreign-toplevel-management protocol
// Tracks open windows for the taskbar

#ifndef TOPLEVEL_TRACKER_H
#define TOPLEVEL_TRACKER_H

#include <wayland-client.h>
#include <string>
#include <vector>
#include <functional>

// Maximum tracked windows
static const int MAX_TOPLEVELS = 64;

struct ToplevelInfo {
    struct zwlr_foreign_toplevel_handle_v1 *handle;
    char *title;
    char *app_id;
    bool activated;
    bool maximized;
    bool minimized;
    bool fullscreen;
    struct wl_output *output;
};

class ToplevelTracker {
public:
    ToplevelTracker();
    ~ToplevelTracker();

    // Initialize with Wayland display and manager
    bool init(struct wl_display *display);

    // Get list of toplevels
    const std::vector<ToplevelInfo>& get_toplevels() const { return toplevels; }

    // Get toplevel count
    int count() const { return toplevels.size(); }

    // Activate a toplevel window
    void activate(struct zwlr_foreign_toplevel_handle_v1 *handle);

    // Close a toplevel window
    void close(struct zwlr_foreign_toplevel_handle_v1 *handle);

    // Minimize a toplevel window
    void minimize(struct zwlr_foreign_toplevel_handle_v1 *handle);

    // Maximize a toplevel window
    void maximize(struct zwlr_foreign_toplevel_handle_v1 *handle);

    // Set callback for when toplevel list changes
    void set_change_callback(std::function<void()> cb) { change_callback = cb; }

private:
    std::vector<ToplevelInfo> toplevels;
    std::function<void()> change_callback;

    // Protocol objects
    struct zwlr_foreign_toplevel_manager_v1 *manager = nullptr;

    // Find toplevel by handle
    int find_index(struct zwlr_foreign_toplevel_handle_v1 *handle);

    // Static callbacks for protocol
    static void toplevel_created(void *data, struct zwlr_foreign_toplevel_manager_v1 *manager,
                                  struct zwlr_foreign_toplevel_handle_v1 *handle);
    static void toplevel_finished(void *data, struct zwlr_foreign_toplevel_manager_v1 *manager,
                                   struct zwlr_foreign_toplevel_handle_v1 *handle);
    static void manager_finished(void *data, struct zwlr_foreign_toplevel_manager_v1 *manager);

    static void title_changed(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
                               const char *title);
    static void app_id_changed(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
                                const char *app_id);
    static void state_enter(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
                             uint32_t state);
    static void state_leave(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
                             uint32_t state);
    static void handle_closed(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle);
    static void output_enter(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
                              struct wl_output *output);
    static void output_leave(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
                              struct wl_output *output);

    static const struct zwlr_foreign_toplevel_manager_v1_listener manager_listener;
    static const struct zwlr_foreign_toplevel_handle_v1_listener handle_listener;
};

#endif // TOPLEVEL_TRACKER_H
