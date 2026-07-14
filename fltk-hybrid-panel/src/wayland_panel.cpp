// wayland_panel.cpp - Raw Wayland + wlr-layer-shell panel implementation
//
// This is the core of the hybrid approach: we create a Wayland layer-shell
// surface directly (bypassing FLTK's window management) so the compositor
// treats our panel as a proper desktop shell component.

#include "wayland_panel.h"
#define namespace namespace_
#include "wlr-layer-shell-unstable-v1-client.h"
#undef namespace
#include "wlr-foreign-toplevel-management-unstable-v1-client.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <errno.h>
#include <linux/input-event-codes.h>

// ============================================================================
// SHM helper: create an anonymous shared memory file
// ============================================================================
static int create_shm_file(size_t size) {
    // Try memfd_create first (Linux 3.17+)
    int fd = memfd_create("fltk-panel-shm", MFD_CLOEXEC);
    if (fd < 0) {
        // Fallback to shm_open
        char name[64];
        snprintf(name, sizeof(name), "/fltk-panel-%d", getpid());
        fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
        shm_unlink(name);
    }
    if (fd < 0) return -1;
    if (ftruncate(fd, size) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

// ============================================================================
// Registry listener — bind compositor globals
// ============================================================================
extern const struct zwlr_foreign_toplevel_manager_v1_listener toplevel_manager_listener;

static const struct wl_registry_listener registry_listener = {
    .global = WaylandPanel::registry_global,
    .global_remove = WaylandPanel::registry_global_remove,
};

void WaylandPanel::registry_global(void* data, struct wl_registry* reg,
                                    uint32_t name, const char* interface, uint32_t version) {
    auto* panel = static_cast<WaylandPanel*>(data);

    if (strcmp(interface, wl_compositor_interface.name) == 0) {
        panel->compositor_ = static_cast<struct wl_compositor*>(
            wl_registry_bind(reg, name, &wl_compositor_interface, 4));
    } else if (strcmp(interface, wl_shm_interface.name) == 0) {
        panel->shm_ = static_cast<struct wl_shm*>(
            wl_registry_bind(reg, name, &wl_shm_interface, 1));
    } else if (strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0) {
        panel->layer_shell_ = static_cast<struct zwlr_layer_shell_v1*>(
            wl_registry_bind(reg, name, &zwlr_layer_shell_v1_interface, 1));
    } else if (strcmp(interface, zwlr_foreign_toplevel_manager_v1_interface.name) == 0) {
        panel->toplevel_manager_ = static_cast<struct zwlr_foreign_toplevel_manager_v1*>(
            wl_registry_bind(reg, name, &zwlr_foreign_toplevel_manager_v1_interface, 3));
        zwlr_foreign_toplevel_manager_v1_add_listener(panel->toplevel_manager_, &toplevel_manager_listener, panel);
    } else if (strcmp(interface, wl_seat_interface.name) == 0) {
        panel->seat_ = static_cast<struct wl_seat*>(
            wl_registry_bind(reg, name, &wl_seat_interface, 5));
    } else if (strcmp(interface, wl_output_interface.name) == 0) {
        if (!panel->output_) {  // Use the first output
            panel->output_ = static_cast<struct wl_output*>(
                wl_registry_bind(reg, name, &wl_output_interface, 1));
        }
    }
}

void WaylandPanel::registry_global_remove(void* /*data*/, struct wl_registry* /*reg*/,
                                           uint32_t /*name*/) {
    // Handle output removal, etc. (simplified for exploration)
}

// ============================================================================
// Layer surface listener — handle configure & close
// ============================================================================
static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
    .configure = WaylandPanel::layer_surface_configure,
    .closed = WaylandPanel::layer_surface_closed,
};

void WaylandPanel::layer_surface_configure(void* data, struct zwlr_layer_surface_v1* surface,
                                            uint32_t serial, uint32_t w, uint32_t h) {
    auto* panel = static_cast<WaylandPanel*>(data);

    // Acknowledge the configure
    zwlr_layer_surface_v1_ack_configure(surface, serial);

    // If size changed, recreate the SHM buffer
    bool size_changed = (int)w != panel->width_ || (int)h != panel->height_;
    panel->width_  = (int)w;
    panel->height_ = (int)h;

    if (size_changed || !panel->configured_) {
        panel->destroy_shm_buffer();
        if (!panel->create_shm_buffer()) {
            fprintf(stderr, "[ERROR] Failed to create SHM buffer (%dx%d)\n", panel->width_, panel->height_);
            panel->running_ = false;
            return;
        }
        fprintf(stdout, "[INFO] Panel configured: %dx%d\n", panel->width_, panel->height_);
    }

    panel->configured_ = true;
    panel->needs_redraw_ = true;

    // Render the first frame immediately
    panel->render_frame();
}

void WaylandPanel::layer_surface_closed(void* data, struct zwlr_layer_surface_v1* /*surface*/) {
    auto* panel = static_cast<WaylandPanel*>(data);
    fprintf(stdout, "[INFO] Layer surface closed by compositor\n");
    panel->running_ = false;
}

// ============================================================================
// Frame callback — triggered when compositor is ready for next frame
// ============================================================================
static const struct wl_callback_listener frame_listener = {
    .done = WaylandPanel::frame_done,
};

void WaylandPanel::frame_done(void* data, struct wl_callback* cb, uint32_t /*time*/) {
    auto* panel = static_cast<WaylandPanel*>(data);
    wl_callback_destroy(cb);
    panel->frame_cb_ = nullptr;

    if (panel->needs_redraw_) {
        panel->render_frame();
    }
}

// ============================================================================
// Pointer listener — handle click events on the panel
// ============================================================================
static const struct wl_pointer_listener pointer_listener = {
    .enter  = WaylandPanel::pointer_enter,
    .leave  = WaylandPanel::pointer_leave,
    .motion = WaylandPanel::pointer_motion,
    .button = WaylandPanel::pointer_button,
    .axis   = WaylandPanel::pointer_axis,
};

void WaylandPanel::pointer_enter(void* data, struct wl_pointer* /*ptr*/, uint32_t /*serial*/,
                                  struct wl_surface* /*surface*/, wl_fixed_t sx, wl_fixed_t sy) {
    auto* panel = static_cast<WaylandPanel*>(data);
    panel->pointer_x_ = wl_fixed_to_int(sx);
    panel->pointer_y_ = wl_fixed_to_int(sy);
}

void WaylandPanel::pointer_leave(void* /*data*/, struct wl_pointer* /*ptr*/,
                                  uint32_t /*serial*/, struct wl_surface* /*surface*/) {
    // Nothing needed for now
}

void WaylandPanel::pointer_motion(void* data, struct wl_pointer* /*ptr*/, uint32_t /*time*/,
                                   wl_fixed_t sx, wl_fixed_t sy) {
    auto* panel = static_cast<WaylandPanel*>(data);
    panel->pointer_x_ = wl_fixed_to_int(sx);
    panel->pointer_y_ = wl_fixed_to_int(sy);
}

void WaylandPanel::pointer_button(void* data, struct wl_pointer* /*ptr*/, uint32_t /*serial*/,
                                   uint32_t /*time*/, uint32_t button, uint32_t state) {
    auto* panel = static_cast<WaylandPanel*>(data);
    if (state == WL_POINTER_BUTTON_STATE_RELEASED && panel->click_cb_) {
        panel->click_cb_(panel->pointer_x_, panel->pointer_y_, button);
        panel->needs_redraw_ = true;
        panel->schedule_frame();
    }
}

void WaylandPanel::pointer_axis(void* /*data*/, struct wl_pointer* /*ptr*/, uint32_t /*time*/,
                                 uint32_t /*axis*/, wl_fixed_t /*value*/) {
    // Scroll events — can be used later
}

// ============================================================================
// Seat listener — get pointer capability
// ============================================================================
static const struct wl_seat_listener seat_listener = {
    .capabilities = WaylandPanel::seat_capabilities,
    .name = WaylandPanel::seat_name,
};

void WaylandPanel::seat_capabilities(void* data, struct wl_seat* seat, uint32_t caps) {
    auto* panel = static_cast<WaylandPanel*>(data);
    if ((caps & WL_SEAT_CAPABILITY_POINTER) && !panel->pointer_) {
        panel->pointer_ = wl_seat_get_pointer(seat);
        wl_pointer_add_listener(panel->pointer_, &pointer_listener, panel);
    }
}

void WaylandPanel::seat_name(void* /*data*/, struct wl_seat* /*seat*/, const char* /*name*/) {}

// ============================================================================
// Constructor / Destructor
// ============================================================================
WaylandPanel::WaylandPanel(const Config& cfg) : config_(cfg) {
    height_ = cfg.height;
}

WaylandPanel::~WaylandPanel() {
    destroy_shm_buffer();
    if (frame_cb_)       wl_callback_destroy(frame_cb_);
    if (layer_surface_)  zwlr_layer_surface_v1_destroy(layer_surface_);
    if (surface_)        wl_surface_destroy(surface_);
    if (pointer_)        wl_pointer_destroy(pointer_);
    if (seat_)           wl_seat_destroy(seat_);
    if (layer_shell_)    zwlr_layer_shell_v1_destroy(layer_shell_);
    if (shm_)            wl_shm_destroy(shm_);
    if (compositor_)     wl_compositor_destroy(compositor_);
    if (registry_)       wl_registry_destroy(registry_);
    if (display_)        wl_display_disconnect(display_);
}

// ============================================================================
// init() — Connect to Wayland, create layer surface
// ============================================================================
bool WaylandPanel::init() {
    // 1. Connect to Wayland display
    display_ = wl_display_connect(nullptr);
    if (!display_) {
        fprintf(stderr, "[ERROR] Cannot connect to Wayland display\n");
        return false;
    }
    fprintf(stdout, "[OK] Connected to Wayland display\n");

    // 2. Get registry and bind globals
    registry_ = wl_display_get_registry(display_);
    wl_registry_add_listener(registry_, &registry_listener, this);
    wl_display_roundtrip(display_);  // First roundtrip: bind globals
    wl_display_roundtrip(display_);  // Second roundtrip: ensure all bound

    // 3. Verify required globals
    if (!compositor_) { fprintf(stderr, "[ERROR] No wl_compositor\n"); return false; }
    if (!shm_)        { fprintf(stderr, "[ERROR] No wl_shm\n"); return false; }
    if (!layer_shell_) {
        fprintf(stderr, "[ERROR] No zwlr_layer_shell_v1 — compositor does not support layer-shell!\n");
        fprintf(stderr, "        Make sure you're running a wlroots-based compositor (labwc, sway, etc.)\n");
        return false;
    }
    fprintf(stdout, "[OK] Bound wl_compositor, wl_shm, zwlr_layer_shell_v1\n");

    // 4. Bind seat for pointer input
    if (seat_) {
        wl_seat_add_listener(seat_, &seat_listener, this);
        wl_display_roundtrip(display_);
    }

    // 5. Create the wl_surface
    surface_ = wl_compositor_create_surface(compositor_);
    if (!surface_) {
        fprintf(stderr, "[ERROR] Failed to create wl_surface\n");
        return false;
    }

    // 6. Create the layer surface — THIS is what makes it a panel!
    //    We anchor to top + left + right so it spans the full width.
    //    The exclusive zone reserves screen space.
    uint32_t layer = ZWLR_LAYER_SHELL_V1_LAYER_TOP;
    layer_surface_ = zwlr_layer_shell_v1_get_layer_surface(
        layer_shell_, surface_, nullptr /* output: compositor chooses */,
        layer, config_.namespace_name);

    if (!layer_surface_) {
        fprintf(stderr, "[ERROR] Failed to create layer surface\n");
        return false;
    }

    // Configure anchoring
    uint32_t anchor;
    if (config_.anchor_top) {
        anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
                 ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
                 ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    } else {
        anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
                 ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
                 ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    }
    zwlr_layer_surface_v1_set_anchor(layer_surface_, anchor);
    zwlr_layer_surface_v1_set_size(layer_surface_, 0, config_.height);  // width=0 → full width
    zwlr_layer_surface_v1_set_exclusive_zone(layer_surface_, config_.height);
    zwlr_layer_surface_v1_set_keyboard_interactivity(layer_surface_,
        ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);

    zwlr_layer_surface_v1_add_listener(layer_surface_, &layer_surface_listener, this);

    // 7. Initial commit (no buffer) — triggers compositor configure
    wl_surface_commit(surface_);
    wl_display_roundtrip(display_);

    fprintf(stdout, "[OK] Layer surface created, waiting for configure...\n");
    return true;
}

// ============================================================================
// SHM buffer management
// ============================================================================
bool WaylandPanel::create_shm_buffer() {
    int stride = width_ * 4;  // 4 bytes per pixel (ARGB8888)
    shm_size_ = stride * height_;

    shm_fd_ = create_shm_file(shm_size_);
    if (shm_fd_ < 0) {
        fprintf(stderr, "[ERROR] Failed to create SHM file: %s\n", strerror(errno));
        return false;
    }

    pixel_data_ = static_cast<uint32_t*>(
        mmap(nullptr, shm_size_, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd_, 0));
    if (pixel_data_ == MAP_FAILED) {
        pixel_data_ = nullptr;
        close(shm_fd_);
        shm_fd_ = -1;
        return false;
    }

    struct wl_shm_pool* pool = wl_shm_create_pool(shm_, shm_fd_, shm_size_);
    buffer_ = wl_shm_pool_create_buffer(pool, 0, width_, height_, stride,
                                         WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    return true;
}

void WaylandPanel::destroy_shm_buffer() {
    if (buffer_) {
        wl_buffer_destroy(buffer_);
        buffer_ = nullptr;
    }
    if (pixel_data_) {
        munmap(pixel_data_, shm_size_);
        pixel_data_ = nullptr;
    }
    if (shm_fd_ >= 0) {
        close(shm_fd_);
        shm_fd_ = -1;
    }
}

// ============================================================================
// Frame rendering
// ============================================================================
void WaylandPanel::render_frame() {
    if (!configured_ || !pixel_data_ || !buffer_) return;

    // Call the render callback to paint pixels
    if (render_cb_) {
        int stride = width_ * 4;
        render_cb_(pixel_data_, width_, height_, stride);
    }

    // Attach buffer and commit
    wl_surface_attach(surface_, buffer_, 0, 0);
    wl_surface_damage_buffer(surface_, 0, 0, width_, height_);

    // Schedule next frame callback
    schedule_frame();

    wl_surface_commit(surface_);
    needs_redraw_ = false;
}

void WaylandPanel::schedule_frame() {
    if (frame_cb_) return;  // Already scheduled
    frame_cb_ = wl_surface_frame(surface_);
    wl_callback_add_listener(frame_cb_, &frame_listener, this);
}

// ============================================================================
// request_redraw()
// ============================================================================
void WaylandPanel::request_redraw() {
    needs_redraw_ = true;
    if (surface_ && !frame_cb_) {
        schedule_frame();
        wl_surface_commit(surface_);
    }
}

// ============================================================================
// run() — Main event loop
// ============================================================================
void WaylandPanel::run() {
    fprintf(stdout, "[OK] Panel running. Press Ctrl+C to exit.\n");
    while (running_) {
        if (wl_display_dispatch(display_) < 0) {
            fprintf(stderr, "[ERROR] Wayland display dispatch error\n");
            break;
        }
    }
}

// ============================================================================
// Foreign Toplevel Management (Window Switcher)
// ============================================================================
void WaylandPanel::activate_window(WindowInfo* win) {
    if (win && win->handle) {
        zwlr_foreign_toplevel_handle_v1_activate(win->handle, seat_);
    }
}

void WaylandPanel::close_window(WindowInfo* win) {
    if (win && win->handle) {
        zwlr_foreign_toplevel_handle_v1_close(win->handle);
    }
}

void WaylandPanel::toplevel_handle_title(void* data, struct zwlr_foreign_toplevel_handle_v1* toplevel, const char* title) {
    auto* win = static_cast<WindowInfo*>(data);
    win->title = title;
}

void WaylandPanel::toplevel_handle_app_id(void* data, struct zwlr_foreign_toplevel_handle_v1* toplevel, const char* app_id) {
    auto* win = static_cast<WindowInfo*>(data);
    win->app_id = app_id;
}

void WaylandPanel::toplevel_handle_output_enter(void* data, struct zwlr_foreign_toplevel_handle_v1* toplevel, struct wl_output* output) {}
void WaylandPanel::toplevel_handle_output_leave(void* data, struct zwlr_foreign_toplevel_handle_v1* toplevel, struct wl_output* output) {}

void WaylandPanel::toplevel_handle_state(void* data, struct zwlr_foreign_toplevel_handle_v1* toplevel, struct wl_array* state) {
    auto* win = static_cast<WindowInfo*>(data);
    win->maximized = false;
    win->minimized = false;
    win->activated = false;
    
    uint32_t* s;
    for (s = (uint32_t*)state->data; (const char*)s < ((const char*)state->data + state->size); s++) {
        switch (*s) {
            case ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MAXIMIZED: win->maximized = true; break;
            case ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MINIMIZED: win->minimized = true; break;
            case ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED: win->activated = true; break;
        }
    }
}

void WaylandPanel::toplevel_handle_done(void* data, struct zwlr_foreign_toplevel_handle_v1* toplevel) {
    auto* win = static_cast<WindowInfo*>(data);
    if (win->panel) {
        win->panel->request_redraw();
    }
}

void WaylandPanel::toplevel_handle_closed(void* data, struct zwlr_foreign_toplevel_handle_v1* toplevel) {
    auto* win = static_cast<WindowInfo*>(data);
    zwlr_foreign_toplevel_handle_v1_destroy(toplevel);
    win->handle = nullptr;
    if (win->panel) {
        win->panel->request_redraw();
    }
}

void WaylandPanel::toplevel_handle_parent(void* data, struct zwlr_foreign_toplevel_handle_v1* toplevel, struct zwlr_foreign_toplevel_handle_v1* parent) {}

const struct zwlr_foreign_toplevel_handle_v1_listener toplevel_handle_listener = {
    .title = WaylandPanel::toplevel_handle_title,
    .app_id = WaylandPanel::toplevel_handle_app_id,
    .output_enter = WaylandPanel::toplevel_handle_output_enter,
    .output_leave = WaylandPanel::toplevel_handle_output_leave,
    .state = WaylandPanel::toplevel_handle_state,
    .done = WaylandPanel::toplevel_handle_done,
    .closed = WaylandPanel::toplevel_handle_closed,
    .parent = WaylandPanel::toplevel_handle_parent,
};

void WaylandPanel::toplevel_manager_toplevel(void* data, struct zwlr_foreign_toplevel_manager_v1* manager, struct zwlr_foreign_toplevel_handle_v1* toplevel) {
    auto* panel = static_cast<WaylandPanel*>(data);
    auto* win = new WindowInfo();
    win->panel = panel;
    win->handle = toplevel;
    panel->windows_.push_back(win);
    zwlr_foreign_toplevel_handle_v1_add_listener(toplevel, &toplevel_handle_listener, win);
    panel->request_redraw();
}

void WaylandPanel::toplevel_manager_finished(void* data, struct zwlr_foreign_toplevel_manager_v1* manager) {
}

extern const struct zwlr_foreign_toplevel_manager_v1_listener toplevel_manager_listener = {
    .toplevel = WaylandPanel::toplevel_manager_toplevel,
    .finished = WaylandPanel::toplevel_manager_finished,
};
