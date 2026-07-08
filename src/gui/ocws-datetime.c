#include <gtk/gtk.h>
#include <cairo.h>
#include <time.h>
#include <math.h>
#include <string.h>

#define M_PI 3.14159265358979323846

static int window_width = 300;
static int window_height = 350;

static gboolean on_draw(GtkWidget *widget, cairo_t *cr, gpointer data) {
    time_t now = time(NULL);
    struct tm *t = localtime(&now);

    // Background
    cairo_set_source_rgb(cr, 0.05, 0.05, 0.1);
    cairo_paint(cr);

    double cx = window_width / 2.0;
    double cy = window_height / 2.0 - 20;
    double radius = 100.0;

    // Clock Face
    cairo_set_source_rgb(cr, 0.8, 0.8, 0.9);
    cairo_set_line_width(cr, 4.0);
    cairo_arc(cr, cx, cy, radius, 0, 2 * M_PI);
    cairo_stroke(cr);

    // Hour Markers
    for (int i = 0; i < 12; i++) {
        double angle = (i * 30) * M_PI / 180.0;
        double x1 = cx + (radius - 10) * sin(angle);
        double y1 = cy - (radius - 10) * cos(angle);
        double x2 = cx + radius * sin(angle);
        double y2 = cy - radius * cos(angle);
        cairo_move_to(cr, x1, y1);
        cairo_line_to(cr, x2, y2);
        cairo_stroke(cr);
    }

    // Hands
    double h_angle = (t->tm_hour % 12 + t->tm_min / 60.0) * 30.0 * M_PI / 180.0;
    double m_angle = (t->tm_min + t->tm_sec / 60.0) * 6.0 * M_PI / 180.0;
    double s_angle = t->tm_sec * 6.0 * M_PI / 180.0;

    // Hour hand
    cairo_set_source_rgb(cr, 0.9, 0.9, 0.9);
    cairo_set_line_width(cr, 6.0);
    cairo_move_to(cr, cx, cy);
    cairo_line_to(cr, cx + 60 * sin(h_angle), cy - 60 * cos(h_angle));
    cairo_stroke(cr);

    // Minute hand
    cairo_set_source_rgb(cr, 0.7, 0.7, 0.8);
    cairo_set_line_width(cr, 4.0);
    cairo_move_to(cr, cx, cy);
    cairo_line_to(cr, cx + 80 * sin(m_angle), cy - 80 * cos(m_angle));
    cairo_stroke(cr);

    // Second hand
    cairo_set_source_rgb(cr, 1.0, 0.3, 0.3);
    cairo_set_line_width(cr, 2.0);
    cairo_move_to(cr, cx, cy);
    cairo_line_to(cr, cx + 90 * sin(s_angle), cy - 90 * cos(s_angle));
    cairo_stroke(cr);

    // Date and Time Text
    char date_buf[64];
    char time_buf[32];
    strftime(date_buf, sizeof(date_buf), "%A, %B %d, %Y", t);
    strftime(time_buf, sizeof(time_buf), "%H:%M:%S", t);

    cairo_set_source_rgb(cr, 0.8, 0.8, 0.9);
    cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, 14.0);
    
    // Center text
    cairo_text_extents_t ext;
    cairo_text_extents(cr, date_buf, &ext);
    cairo_move_to(cr, cx - ext.width / 2, cy + radius + 30);
    cairo_show_text(cr, date_buf);

    cairo_set_font_size(cr, 20.0);
    cairo_text_extents(cr, time_buf, &ext);
    cairo_move_to(cr, cx - ext.width / 2, cy + radius + 50);
    cairo_show_text(cr, time_buf);

    return FALSE;
}

static gboolean update_clock(GtkWidget *widget) {
    gtk_widget_queue_draw(widget);
    return TRUE;
}

int main(int argc, char *argv[]) {
    gtk_init(&argc, &argv);

    GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(window), "OCWS Datetime");
    gtk_window_set_default_size(GTK_WINDOW(window), window_width, window_height);
    gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
    gtk_window_set_keep_above(GTK_WINDOW(window), TRUE);

    GtkWidget *drawing_area = gtk_drawing_area_new();
    gtk_container_add(GTK_CONTAINER(window), drawing_area);

    g_signal_connect(G_OBJECT(window), "destroy", G_CALLBACK(gtk_main_quit), NULL);
    g_signal_connect(G_OBJECT(drawing_area), "draw", G_CALLBACK(on_draw), NULL);

    g_timeout_add(1000, (GSourceFunc)update_clock, drawing_area);

    gtk_widget_show_all(window);
    gtk_main();

    return 0;
}