// Toplevel window tracker implementation
// Binds wlr-foreign-toplevel-management protocol for window tracking

#include "toplevel-dock.h"
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"
#include <cstring>
#include <cstdio>

// Include protocol implementation for interface definitions
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.c"

// State flags from protocol
enum toplevel_state {
    TOPLEVEL_STATE_MAXIMIZED = 0,
    TOPLEVEL_STATE_MINIMIZED = 1,
    TOPLEVEL_STATE_FOCUSED = 2,
    TOPLEVEL_STATE_FULLSCREEN = 3,
};

ToplevelTracker::ToplevelTracker() {}

ToplevelTracker::~ToplevelTracker() {
    if (manager) {
        zwlr_foreign_toplevel_manager_v1_destroy(manager);
        manager = nullptr;
    }
    if (registry) wl_registry_destroy(registry);
}

bool ToplevelTracker::init(wl_display *disp) {
    display = disp;
    if (!display) return false;

    registry = wl_display_get_registry(display);
    if (!registry) return false;

    wl_registry_add_listener(registry, &registry_listener, this);
    wl_display_roundtrip(display);

    if (!manager) {
        fprintf(stderr, "toplevel-dock: zwlr_foreign_toplevel_manager_v1 not available\n");
        return false;
    }

    fprintf(stderr, "toplevel-dock: initialized (seat=%p, manager=%p)\n", seat, manager);
    return true;
}

void ToplevelTracker::poll() {
    if (!display) return;
    wl_display_dispatch_pending(display);
}

// Find window by handle
int ToplevelTracker::find_index(zwlr_foreign_toplevel_handle_v1 *handle) {
    for (int i = 0; i < (int)windows.size(); i++) {
        if (windows[i].handle == handle) return i;
    }
    return -1;
}

// Remove window at index
void ToplevelTracker::remove_at(int index) {
    if (index >= 0 && index < (int)windows.size()) {
        windows.erase(windows.begin() + index);
        dirty = true;
        if (change_callback) change_callback();
    }
}

// Activate (focus) a window
void ToplevelTracker::activate(zwlr_foreign_toplevel_handle_v1 *handle) {
    if (handle && seat) {
        zwlr_foreign_toplevel_handle_v1_activate(handle, seat);
        fprintf(stderr, "toplevel-dock: activate %p\n", handle);
    }
}

// Close a window
void ToplevelTracker::close(zwlr_foreign_toplevel_handle_v1 *handle) {
    if (handle) {
        zwlr_foreign_toplevel_handle_v1_close(handle);
        fprintf(stderr, "toplevel-dock: close %p\n", handle);
    }
}

// Minimize a window
void ToplevelTracker::minimize(zwlr_foreign_toplevel_handle_v1 *handle) {
    if (handle) {
        zwlr_foreign_toplevel_handle_v1_set_minimized(handle);
        fprintf(stderr, "toplevel-dock: minimize %p\n", handle);
    }
}

// Maximize a window
void ToplevelTracker::maximize(zwlr_foreign_toplevel_handle_v1 *handle) {
    if (handle) {
        zwlr_foreign_toplevel_handle_v1_set_maximized(handle);
        fprintf(stderr, "toplevel-dock: maximize %p\n", handle);
    }
}

// ============================================================
// Protocol callbacks
// ============================================================

void ToplevelTracker::registry_global(void *data, wl_registry *registry,
                                       uint32_t name, const char *interface, uint32_t version) {
    ToplevelTracker *self = static_cast<ToplevelTracker*>(data);

    if (strcmp(interface, zwlr_foreign_toplevel_manager_v1_interface.name) == 0) {
        self->manager = (zwlr_foreign_toplevel_manager_v1*)wl_registry_bind(
            registry, name, &zwlr_foreign_toplevel_manager_v1_interface,
            std::min(version, 1u));
        if (self->manager) {
            zwlr_foreign_toplevel_manager_v1_add_listener(
                self->manager, &manager_listener, self);
            fprintf(stderr, "toplevel-dock: bound toplevel manager v%u\n", version);
        }
    } else if (strcmp(interface, wl_seat_interface.name) == 0) {
        self->seat = (wl_seat*)wl_registry_bind(
            registry, name, &wl_seat_interface, 1);
        fprintf(stderr, "toplevel-dock: bound seat\n");
    }
}

void ToplevelTracker::registry_global_remove(void *data, wl_registry *registry, uint32_t name) {
    // Handle removal
}

