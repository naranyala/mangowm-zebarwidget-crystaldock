// FLTK Wayland Panel with Bottom Dock
// Uses FLTK's native Wayland backend + wlr-foreign-toplevel-management protocol
// Creates a panel with launcher, workspaces, clock, and a dynamic app dock

#include <FL/Fl.H>
#include <FL/Fl_Window.H>
#include <FL/Fl_Button.H>
#include <FL/Fl_Box.H>
#include <FL/Fl_Flex.H>
#include <FL/fl_draw.H>
#include <wayland-client.h>
#include <FL/platform.H>
#include <ctime>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <vector>

#include "toplevel-dock.h"

// Panel dimensions
static const int PANEL_HEIGHT = 36;
static const int DOCK_HEIGHT = 56;
static const int DOCK_BUTTON_SIZE = 44;
static const int WINDOW_WIDTH = 1280;
static const int WINDOW_HEIGHT = PANEL_HEIGHT + DOCK_HEIGHT;

// Catppuccin Mocha colors
static const Fl_Color BG        = fl_rgb_color(30, 30, 46);
static const Fl_Color FG        = fl_rgb_color(205, 214, 244);
static const Fl_Color ACCENT    = fl_rgb_color(137, 180, 250);
static const Fl_Color GREEN     = fl_rgb_color(166, 227, 161);
static const Fl_Color SURFACE0  = fl_rgb_color(49, 50, 68);
static const Fl_Color SURFACE1  = fl_rgb_color(69, 71, 90);
static const Fl_Color PEACH     = fl_rgb_color(250, 179, 135);
static const Fl_Color RED       = fl_rgb_color(243, 139, 168);

// Global state
static Fl_Box *clock_label = nullptr;
static int active_workspace = 1;
static ToplevelTracker *tracker = nullptr;
static Fl_Flex *dock_container = nullptr;
static std::vector<Fl_Button*> dock_buttons;

// ============================================================
// Clock
// ============================================================

static void update_clock(void *) {
    time_t now = time(nullptr);
    struct tm *t = localtime(&now);
    char buf[16];
    strftime(buf, sizeof(buf), "%H:%M", t);
    if (clock_label) clock_label->label(buf);
    Fl::repeat_timeout(1.0, update_clock);
}

// ============================================================
// Callbacks
// ============================================================

static void ws_cb(Fl_Widget *w, void *data) {
    int ws = (int)(long)data;
    active_workspace = ws;
    printf("workspace: %d\n", ws);
}

static void launcher_cb(Fl_Widget *, void *) {
    printf("launcher\n");
}

static void power_cb(Fl_Widget *, void *) {
    exit(0);
}

// Dock button callback - activate (focus) window
static void dock_activate_cb(Fl_Widget *w, void *data) {
    int idx = (int)(long)data;
    if (tracker && idx >= 0 && idx < tracker->count()) {
        const auto &win = tracker->get_windows()[idx];
        printf("activate: [%s] %s\n", win.app_id, win.title);
        tracker->activate(win.handle);
    }
}

// Dock button callback - close window (right-click simulated)
static void dock_close_cb(Fl_Widget *w, void *data) {
    int idx = (int)(long)data;
    if (tracker && idx >= 0 && idx < tracker->count()) {
        const auto &win = tracker->get_windows()[idx];
        printf("close: [%s] %s\n", win.app_id, win.title);
        tracker->close(win.handle);
    }
}

// ============================================================
// Dock management
// ============================================================

static void rebuild_dock() {
    if (!tracker || !dock_container) return;

    // Remove old buttons
    for (Fl_Button *btn : dock_buttons) {
        dock_container->remove(btn);
        delete btn;
    }
    dock_buttons.clear();

    // Create new buttons for each window
    const auto &windows = tracker->get_windows();
    int x = 8;

    for (int i = 0; i < (int)windows.size(); i++) {
        const auto &w = windows[i];

        // Skip windows without app_id
        if (strlen(w.app_id) == 0 || strcmp(w.app_id, "(unknown)") == 0) continue;

        // Truncate title for button label
        char label[32];
        const char *text = w.title[0] ? w.title : w.app_id;
        strncpy(label, text, sizeof(label) - 1);
        label[sizeof(label) - 1] = '\0';
        if ((int)strlen(label) > 12) {
            strcpy(label + 9, "...");
        }

        Fl_Button *btn = new Fl_Button(x, PANEL_HEIGHT + 6, DOCK_BUTTON_SIZE, DOCK_BUTTON_SIZE,
                                        strdup(label));

        // Style based on state
        if (w.focused) {
            btn->color(ACCENT);
            btn->labelcolor(BG);
        } else if (w.minimized) {
            btn->color(SURFACE1);
            btn->labelcolor(fl_rgb_color(108, 112, 134));
        } else {
            btn->color(SURFACE0);
            btn->labelcolor(FG);
        }

        btn->labelsize(10);
        btn->box(FL_ROUNDED_BOX);
        btn->callback(dock_activate_cb, (void*)(long)i);

        dock_buttons.push_back(btn);
        x += DOCK_BUTTON_SIZE + 8;
    }

    dock_container->redraw();
}

