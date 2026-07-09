#include <gtk/gtk.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <dirent.h>
#include <pthread.h>
#include <math.h>
#include "../libocws/gtk.h"
#include "../libocws/background_app.h"
#include "../libocws/audio_stream.h"
#include "../libocws/audio_analysis.h"

#define BUFSIZE 1024

static const char *freq_labels[] = {"32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"};
static GtkWidget *sliders[10];
static GtkWidget *preset_combo;
static GtkWidget *g_draw_area = NULL;
static audio_features_t g_features;
static int g_capture_running = 0;

static void push_eq(double values[10]) {
    gchar csv[128];
    snprintf(csv, sizeof(csv), "%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f",
        values[0], values[1], values[2], values[3], values[4],
        values[5], values[6], values[7], values[8], values[9]);
    gchar cmd[256];
    snprintf(cmd, sizeof(cmd), "ocws-eq-apply apply \"%s\"", csv);
    g_print("Applying EQ: %s\n", csv);
    system(cmd);
}

static void preset_to_bands(const gchar *name, double out[10]) {
    for (int i = 0; i < 10; i++) out[i] = 0.0;
    if (!name) return;
    if (g_str_equal(name, "Bass Boost")) {
        double v[10] = {9,7,5,3,1,0,0,0,0,0}; memcpy(out, v, sizeof(v));
    } else if (g_str_equal(name, "Treble Boost")) {
        double v[10] = {0,0,0,0,0,1,3,5,7,9}; memcpy(out, v, sizeof(v));
    } else if (g_str_equal(name, "Acoustic")) {
        double v[10] = {-2,0,2,3,3,2,1,0,-1,-2}; memcpy(out, v, sizeof(v));
    } else if (g_str_equal(name, "Electronic")) {
        double v[10] = {5,4,2,0,1,2,3,4,5,6}; memcpy(out, v, sizeof(v));
    } else if (g_str_equal(name, "Spoken Word")) {
        double v[10] = {-4,-2,0,2,4,4,3,1,-1,-2}; memcpy(out, v, sizeof(v));
    }
}

static void apply_preset(GtkWidget *w, gpointer d) {
    (void)w; (void)d;
    const gchar *name = gtk_combo_box_text_get_active_text(GTK_COMBO_BOX_TEXT(preset_combo));
    if (name) {
        double vals[10];
        preset_to_bands(name, vals);
        push_eq(vals);
        g_print("Applied preset: %s\n", name);
    }
}

static void load_presets(void) {
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(preset_combo), "Default");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(preset_combo), "Bass Boost");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(preset_combo), "Treble Boost");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(preset_combo), "Acoustic");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(preset_combo), "Electronic");
    const char *homedir = getenv("HOME");
    if (homedir) {
        char path[512];
        snprintf(path, sizeof(path), "%s/.config/easyeffects/output", homedir);
        DIR *dir = opendir(path);
        if (dir) {
            struct dirent *ent;
            while ((ent = readdir(dir)) != NULL) {
                if (strstr(ent->d_name, ".json")) {
                    gchar *dot = strrchr(ent->d_name, '.');
                    if (dot) *dot = '\0';
                    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(preset_combo), ent->d_name);
                    if (dot) *dot = '.';
                }
            }
            closedir(dir);
        }
    }
    gtk_combo_box_set_active(GTK_COMBO_BOX(preset_combo), 0);
}

static void apply_custom_eq(GtkWidget *w, gpointer d) {
    (void)w; (void)d;
    double values[10];
    for (int i = 0; i < 10; i++)
        values[i] = gtk_range_get_value(GTK_RANGE(sliders[i]));
    push_eq(values);
}

static void reset_custom_eq(GtkWidget *w, gpointer d) {
    (void)w; (void)d;
    for (int i = 0; i < 10; i++)
        gtk_range_set_value(GTK_RANGE(sliders[i]), 0.0);
}

static GtkWidget* create_presets_tab(void) {
    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 15);
    gtk_widget_set_margin_start(vbox, 30);
    gtk_widget_set_margin_end(vbox, 30);
    gtk_widget_set_margin_top(vbox, 30);
    gtk_widget_set_margin_bottom(vbox, 30);
    GtkWidget *label = gtk_label_new("Select an EasyEffects Preset:");
    gtk_box_pack_start(GTK_BOX(vbox), label, FALSE, FALSE, 0);
    preset_combo = gtk_combo_box_text_new();
    load_presets();
    gtk_box_pack_start(GTK_BOX(vbox), preset_combo, FALSE, FALSE, 0);
    GtkWidget *btn = gtk_button_new_with_label("Apply Preset");
    gtk_style_context_add_class(gtk_widget_get_style_context(btn), "suggested-action");
    g_signal_connect(btn, "clicked", G_CALLBACK(apply_preset), NULL);
    gtk_box_pack_start(GTK_BOX(vbox), btn, FALSE, FALSE, 0);
    return vbox;
}

