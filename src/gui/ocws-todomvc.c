#include <gtk/gtk.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#define MAX_TODOS 256
#define MAX_LEN 256

typedef struct { char text[MAX_LEN]; int done; } Todo;

static Todo todos[MAX_TODOS];
static int todo_count = 0;
static int filter = 0; /* 0 all, 1 active, 2 completed */

static GtkWidget *entry;
static GtkWidget *listbox;
static GtkWidget *footer_label;
static GtkWidget *clear_btn;
static GtkWidget *toggle_all;

static void rebuild_list(void);
static void on_toggle(GtkWidget *chk, gpointer d);
static void on_edit(GtkWidget *row, gpointer d);

static const char *store_path(void) {
    static char path[512];
    const char *home = getenv("HOME");
    snprintf(path, sizeof(path), "%s/.local/share/ocws/todos.txt", home ? home : ".");
    return path;
}

static void load_todos(void) {
    FILE *f = fopen(store_path(), "r");
    if (!f) return;
    while (todo_count < MAX_TODOS && fgets(todos[todo_count].text, MAX_LEN, f)) {
        size_t n = strlen(todos[todo_count].text);
        while (n > 0 && (todos[todo_count].text[n-1] == '\n' || todos[todo_count].text[n-1] == '\r'))
            todos[todo_count].text[--n] = 0;
        if (n == 0) continue;
        todos[todo_count].done = (n > 1 && todos[todo_count].text[0] == 'x' && todos[todo_count].text[1] == ' ');
        if (todos[todo_count].done) memmove(todos[todo_count].text, todos[todo_count].text + 2, n - 1);
        todo_count++;
    }
    fclose(f);
}

static void save_todos(void) {
    FILE *f = fopen(store_path(), "w");
    if (!f) return;
    for (int i = 0; i < todo_count; i++)
        fprintf(f, "%s%s\n", todos[i].done ? "x " : "", todos[i].text);
    fclose(f);
}

static int active_count(void) {
    int n = 0;
    for (int i = 0; i < todo_count; i++) if (!todos[i].done) n++;
    return n;
}

static void update_footer(void) {
    int active = active_count();
    char buf[64];
    snprintf(buf, sizeof(buf), "%d item%s left", active, active == 1 ? "" : "s");
    gtk_label_set_text(GTK_LABEL(footer_label), buf);
    int any_done = 0;
    for (int i = 0; i < todo_count; i++) if (todos[i].done) any_done = 1;
    gtk_widget_set_sensitive(clear_btn, any_done);
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(toggle_all), active == 0 && todo_count > 0);
}

static void rebuild_list(void) {
    GList *children = gtk_container_get_children(GTK_CONTAINER(listbox));
    for (GList *c = children; c; c = c->next)
        gtk_container_remove(GTK_CONTAINER(listbox), GTK_WIDGET(c->data));
    g_list_free(children);

    for (int i = 0; i < todo_count; i++) {
        if (filter == 1 && todos[i].done) continue;
        if (filter == 2 && !todos[i].done) continue;

        GtkWidget *row = gtk_list_box_row_new();
        GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *chk = gtk_check_button_new();
        gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(chk), todos[i].done);

        GtkWidget *lbl = gtk_label_new(todos[i].text);
        gtk_label_set_xalign(GTK_LABEL(lbl), 0.0);
        gtk_widget_set_hexpand(lbl, TRUE);
        if (todos[i].done) {
            /* strikethrough for completed */
            PangoAttrList *attrs = pango_attr_list_new();
            PangoAttribute *st = pango_attr_strikethrough_new(TRUE);
            pango_attr_list_insert(attrs, st);
            gtk_label_set_attributes(GTK_LABEL(lbl), attrs);
            pango_attr_list_unref(attrs);
        }

        gtk_box_pack_start(GTK_BOX(box), chk, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(box), lbl, TRUE, TRUE, 0);
        gtk_container_add(GTK_CONTAINER(row), box);

        /* store index for callbacks */
        g_object_set_data(G_OBJECT(chk), "idx", GINT_TO_POINTER(i));
        g_signal_connect(chk, "toggled", G_CALLBACK(on_toggle), NULL);
        g_object_set_data(G_OBJECT(row), "idx", GINT_TO_POINTER(i));
        g_signal_connect(row, "activate", G_CALLBACK(on_edit), NULL);

        gtk_list_box_insert(GTK_LIST_BOX(listbox), row, -1);
    }
    gtk_widget_show_all(listbox);
    update_footer();
}

static void on_toggle(GtkWidget *chk, gpointer d) {
    int idx = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(chk), "idx"));
    if (idx >= 0 && idx < todo_count) {
        todos[idx].done = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(chk));
        save_todos();
        rebuild_list();
    }
}

