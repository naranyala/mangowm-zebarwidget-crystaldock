#include <gtk/gtk.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <dirent.h>
#include <pthread.h>
#include <math.h>
#include <fftw3.h>
#include "../libocws/gtk.h"
#include "../libocws/background_app.h"

// 10-Band EQ Frequencies
const char *freq_labels[] = {"32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"};
GtkWidget *sliders[10];
GtkWidget *preset_combo;

// Visualizer State
#define BUFSIZE 1024
static float audio_buffer[BUFSIZE];
static double fft_out_mag[BUFSIZE/2];
static double smoothed_mag[BUFSIZE/2];
static pthread_mutex_t audio_mutex = PTHREAD_MUTEX_INITIALIZER;

static void* pa_capture_thread(void *arg) {
    (void)arg;
    static const pa_sample_spec ss = {
        .format = PA_SAMPLE_FLOAT32LE,
        .rate = 44100,
        .channels = 1
    };
    int error;
    // PA_STREAM_RECORD grabs the default recording device. For output monitor, you usually 
    // want the ".monitor" sink. NULL usually uses the default source which might be the mic.
    // For a generic visualizer, NULL works if the default source is a monitor, or if we use EasyEffects/PipeWire routing.
    pa_simple *s = pa_simple_new(NULL, "ocws-equalizer", PA_STREAM_RECORD, NULL, "visualizer", &ss, NULL, NULL, &error);
    if (!s) {
        g_printerr("pa_simple_new() failed: %s\n", pa_strerror(error));
        return NULL;
    }

    double *in = fftw_alloc_real(BUFSIZE);
    fftw_complex *out = fftw_alloc_complex(BUFSIZE / 2 + 1);
    fftw_plan plan = fftw_plan_dft_r2c_1d(BUFSIZE, in, out, FFTW_MEASURE);

    float read_buf[BUFSIZE];
    while (1) {
        if (pa_simple_read(s, read_buf, sizeof(read_buf), &error) < 0) {
            g_printerr("pa_simple_read() failed: %s\n", pa_strerror(error));
            break;
        }

        // Apply Hann window and copy to FFT input
        for (int i = 0; i < BUFSIZE; i++) {
            double multiplier = 0.5 * (1.0 - cos(2.0 * G_PI * i / (BUFSIZE - 1)));
            in[i] = read_buf[i] * multiplier;
        }

        fftw_execute(plan);

        pthread_mutex_lock(&audio_mutex);
        for (int i = 0; i < BUFSIZE; i++) {
            audio_buffer[i] = read_buf[i];
        }
        for (int i = 0; i < BUFSIZE/2; i++) {
            double mag = sqrt(out[i][0]*out[i][0] + out[i][1]*out[i][1]);
            fft_out_mag[i] = mag;
        }
        pthread_mutex_unlock(&audio_mutex);
    }

    fftw_destroy_plan(plan);
    fftw_free(in);
    fftw_free(out);
    pa_simple_free(s);
    return NULL;
}

static gboolean on_draw_visualizer(GtkWidget *widget, cairo_t *cr, gpointer data) {
    (void)data;
    guint width = gtk_widget_get_allocated_width(widget);
    guint height = gtk_widget_get_allocated_height(widget);

    // Dark background
    cairo_set_source_rgb(cr, 0.1, 0.1, 0.12);
    cairo_paint(cr);

    pthread_mutex_lock(&audio_mutex);
    
    // Draw FFT spectrum
    int num_bars = 64;
    double bar_width = (double)width / num_bars;
    
    // Create a smooth gradient for bars
    cairo_pattern_t *pat = cairo_pattern_create_linear(0, height, 0, 0);
    cairo_pattern_add_color_stop_rgba(pat, 0.0, 0.2, 0.8, 0.5, 0.9);
    cairo_pattern_add_color_stop_rgba(pat, 0.8, 0.1, 0.6, 0.8, 0.9);
    cairo_pattern_add_color_stop_rgba(pat, 1.0, 0.8, 0.2, 0.2, 0.9);
    cairo_set_source(cr, pat);
    
    for (int i = 0; i < num_bars; i++) {
        int fft_idx = (i * (BUFSIZE/4)) / num_bars; // only look at lower half of frequencies (more bass/mids)
        double raw_mag = fft_out_mag[fft_idx] * 0.4;
        
        // Smoothing
        smoothed_mag[fft_idx] += (raw_mag - smoothed_mag[fft_idx]) * 0.2;
        double mag = smoothed_mag[fft_idx];
        
        if (mag > height) mag = height;
        if (mag < 2) mag = 2; // minimum bar height
        
        cairo_rectangle(cr, i * bar_width + 1, height - mag, bar_width - 2, mag);
        cairo_fill(cr);
    }
    
    cairo_pattern_destroy(pat);
    pthread_mutex_unlock(&audio_mutex);
    return FALSE;
}