static GtkWidget* create_custom_eq_tab(void) {
    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 15);
    gtk_widget_set_margin_start(vbox, 30);
    gtk_widget_set_margin_end(vbox, 30);
    gtk_widget_set_margin_top(vbox, 30);
    gtk_widget_set_margin_bottom(vbox, 30);
    GtkWidget *hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
    gtk_box_set_homogeneous(GTK_BOX(hbox), TRUE);
    for (int i = 0; i < 10; i++) {
        GtkWidget *bv = gtk_box_new(GTK_ORIENTATION_VERTICAL, 5);
        sliders[i] = gtk_scale_new_with_range(GTK_ORIENTATION_VERTICAL, -12.0, 12.0, 0.1);
        gtk_range_set_value(GTK_RANGE(sliders[i]), 0.0);
        gtk_range_set_inverted(GTK_RANGE(sliders[i]), TRUE);
        gtk_widget_set_size_request(sliders[i], -1, 200);
        GtkWidget *fl = gtk_label_new(freq_labels[i]);
        gtk_box_pack_start(GTK_BOX(bv), sliders[i], TRUE, TRUE, 0);
        gtk_box_pack_start(GTK_BOX(bv), fl, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(hbox), bv, TRUE, TRUE, 0);
    }
    gtk_box_pack_start(GTK_BOX(vbox), hbox, TRUE, TRUE, 10);
    GtkWidget *bb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
    gtk_widget_set_halign(bb, GTK_ALIGN_CENTER);
    GtkWidget *rb = gtk_button_new_with_label("Reset");
    g_signal_connect(rb, "clicked", G_CALLBACK(reset_custom_eq), NULL);
    gtk_box_pack_start(GTK_BOX(bb), rb, FALSE, FALSE, 0);
    GtkWidget *ab = gtk_button_new_with_label("Apply Custom EQ");
    gtk_style_context_add_class(gtk_widget_get_style_context(ab), "suggested-action");
    g_signal_connect(ab, "clicked", G_CALLBACK(apply_custom_eq), NULL);
    gtk_box_pack_start(GTK_BOX(bb), ab, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), bb, FALSE, FALSE, 0);
    return vbox;
}

// --- enhanced visualizer with audio_stream + audio_analysis ---

static gboolean on_draw_enhanced(GtkWidget *w, cairo_t *cr, gpointer d) {
    (void)d;
    guint width = gtk_widget_get_allocated_width(w);
    (void)gtk_widget_get_allocated_height(w);

    cairo_set_source_rgb(cr, 0.05, 0.05, 0.08);
    cairo_paint(cr);

    audio_stream_snapshot(&g_features);

    // active stream label
    const char *active = audio_stream_active();
    if (active && *active) {
        cairo_set_source_rgb(cr, 0.6, 0.8, 1.0);
        cairo_move_to(cr, 10, 20);
        PangoLayout *layout = pango_cairo_create_layout(cr);
        gchar buf[256];
        snprintf(buf, sizeof(buf), "Now Playing: %s", active);
        pango_layout_set_text(layout, buf, -1);
        pango_layout_set_font_description(layout, pango_font_description_from_string("Sans Bold 12"));
        pango_cairo_show_layout(cr, layout);
        g_object_unref(layout);
    }

    // level meters on the right
    float l_lvl = 0, r_lvl = 0;
    audio_stream_levels(&l_lvl, &r_lvl);

    cairo_set_source_rgba(cr, 0.1, 0.1, 0.15, 0.8);
    cairo_rectangle(cr, width - 120, 30, 110, 80);
    cairo_fill(cr);

    cairo_set_source_rgb(cr, 0.3, 0.8, 0.3);
    cairo_rectangle(cr, width - 115, 75 - l_lvl * 40, 45, l_lvl * 40);
    cairo_fill(cr);
    cairo_set_source_rgb(cr, 0.3, 0.3, 0.8);
    cairo_rectangle(cr, width - 65, 75 - r_lvl * 40, 45, r_lvl * 40);
    cairo_fill(cr);

    // spectrum bars (band-level display)
    float bands[4] = {g_features.band_lf, g_features.band_lmf, g_features.band_hmf, g_features.band_hf};
    const char *blabels[] = {"Bass", "Lo-Mid", "Hi-Mid", "Treble"};
    double colors[4][3] = {{0.2,0.4,0.9}, {0.2,0.8,0.3}, {0.9,0.8,0.2}, {0.9,0.3,0.2}};
    guint bw = width / 4;
    for (int i = 0; i < 4; i++) {
        double h = bands[i] * 120.0;
        if (h < 2) h = 2;
        if (h > 120) h = 120;
        cairo_set_source_rgb(cr, colors[i][0], colors[i][1], colors[i][2]);
        cairo_rectangle(cr, i * bw + 4, 150 - h, bw - 8, h);
        cairo_fill(cr);

        cairo_set_source_rgb(cr, 0.8, 0.8, 0.8);
        cairo_move_to(cr, i * bw + 4, 160);
        PangoLayout *lay = pango_cairo_create_layout(cr);
        gchar lb[32];
        snprintf(lb, sizeof(lb), "%s\n%.2f", blabels[i], (double)bands[i]);
        pango_layout_set_text(lay, lb, -1);
        pango_layout_set_font_description(lay, pango_font_description_from_string("Sans 9"));
        pango_cairo_show_layout(cr, lay);
        g_object_unref(lay);
    }

    // centroid indicator
    cairo_set_source_rgba(cr, 0.8, 0.2, 0.8, 0.8);
    cairo_arc(cr, g_features.centroid * width, 170, 6, 0, 2 * G_PI);
    cairo_fill(cr);

    return FALSE;
}