static void on_edit(GtkWidget *row, gpointer d) {
    int idx = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "idx"));
    if (idx < 0 || idx >= todo_count) return;
    GtkWidget *dialog = gtk_dialog_new_with_buttons("Edit",
        GTK_WINDOW(gtk_widget_get_toplevel(row)), GTK_DIALOG_MODAL,
        "_OK", GTK_RESPONSE_OK, "_Cancel", GTK_RESPONSE_CANCEL, NULL);
    GtkWidget *dentry = gtk_entry_new();
    gtk_entry_set_text(GTK_ENTRY(dentry), todos[idx].text);
    gtk_box_pack_start(GTK_BOX(gtk_dialog_get_content_area(GTK_DIALOG(dialog))), dentry, TRUE, TRUE, 8);
    gtk_widget_show_all(dialog);
    if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_OK) {
        const char *t = gtk_entry_get_text(GTK_ENTRY(dentry));
        if (t && *t) {
            strncpy(todos[idx].text, t, MAX_LEN - 1);
            todos[idx].text[MAX_LEN - 1] = 0;
            save_todos();
            rebuild_list();
        }
    }
    gtk_widget_destroy(dialog);
}

static void on_activate_entry(GtkWidget *e, gpointer d) {
    const char *t = gtk_entry_get_text(GTK_ENTRY(e));
    if (!t || !*t) return;
    if (todo_count >= MAX_TODOS) return;
    strncpy(todos[todo_count].text, t, MAX_LEN - 1);
    todos[todo_count].text[MAX_LEN - 1] = 0;
    todos[todo_count].done = 0;
    todo_count++;
    gtk_entry_set_text(GTK_ENTRY(e), "");
    save_todos();
    rebuild_list();
}

static void on_toggle_all(GtkWidget *btn, gpointer d) {
    int state = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(btn));
    for (int i = 0; i < todo_count; i++) todos[i].done = state;
    save_todos();
    rebuild_list();
}

static void on_filter(GtkWidget *btn, gpointer d) {
    filter = GPOINTER_TO_INT(d);
    rebuild_list();
}

static void on_clear(GtkWidget *btn, gpointer d) {
    int w = 0;
    for (int i = 0; i < todo_count; i++)
        if (!todos[i].done) todos[w++] = todos[i];
    todo_count = w;
    save_todos();
    rebuild_list();
}

int main(int argc, char *argv[]) {
    gtk_init(&argc, &argv);

    GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(window), "OCWS TodoMVC");
    gtk_window_set_default_size(GTK_WINDOW(window), 380, 460);
    gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
    gtk_window_set_keep_above(GTK_WINDOW(window), TRUE);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(vbox), 10);

    /* header: toggle-all + entry */
    GtkWidget *hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    toggle_all = gtk_check_button_new();
    entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(entry), "What needs to be done?");
    gtk_box_pack_start(GTK_BOX(hbox), toggle_all, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), entry, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), hbox, FALSE, FALSE, 0);

    listbox = gtk_list_box_new();
    gtk_list_box_set_selection_mode(GTK_LIST_BOX(listbox), GTK_SELECTION_NONE);
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_widget_set_vexpand(scroll, TRUE);
    gtk_container_add(GTK_CONTAINER(scroll), listbox);
    gtk_box_pack_start(GTK_BOX(vbox), scroll, TRUE, TRUE, 0);

    /* footer */
    GtkWidget *fbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    footer_label = gtk_label_new("0 items left");
    gtk_label_set_xalign(GTK_LABEL(footer_label), 0.0);
    gtk_widget_set_hexpand(footer_label, TRUE);

    GtkWidget *f_all = gtk_button_new_with_label("All");
    GtkWidget *f_act = gtk_button_new_with_label("Active");
    GtkWidget *f_cmp = gtk_button_new_with_label("Completed");
    clear_btn = gtk_button_new_with_label("Clear completed");

    gtk_box_pack_start(GTK_BOX(fbox), footer_label, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(fbox), f_all, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(fbox), f_act, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(fbox), f_cmp, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(fbox), clear_btn, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), fbox, FALSE, FALSE, 0);

    gtk_container_add(GTK_CONTAINER(window), vbox);

    g_signal_connect(window, "destroy", G_CALLBACK(gtk_main_quit), NULL);
    g_signal_connect(entry, "activate", G_CALLBACK(on_activate_entry), NULL);
    g_signal_connect(toggle_all, "toggled", G_CALLBACK(on_toggle_all), NULL);
    g_signal_connect(clear_btn, "clicked", G_CALLBACK(on_clear), NULL);
    g_signal_connect(f_all, "clicked", G_CALLBACK(on_filter), GINT_TO_POINTER(0));
    g_signal_connect(f_act, "clicked", G_CALLBACK(on_filter), GINT_TO_POINTER(1));
    g_signal_connect(f_cmp, "clicked", G_CALLBACK(on_filter), GINT_TO_POINTER(2));

    load_todos();
    rebuild_list();
    gtk_widget_show_all(window);
    gtk_main();
    return 0;
}