static gboolean on_tick_visualizer(GtkWidget *widget, GdkFrameClock *frame_clock, gpointer user_data) {
    (void)frame_clock;
    (void)user_data;
    gtk_widget_queue_draw(widget);
    return G_SOURCE_CONTINUE;
}

static GtkWidget* create_visualizer_tab() {
    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    
    GtkWidget *drawing_area = gtk_drawing_area_new();
    gtk_widget_set_size_request(drawing_area, -1, 300);
    g_signal_connect(G_OBJECT(drawing_area), "draw", G_CALLBACK(on_draw_visualizer), NULL);
    gtk_widget_add_tick_callback(drawing_area, on_tick_visualizer, NULL, NULL);

    gtk_box_pack_start(GTK_BOX(vbox), drawing_area, TRUE, TRUE, 0);
    
    // Start Audio Thread
    pthread_t tid;
    pthread_create(&tid, NULL, pa_capture_thread, NULL);

    return vbox;
}

// Push 10 band dB values (32..16K) to the system EQ via ocws-eq-apply,
// which drives the mbeq PipeWire filter-chain. Returns immediately.
static void push_eq(double values[10]) {
    gchar *csv = g_strdup_printf("%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f",
        values[0], values[1], values[2], values[3], values[4],
        values[5], values[6], values[7], values[8], values[9]);
    gchar *cmd = g_strdup_printf("ocws-eq-apply apply \"%s\"", csv);
    g_print("Applying EQ: %s\n", csv);
    system(cmd);
    g_free(csv);
    g_free(cmd);
}

// Map a preset name to 10 band dB values (32,64,125,250,500,1K,2K,4K,8K,16K).
static void preset_to_bands(const gchar *name, double out[10]) {
    for (int i = 0; i < 10; i++) out[i] = 0.0;
    if (!name) return;
    if (strcmp(name, "Bass Boost") == 0) {
        double v[10] = {9,7,5,3,1,0,0,0,0,0}; memcpy(out, v, sizeof(v));
    } else if (strcmp(name, "Treble Boost") == 0) {
        double v[10] = {0,0,0,0,0,1,3,5,7,9}; memcpy(out, v, sizeof(v));
    } else if (strcmp(name, "Acoustic") == 0) {
        double v[10] = {-2,0,2,3,3,2,1,0,-1,-2}; memcpy(out, v, sizeof(v));
    } else if (strcmp(name, "Electronic") == 0) {
        double v[10] = {5,4,2,0,1,2,3,4,5,6}; memcpy(out, v, sizeof(v));
    } else if (strcmp(name, "Spoken Word") == 0) {
        double v[10] = {-4,-2,0,2,4,4,3,1,-1,-2}; memcpy(out, v, sizeof(v));
    }
    // "Default" and any EasyEffects-named preset -> flat
}

static void apply_preset(GtkWidget *widget, gpointer data) {
    (void)widget;
    (void)data;
    const gchar *preset_name = gtk_combo_box_text_get_active_text(GTK_COMBO_BOX_TEXT(preset_combo));
    if (preset_name) {
        double vals[10];
        preset_to_bands(preset_name, vals);
        push_eq(vals);
        g_print("Applied preset: %s\n", preset_name);
    }
}

static void load_presets() {
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
                    char name[256];
                    strncpy(name, ent->d_name, sizeof(name));
                    char *dot = strrchr(name, '.');
                    if (dot) *dot = '\0';
                    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(preset_combo), name);
                }
            }
            closedir(dir);
        }
    }
    gtk_combo_box_set_active(GTK_COMBO_BOX(preset_combo), 0);
}

static void apply_custom_eq(GtkWidget *widget, gpointer data) {
    (void)widget;
    (void)data;
    g_print("Generating custom EQ preset...\n");
    double values[10];
    for (int i = 0; i < 10; i++) {
        values[i] = gtk_range_get_value(GTK_RANGE(sliders[i]));
        g_print("Band %s: %.1f dB\n", freq_labels[i], values[i]);
    }
    // Apply directly to the system EQ via the mbeq PipeWire filter-chain.
    push_eq(values);
}

static void reset_custom_eq(GtkWidget *widget, gpointer data) {
    (void)widget;
    (void)data;
    for (int i = 0; i < 10; i++) {
        gtk_range_set_value(GTK_RANGE(sliders[i]), 0.0);
    }
}

static GtkWidget* create_presets_tab() {
    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 15);
    gtk_widget_set_margin_top(vbox, 30);
    gtk_widget_set_margin_bottom(vbox, 30);
    gtk_widget_set_margin_start(vbox, 30);
    gtk_widget_set_margin_end(vbox, 30);

    GtkWidget *label = gtk_label_new("Select an EasyEffects Preset:");
    gtk_box_pack_start(GTK_BOX(vbox), label, FALSE, FALSE, 0);

    preset_combo = gtk_combo_box_text_new();
    load_presets();
    gtk_box_pack_start(GTK_BOX(vbox), preset_combo, FALSE, FALSE, 0);

    GtkWidget *apply_btn = gtk_button_new_with_label("Apply Preset");
    gtk_style_context_add_class(gtk_widget_get_style_context(apply_btn), "suggested-action");
    g_signal_connect(apply_btn, "clicked", G_CALLBACK(apply_preset), NULL);
    gtk_box_pack_start(GTK_BOX(vbox), apply_btn, FALSE, FALSE, 0);

    return vbox;
}