static gboolean on_tick(GtkWidget *w, GdkFrameClock *fc, gpointer d) {
    (void)fc; (void)d;
    gtk_widget_queue_draw(w);
    return G_SOURCE_CONTINUE;
}

static void* capture_loop(void *arg) {
    (void)arg;
    g_print("Enhanced equalizer: audio capture thread started\n");
    while (g_capture_running) {
        usleep(250000); // 4 Hz polling
    }
    return NULL;
}

static GtkWidget* create_enhanced_visualizer_tab(void) {
    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 5);
    g_draw_area = gtk_drawing_area_new();
    gtk_widget_set_size_request(g_draw_area, -1, 250);
    g_signal_connect(G_OBJECT(g_draw_area), "draw", G_CALLBACK(on_draw_enhanced), NULL);
    gtk_widget_add_tick_callback(g_draw_area, on_tick, NULL, NULL);
    gtk_box_pack_start(GTK_BOX(vbox), g_draw_area, TRUE, TRUE, 0);

    // start capture
    g_capture_running = 1;
    pthread_t tid;
    pthread_create(&tid, NULL, capture_loop, NULL);
    pthread_detach(tid);

    return vbox;
}

// --- main app ---

static void activate(GtkApplication *app, gpointer user_data) {
    (void)user_data;
    GtkWidget *window = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(window), "OCWS Equalizer (Enhanced)");
    gtk_window_set_default_size(GTK_WINDOW(window), 700, 500);
    gtk_window_set_position(GTK_WINDOW(window), GTK_WIN_POS_CENTER);

    GtkWidget *header = gtk_header_bar_new();
    gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(header), TRUE);
    gtk_header_bar_set_title(GTK_HEADER_BAR(header), "OCWS Equalizer");
    gtk_header_bar_set_subtitle(GTK_HEADER_BAR(header), "Enhanced Audio Analysis");
    gtk_window_set_titlebar(GTK_WINDOW(window), header);

    GtkWidget *vbox_main = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(window), vbox_main);

    GtkWidget *stack = gtk_stack_new();
    gtk_stack_set_transition_type(GTK_STACK(stack), GTK_STACK_TRANSITION_TYPE_SLIDE_LEFT_RIGHT);
    GtkWidget *switcher = gtk_stack_switcher_new();
    gtk_stack_switcher_set_stack(GTK_STACK_SWITCHER(switcher), GTK_STACK(stack));
    gtk_header_bar_set_custom_title(GTK_HEADER_BAR(header), switcher);

    gtk_stack_add_titled(GTK_STACK(stack), create_presets_tab(), "presets", "Presets");
    gtk_stack_add_titled(GTK_STACK(stack), create_custom_eq_tab(), "custom", "10-Band EQ");
    gtk_stack_add_titled(GTK_STACK(stack), create_enhanced_visualizer_tab(), "visualizer", "Visualizer");

    gtk_box_pack_start(GTK_BOX(vbox_main), stack, TRUE, TRUE, 0);

    ocws_background_app_init(app, window, "audio-volume-high");
}

int main(int argc, char **argv) {
    if (audio_stream_init() != 0)
        g_warning("audio_stream_init failed — no audio data will be available");

    GtkApplication *app = gtk_application_new("org.ocws.equalizer.enhanced", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);

    audio_stream_deinit();
    return status;
}
