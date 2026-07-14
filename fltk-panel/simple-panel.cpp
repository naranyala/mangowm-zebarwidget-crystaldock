// FLTK Wayland Panel - Simple prototype
// Runs as a regular Wayland window via FLTK's Wayland backend
//
// Features:
// - Clock display
// - Workspace indicator buttons
// - Launcher button
// - System tray placeholder

#include <FL/Fl.H>
#include <FL/Fl_Window.H>
#include <FL/Fl_Button.H>
#include <FL/Fl_Box.H>
#include <FL/Fl_RGB_Image.H>
#include <FL/fl_draw.H>
#include <ctime>
#include <cstring>
#include <cstdio>
#include <unistd.h>

// Panel configuration
static const int PANEL_HEIGHT = 36;
static const int PANEL_WIDTH = 1920;  // Will be resized by compositor
static const int WORKSPACE_COUNT = 4;

// Colors (Catppuccin Mocha inspired)
static const Fl_Color COLOR_BG = fl_rgb_color(30, 30, 46);
static const Fl_Color COLOR_FG = fl_rgb_color(205, 214, 244);
static const Fl_Color COLOR_ACCENT = fl_rgb_color(137, 180, 250);
static const Fl_Color COLOR_HOVER = fl_rgb_color(49, 50, 68);
static const Fl_Color COLOR_ACTIVE = fl_rgb_color(116, 199, 175);

// Clock update timer
static Fl_Box *clock_box = nullptr;

static void update_clock(void *data) {
    time_t now = time(nullptr);
    struct tm *t = localtime(&now);
    char buf[64];
    strftime(buf, sizeof(buf), "%H:%M", t);
    clock_box->label(buf);
    Fl::repeat_timeout(1.0, update_clock, data);
}

// Workspace button callback
static void workspace_cb(Fl_Widget *w, void *data) {
    int ws = (int)(long)data;
    printf("Switch to workspace %d\n", ws);
    // In a real panel, this would call:
    //   labwc --critical-client -r "GoToDesktop 1"
    // or use the labwc IPC socket
}

// Launcher button callback
static void launcher_cb(Fl_Widget *w, void *data) {
    printf("Launch fuzzel\n");
    // In a real panel: system("fuzzel &");
    // Or use the labwc IPC socket
}

// Quit button callback
static void quit_cb(Fl_Widget *w, void *data) {
    Fl::awake();
}

int main(int argc, char **argv) {
    // Create main panel window
    Fl_Window *panel = new Fl_Window(PANEL_WIDTH, PANEL_HEIGHT);
    panel->color(COLOR_BG);
    panel->label("FLTK Panel");
    panel->begin();

    // Left section: Launcher button
    Fl_Button *launcher = new Fl_Button(0, 0, 60, PANEL_HEIGHT, "@+9filigree>");
    launcher->color(COLOR_BG);
    launcher->labelcolor(COLOR_ACCENT);
    launcher->callback(launcher_cb);
    launcher->box(FL_FLAT_BOX);

    // Workspace buttons
    int x_pos = 64;
    for (int i = 0; i < WORKSPACE_COUNT; i++) {
        char label[8];
        snprintf(label, sizeof(label), "%d", i + 1);
        Fl_Button *ws = new Fl_Button(x_pos, 0, 32, PANEL_HEIGHT, strdup(label));
        ws->color(COLOR_BG);
        ws->labelcolor(COLOR_FG);
        ws->callback(workspace_cb, (void*)(long)(i + 1));
        ws->box(FL_FLAT_BOX);
        ws->labelsize(12);
        x_pos += 36;
    }

    // Spacer (center)
    Fl_Box *spacer = new Fl_Box(x_pos, 0, PANEL_WIDTH - x_pos - 120, PANEL_HEIGHT);

    // Clock (right)
    clock_box = new Fl_Box(PANEL_WIDTH - 120, 0, 120, PANEL_HEIGHT, "00:00");
    clock_box->labelcolor(COLOR_FG);
    clock_box->labelsize(14);
    clock_box->box(FL_FLAT_BOX);
    clock_box->align(FL_ALIGN_CENTER);

    panel->end();
    panel->resizable(spacer);

    // Show and start clock updates
    panel->show(argc, argv);
    Fl::add_timeout(1.0, update_clock);

    printf("FLTK Panel running on Wayland\n");
    printf("Press Ctrl+C or close window to quit\n");

    return Fl::run();
}