static GtkWidget* create_custom_eq_tab() {
    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 15);
    gtk_widget_set_margin_top(vbox, 30);
    gtk_widget_set_margin_bottom(vbox, 30);
    gtk_widget_set_margin_start(vbox, 30);
    gtk_widget_set_margin_end(vbox, 30);

    GtkWidget *hbox_sliders = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
    gtk_box_set_homogeneous(GTK_BOX(hbox_sliders), TRUE);
    
    for (int i = 0; i < 10; i++) {
        GtkWidget *band_vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 5);
        
        sliders[i] = gtk_scale_new_with_range(GTK_ORIENTATION_VERTICAL, -12.0, 12.0, 0.1);
        gtk_range_set_value(GTK_RANGE(sliders[i]), 0.0);
        gtk_range_set_inverted(GTK_RANGE(sliders[i]), TRUE);
        gtk_widget_set_size_request(sliders[i], -1, 200);
        
        GtkWidget *freq_label = gtk_label_new(freq_labels[i]);
        
        gtk_box_pack_start(GTK_BOX(band_vbox), sliders[i], TRUE, TRUE, 0);
        gtk_box_pack_start(GTK_BOX(band_vbox), freq_label, FALSE, FALSE, 0);
        
        gtk_box_pack_start(GTK_BOX(hbox_sliders), band_vbox, TRUE, TRUE, 0);
    }
    
    gtk_box_pack_start(GTK_BOX(vbox), hbox_sliders, TRUE, TRUE, 10);

    GtkWidget *btn_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
    gtk_widget_set_halign(btn_box, GTK_ALIGN_CENTER);

    GtkWidget *reset_btn = gtk_button_new_with_label("Reset");
    g_signal_connect(reset_btn, "clicked", G_CALLBACK(reset_custom_eq), NULL);
    gtk_box_pack_start(GTK_BOX(btn_box), reset_btn, FALSE, FALSE, 0);

    GtkWidget *apply_btn = gtk_button_new_with_label("Apply Custom EQ");
    gtk_style_context_add_class(gtk_widget_get_style_context(apply_btn), "suggested-action");
    g_signal_connect(apply_btn, "clicked", G_CALLBACK(apply_custom_eq), NULL);
    gtk_box_pack_start(GTK_BOX(btn_box), apply_btn, FALSE, FALSE, 0);

    gtk_box_pack_start(GTK_BOX(vbox), btn_box, FALSE, FALSE, 0);

    return vbox;
}

static void activate(GtkApplication *app, gpointer user_data) {
    (void)user_data;

    GtkWidget *window = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(window), "OCWS Equalizer");
    gtk_window_set_default_size(GTK_WINDOW(window), 650, 450);
    gtk_window_set_position(GTK_WINDOW(window), GTK_WIN_POS_CENTER);

    // Header Bar
    GtkWidget *header = gtk_header_bar_new();
    gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(header), TRUE);
    gtk_header_bar_set_title(GTK_HEADER_BAR(header), "OCWS Equalizer");
    gtk_header_bar_set_subtitle(GTK_HEADER_BAR(header), "Integrated Audio & Visualizer");
    gtk_window_set_titlebar(GTK_WINDOW(window), header);

    // Main Stack & Switcher
    GtkWidget *vbox_main = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(window), vbox_main);

    GtkWidget *stack = gtk_stack_new();
    gtk_stack_set_transition_type(GTK_STACK(stack), GTK_STACK_TRANSITION_TYPE_SLIDE_LEFT_RIGHT);
    
    GtkWidget *switcher = gtk_stack_switcher_new();
    gtk_stack_switcher_set_stack(GTK_STACK_SWITCHER(switcher), GTK_STACK(stack));
    gtk_header_bar_set_custom_title(GTK_HEADER_BAR(header), switcher);

    // Add Tabs
    gtk_stack_add_titled(GTK_STACK(stack), create_presets_tab(), "presets", "Presets");
    gtk_stack_add_titled(GTK_STACK(stack), create_custom_eq_tab(), "custom", "10-Band EQ");
    gtk_stack_add_titled(GTK_STACK(stack), create_visualizer_tab(), "visualizer", "Visualizer");

    gtk_box_pack_start(GTK_BOX(vbox_main), stack, TRUE, TRUE, 0);

    // Initialize the background app abstraction (tray icon, hold running, handle hide-on-close)
    ocws_background_app_init(app, window, "audio-volume-high");
}

int main(int argc, char **argv) {
    // Optionally daemonize if you want it completely detached from the shell
    // ocws_daemonize();

    GtkApplication *app = gtk_application_new("org.ocws.equalizer", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return status;
}