void ToplevelTracker::manager_toplevel(void *data, zwlr_foreign_toplevel_manager_v1 *manager,
                                        zwlr_foreign_toplevel_handle_v1 *handle) {
    ToplevelTracker *self = static_cast<ToplevelTracker*>(data);

    if ((int)self->windows.size() >= MAX_TOPLEVELS) return;

    ToplevelInfo info = {};
    info.handle = handle;
    info.alive = true;
    strncpy(info.title, "(untitled)", sizeof(info.title) - 1);
    strncpy(info.app_id, "(unknown)", sizeof(info.app_id) - 1);

    self->windows.push_back(info);

    // Attach handle listener
    zwlr_foreign_toplevel_handle_v1_add_listener(handle, &handle_listener, self);

    self->dirty = true;
    fprintf(stderr, "toplevel-dock: new window (total: %d)\n", (int)self->windows.size());
}

void ToplevelTracker::manager_finished(void *data, zwlr_foreign_toplevel_manager_v1 *manager) {
    ToplevelTracker *self = static_cast<ToplevelTracker*>(data);
    self->manager = nullptr;
    fprintf(stderr, "toplevel-dock: manager finished\n");
}

void ToplevelTracker::handle_title(void *data, zwlr_foreign_toplevel_handle_v1 *handle,
                                    const char *title) {
    ToplevelTracker *self = static_cast<ToplevelTracker*>(data);
    int idx = self->find_index(handle);
    if (idx >= 0) {
        strncpy(self->windows[idx].title, title ? title : "(untitled)",
                sizeof(self->windows[idx].title) - 1);
    }
}

void ToplevelTracker::handle_app_id(void *data, zwlr_foreign_toplevel_handle_v1 *handle,
                                     const char *app_id) {
    ToplevelTracker *self = static_cast<ToplevelTracker*>(data);
    int idx = self->find_index(handle);
    if (idx >= 0) {
        strncpy(self->windows[idx].app_id, app_id ? app_id : "(unknown)",
                sizeof(self->windows[idx].app_id) - 1);
    }
}

void ToplevelTracker::handle_state(void *data, zwlr_foreign_toplevel_handle_v1 *handle,
                                    wl_array *state) {
    ToplevelTracker *self = static_cast<ToplevelTracker*>(data);
    int idx = self->find_index(handle);
    if (idx < 0) return;

    ToplevelInfo &info = self->windows[idx];
    info.focused = false;
    info.minimized = false;
    info.maximized = false;
    info.fullscreen = false;

    // Parse state array
    uint32_t *state_arr = (uint32_t *)state->data;
    size_t n = state->size / sizeof(uint32_t);
    for (size_t i = 0; i < n; i++) {
        switch (state_arr[i]) {
            case TOPLEVEL_STATE_MAXIMIZED: info.maximized = true; break;
            case TOPLEVEL_STATE_MINIMIZED: info.minimized = true; break;
            case TOPLEVEL_STATE_FOCUSED: info.focused = true; break;
            case TOPLEVEL_STATE_FULLSCREEN: info.fullscreen = true; break;
            default: break;
        }
    }
}

void ToplevelTracker::handle_done(void *data, zwlr_foreign_toplevel_handle_v1 *handle) {
    ToplevelTracker *self = static_cast<ToplevelTracker*>(data);
    self->dirty = true;
    if (self->change_callback) self->change_callback();
}

void ToplevelTracker::handle_closed(void *data, zwlr_foreign_toplevel_handle_v1 *handle) {
    ToplevelTracker *self = static_cast<ToplevelTracker*>(data);
    int idx = self->find_index(handle);
    if (idx >= 0) {
        fprintf(stderr, "toplevel-dock: window closed: %s\n", self->windows[idx].title);
        self->remove_at(idx);
    }
}

void ToplevelTracker::handle_output_enter(void *data, zwlr_foreign_toplevel_handle_v1 *handle,
                                           wl_output *output) {
    // Track which output window is on
}

void ToplevelTracker::handle_output_leave(void *data, zwlr_foreign_toplevel_handle_v1 *handle,
                                           wl_output *output) {
    // Track which output window is on
}

static void handle_parent(void *data, zwlr_foreign_toplevel_handle_v1 *handle,
                           zwlr_foreign_toplevel_handle_v1 *parent) {
    // Parent window relationship
}

// ============================================================
// Protocol listener structs
// ============================================================

const wl_registry_listener ToplevelTracker::registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

const zwlr_foreign_toplevel_manager_v1_listener ToplevelTracker::manager_listener = {
    .toplevel = manager_toplevel,
    .finished = manager_finished,
};

const zwlr_foreign_toplevel_handle_v1_listener ToplevelTracker::handle_listener = {
    .title = handle_title,
    .app_id = handle_app_id,
    .output_enter = handle_output_enter,
    .output_leave = handle_output_leave,
    .state = handle_state,
    .done = handle_done,
    .closed = handle_closed,
    .parent = handle_parent,
};
