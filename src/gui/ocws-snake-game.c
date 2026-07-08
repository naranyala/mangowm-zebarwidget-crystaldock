#include <gtk/gtk.h>
#include <cairo.h>
#include <stdlib.h>
#include <time.h>

#define GRID 20
#define CELL 20
#define MARGIN 10
#define WIN_W (GRID * CELL + MARGIN * 2)
#define WIN_H (GRID * CELL + MARGIN * 2 + 30)

enum { UP, DOWN, LEFT, RIGHT };

typedef struct { int x, y; } Pt;

static Pt snake[GRID * GRID];
static int snake_len = 3;
static int dir = RIGHT;
static int next_dir = RIGHT;
static Pt food;
static int score = 0;
static int game_over = 0;
static GtkWidget *draw_area;

static gboolean on_draw(GtkWidget *w, cairo_t *cr, gpointer d) {
    // Background
    cairo_set_source_rgb(cr, 0.06, 0.06, 0.10);
    cairo_paint(cr);

    // Grid border
    cairo_set_source_rgb(cr, 0.3, 0.3, 0.4);
    cairo_rectangle(cr, MARGIN, MARGIN, GRID * CELL, GRID * CELL);
    cairo_stroke(cr);

    // Food
    cairo_set_source_rgb(cr, 1.0, 0.3, 0.3);
    cairo_rectangle(cr, MARGIN + food.x * CELL + 2, MARGIN + food.y * CELL + 2,
                    CELL - 4, CELL - 4);
    cairo_fill(cr);

    // Snake
    for (int i = 0; i < snake_len; i++) {
        double f = (double)i / snake_len;
        cairo_set_source_rgb(cr, 0.3 + 0.5 * (1 - f), 0.8 * (1 - f) + 0.2, 0.5 * f + 0.3);
        cairo_rectangle(cr, MARGIN + snake[i].x * CELL + 1, MARGIN + snake[i].y * CELL + 1,
                        CELL - 2, CELL - 2);
        cairo_fill(cr);
    }

    // HUD
    char buf[64];
    cairo_set_source_rgb(cr, 0.8, 0.8, 0.9);
    cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    cairo_set_font_size(cr, 14);
    if (game_over) {
        snprintf(buf, sizeof(buf), "Game Over! Score %d — press R", score);
    } else {
        snprintf(buf, sizeof(buf), "Score: %d", score);
    }
    cairo_move_to(cr, MARGIN, WIN_H - 10);
    cairo_show_text(cr, buf);

    return FALSE;
}

static void reset_game(void) {
    snake_len = 3;
    dir = next_dir = RIGHT;
    score = 0;
    game_over = 0;
    for (int i = 0; i < snake_len; i++) {
        snake[i].x = GRID / 2 - i;
        snake[i].y = GRID / 2;
    }
    food.x = rand() % GRID;
    food.y = rand() % GRID;
}

static gboolean tick(gpointer d) {
    if (!game_over) {
        next_dir = dir;
        Pt head = snake[0];
        switch (dir) {
            case UP:    head.y--; break;
            case DOWN:  head.y++; break;
            case LEFT:  head.x--; break;
            case RIGHT: head.x++; break;
        }
        if (head.x < 0 || head.x >= GRID || head.y < 0 || head.y >= GRID) {
            game_over = 1;
        } else {
            for (int i = 0; i < snake_len; i++) {
                if (snake[i].x == head.x && snake[i].y == head.y) game_over = 1;
            }
        }
        if (!game_over) {
            if (head.x == food.x && head.y == food.y) {
                if (snake_len < GRID * GRID) snake_len++;
                score++;
                food.x = rand() % GRID;
                food.y = rand() % GRID;
            }
            for (int i = snake_len - 1; i > 0; i--) snake[i] = snake[i - 1];
            snake[0] = head;
        }
    }
    gtk_widget_queue_draw(draw_area);
    return TRUE;
}

static gboolean on_key(GtkWidget *w, GdkEventKey *e, gpointer d) {
    switch (e->keyval) {
        case GDK_KEY_Up:    if (dir != DOWN)  next_dir = UP;    break;
        case GDK_KEY_Down:  if (dir != UP)    next_dir = DOWN;  break;
        case GDK_KEY_Left:  if (dir != RIGHT) next_dir = LEFT;  break;
        case GDK_KEY_Right: if (dir != LEFT)  next_dir = RIGHT; break;
        case GDK_KEY_r:
        case GDK_KEY_R:     reset_game(); break;
        default: return FALSE;
    }
    dir = next_dir;
    return TRUE;
}

int main(int argc, char *argv[]) {
    gtk_init(&argc, &argv);
    srand((unsigned)time(NULL));

    GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(window), "OCWS Snake");
    gtk_window_set_default_size(GTK_WINDOW(window), WIN_W, WIN_H);
    gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
    gtk_window_set_keep_above(GTK_WINDOW(window), TRUE);

    draw_area = gtk_drawing_area_new();
    gtk_container_add(GTK_CONTAINER(window), draw_area);
    gtk_widget_add_events(window, GDK_KEY_PRESS_MASK);
    gtk_widget_set_can_focus(draw_area, TRUE);
    gtk_widget_grab_focus(draw_area);

    g_signal_connect(G_OBJECT(window), "destroy", G_CALLBACK(gtk_main_quit), NULL);
    g_signal_connect(G_OBJECT(draw_area), "draw", G_CALLBACK(on_draw), NULL);
    g_signal_connect(G_OBJECT(window), "key_press_event", G_CALLBACK(on_key), NULL);

    reset_game();
    g_timeout_add(120, tick, draw_area);

    gtk_widget_show_all(window);
    gtk_main();
    return 0;
}