// Timer to poll for window changes
static void poll_toplevels(void *) {
    if (tracker) {
        tracker->poll();
        if (tracker->is_dirty()) {
            tracker->clear_dirty();
            rebuild_dock();
        }
    }
    Fl::repeat_timeout(0.5, poll_toplevels);
}

// ============================================================
// Main
// ============================================================

int main(int argc, char **argv) {
    // Create main window
    Fl_Window *win = new Fl_Window(WINDOW_WIDTH, WINDOW_HEIGHT, "fltk-panel");
    win->color(BG);
    win->begin();

    // ---- Top panel bar ----
    Fl_Flex *top_bar = new Fl_Flex(0, 0, WINDOW_WIDTH, PANEL_HEIGHT, Fl_Flex::HORIZONTAL);
    top_bar->type(Fl_Flex::HORIZONTAL);
    top_bar->spacing(4);
    top_bar->color(BG);

    // Launcher
    Fl_Button *launcher = new Fl_Button(0, 0, 40, PANEL_HEIGHT, ">>");
    launcher->color(BG);
    launcher->labelcolor(ACCENT);
    launcher->labelsize(14);
    launcher->box(FL_FLAT_BOX);
    launcher->callback(launcher_cb);

    // Workspace buttons
    for (int i = 1; i <= 4; i++) {
        char lbl[4];
        snprintf(lbl, sizeof(lbl), "%d", i);
        Fl_Button *ws = new Fl_Button(0, 0, 28, PANEL_HEIGHT, strdup(lbl));
        ws->color(i == active_workspace ? SURFACE0 : BG);
        ws->labelcolor(i == active_workspace ? GREEN : FG);
        ws->labelsize(12);
        ws->box(FL_FLAT_BOX);
        ws->callback(ws_cb, (void *)(long)i);
    }

    // Spacer (flexible)
    Fl_Box *spacer = new Fl_Box(0, 0, 200, PANEL_HEIGHT);
    spacer->color(BG);

    // Clock
    clock_label = new Fl_Box(0, 0, 80, PANEL_HEIGHT, "00:00");
    clock_label->labelcolor(FG);
    clock_label->labelsize(14);
    clock_label->box(FL_FLAT_BOX);
    clock_label->align(FL_ALIGN_CENTER);

    // Power button
    Fl_Button *power = new Fl_Button(0, 0, 32, PANEL_HEIGHT, "X");
    power->color(BG);
    power->labelcolor(RED);
    power->labelsize(12);
    power->box(FL_FLAT_BOX);
    power->callback(power_cb);

    top_bar->end();
    top_bar->resizable(spacer);

    // ---- Bottom dock area ----
    dock_container = new Fl_Flex(0, PANEL_HEIGHT, WINDOW_WIDTH, DOCK_HEIGHT, Fl_Flex::HORIZONTAL);
    dock_container->type(Fl_Flex::HORIZONTAL);
    dock_container->spacing(8);
    dock_container->color(BG);
    dock_container->box(FL_FLAT_BOX);

    // Initial placeholder
    Fl_Box *dock_placeholder = new Fl_Box(0, PANEL_HEIGHT, WINDOW_WIDTH, DOCK_HEIGHT,
                                           "No running apps");
    dock_placeholder->labelcolor(SURFACE1);
    dock_placeholder->labelsize(12);
    dock_placeholder->box(FL_FLAT_BOX);
    dock_placeholder->align(FL_ALIGN_CENTER);

    dock_container->end();

    win->end();
    win->resizable(spacer);

    // Show window
    win->show(argc, argv);

    // Start clock
    Fl::add_timeout(1.0, update_clock);

    // Initialize toplevel tracker
    tracker = new ToplevelTracker();
    wl_display *display = fl_wl_display();
    if (display) {
        if (tracker->init(display)) {
            printf("toplevel tracker initialized\n");
            Fl::add_timeout(0.5, poll_toplevels);
        } else {
            printf("toplevel tracker init failed (no wlr-protocols?)\n");
        }
    } else {
        printf("no Wayland display available\n");
    }

    printf("FLTK Panel running\n");
    printf("  Top: launcher | workspaces | clock\n");
    printf("  Bottom: dynamic app dock\n");

    return Fl::run();
}
