#include "widgets.h"
#include "toplevel.h"
#include "menu.h"
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"
#include <cairo/cairo.h>
#include <pango/pangocairo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/statvfs.h>

static struct wl_seat *g_menu_seat = NULL;
static void act_focus(void *arg) {
  struct zwlr_foreign_toplevel_handle_v1 *h =
    (struct zwlr_foreign_toplevel_handle_v1*)arg;
  if (h && g_menu_seat)
    zwlr_foreign_toplevel_handle_v1_activate(h, g_menu_seat);
}

// tiny dynamic menu-item builder
typedef struct { menu_item_t *a; int n, cap; } mb_t;
static void mb_add(mb_t *b, menu_item_t it) {
  if (b->n >= b->cap) {
    b->cap = b->cap ? b->cap * 2 : 8;
    b->a = (menu_item_t*)realloc(b->a, (size_t)b->cap * sizeof(menu_item_t));
  }
  b->a[b->n++] = it;
}
static menu_item_t mi(const char *label, const char *detail, const char *cmd) {
  menu_item_t it; memset(&it, 0, sizeof(it));
  it.label = (char*)label; it.detail = (char*)detail; it.cmd = (char*)cmd;
  return it;
}
static void mb_sep(mb_t *b) { mb_add(b, mi(NULL, NULL, NULL)); b->a[b->n-1].separator = true; }

// forward declarations of per-widget menu openers
static int ws_menu(widget_t*, int, int);
static int tl_menu(widget_t*, int, int);
static int run_menu(widget_t*, int, int);
static int cpu_menu(widget_t*, int, int);
static int mem_menu(widget_t*, int, int);
static int temp_menu(widget_t*, int, int);
static int disk_menu(widget_t*, int, int);
static int bat_menu(widget_t*, int, int);
static int vol_menu(widget_t*, int, int);
static int net_menu(widget_t*, int, int);
static int media_menu(widget_t*, int, int);
static int clk_menu(widget_t*, int, int);
static int pwr_menu(widget_t*, int, int);

static const char *opt_get(const char *opts, const char *key, char *buf, size_t n) {
  if (!opts) return NULL;
  const char *p = opts;
  size_t kl = strlen(key);
  while (*p) {
    if (!strncmp(p, key, kl) && p[kl] == '=') {
      const char *v = p + kl + 1;
      while (*v == ' ' || *v == '\t') v++;
      const char *e = strchr(v, '\n');
      size_t l = e ? (size_t)(e - v) : strlen(v);
      while (l > 0 && (v[l-1] == ' ' || v[l-1] == '\t' || v[l-1] == '\r')) l--;
      if (l >= n) l = n - 1;
      memcpy(buf, v, l);
      buf[l] = 0;
      return buf;
    }
    const char *nl = strchr(p, '\n');
    if (!nl) break;
    p = nl + 1;
  }
  return NULL;
}

static int read_cmd_int(const char *cmd, int def) {
  FILE *f = popen(cmd, "r");
  if (!f) return def;
  char b[256];
  int v = def;
  if (fgets(b, sizeof(b), f)) v = atoi(b);
  pclose(f);
  return v;
}

static char *read_cmd_str(const char *cmd) {
  FILE *f = popen(cmd, "r");
  if (!f) return strdup("");
  char b[512];
  if (!fgets(b, sizeof(b), f)) { pclose(f); return strdup(""); }
  size_t l = strlen(b);
  while (l && (b[l-1] == '\n' || b[l-1] == '\r')) b[--l] = 0;
  char *r = strdup(b);
  pclose(f);
  return r;
}

static char *read_file_str(const char *path) {
  FILE *f = fopen(path, "r");
  if (!f) return strdup("");
  char b[256];
  if (!fgets(b, sizeof(b), f)) { fclose(f); return strdup(""); }
  size_t l = strlen(b);
  while (l && (b[l-1] == '\n' || b[l-1] == '\r')) b[--l] = 0;
  char *r = strdup(b);
  fclose(f);
  return r;
}

static int read_file_int(const char *path, int def) {
  char *s = read_file_str(path);
  int v = s && *s ? atoi(s) : def;
  free(s);
  return v;
}

/* ---------------- workspaces ---------------- */

typedef struct { char labels[64]; } ws_priv_t;
static int ws_measure(widget_t *w, int h) {
  ws_priv_t *p = (ws_priv_t*)w->priv;
  return (int)(strlen(p->labels) * 7) + 8;
}
static void ws_draw(widget_t *w, cairo_t *cr, int x, int y, int h) {
  ws_priv_t *p = (ws_priv_t*)w->priv;
  widget_text(cr, p->labels, x, h, "Sans 10", 0.6, 0.6, 0.7);
}
widget_t *w_workspaces_create(const char *opts) {
  ws_priv_t *p = (ws_priv_t*)calloc(1, sizeof(*p));
  char buf[64];
  if (opt_get(opts, "labels", buf, sizeof(buf))) snprintf(p->labels, sizeof(p->labels), " %s ", buf);
  else snprintf(p->labels, sizeof(p->labels), " 1 2 3 4 ");
  widget_t *w = (widget_t*)calloc(1, sizeof(*w));
  w->type = "workspaces"; w->priv = p;
  w->menu_open = ws_menu;
  w->measure = ws_measure; w->draw = ws_draw;
  return w;
}

/* ---------------- toplevel taskbar ---------------- */

#define TL_APP_W 14

static int tl_measure(widget_t *w, int h) {
  struct panel_ctx *c = (struct panel_ctx*)w->ctx;
  int n = c ? *c->count : 0;
  return n * TL_APP_W + 2;
}
static void tl_draw(widget_t *w, cairo_t *cr, int x, int y, int h) {
  struct panel_ctx *c = (struct panel_ctx*)w->ctx;
  if (!c) return;
  struct toplevel_info *t = c->toplevels;
  int n = *c->count;
  int xo = x;
  int bw = 10, by = 6, bh = h - 12;
  if (bh < 4) bh = 4;
  for (int i = 0; i < n; i++) {
    if (t[i].focused) cairo_set_source_rgb(cr, 0.55, 0.80, 1.0);
    else cairo_set_source_rgb(cr, 0.40, 0.42, 0.46);
    cairo_rectangle(cr, xo + 2, by, bw, bh);
    cairo_fill(cr);
    xo += TL_APP_W;
  }
}
static bool tl_click(widget_t *w, int btn, int x, int y) {
  if (btn != 1) return false;
  struct panel_ctx *c = (struct panel_ctx*)w->ctx;
  if (!c || !c->seat) return false;
  int n = *c->count;
  if (n <= 0) return false;
  int idx = x / TL_APP_W;
  if (idx < 0 || idx >= n) return false;
  struct zwlr_foreign_toplevel_handle_v1 *handle =
    (struct zwlr_foreign_toplevel_handle_v1*)c->toplevels[idx].handle;
  if (handle) zwlr_foreign_toplevel_handle_v1_activate(handle, c->seat);
  return true;
}
widget_t *w_toplevel_create(const char *opts) {
  widget_t *w = (widget_t*)calloc(1, sizeof(*w));
  w->type = "toplevel";
  w->menu_open = tl_menu;
  w->measure = tl_measure; w->draw = tl_draw; w->click = tl_click;
  return w;
}

/* ---------------- launcher ---------------- */

typedef struct { char cmd[128]; } run_priv_t;
static int run_measure(widget_t *w, int h) { return 22; }
static void run_draw(widget_t *w, cairo_t *cr, int x, int y, int h) {
  widget_icon_glyph(cr, "⌘", x + 4, h, 0.8, 0.8, 0.85);
}
static bool run_click(widget_t *w, int btn, int x, int y) {
  if (btn != 1) return false;
  run_priv_t *p = (run_priv_t*)w->priv;
  if (p->cmd[0]) system(p->cmd);
  return true;
}
widget_t *w_launcher_create(const char *opts) {
  run_priv_t *p = (run_priv_t*)calloc(1, sizeof(*p));
  char buf[128];
  if (opt_get(opts, "cmd", buf, sizeof(buf))) snprintf(p->cmd, sizeof(p->cmd), "%s &", buf);
  else snprintf(p->cmd, sizeof(p->cmd), "fuzzel &");
  widget_t *w = (widget_t*)calloc(1, sizeof(*w));
  w->type = "launcher"; w->priv = p;
  w->menu_open = run_menu;
  w->measure = run_measure; w->draw = run_draw; w->click = run_click;
  return w;
}

/* ---------------- cpu ---------------- */

typedef struct { int prev_total, prev_idle; char txt[32]; } cpu_priv_t;
static void cpu_update(widget_t *w) {
  cpu_priv_t *p = (cpu_priv_t*)w->priv;
  FILE *f = fopen("/proc/stat", "r");
  if (!f) return;
  char line[128];
  if (fgets(line, sizeof(line), f)) {
    int u, n, s, i, io, irq, sirq;
    if (sscanf(line, "cpu %d %d %d %d %d %d %d", &u, &n, &s, &i, &io, &irq, &sirq) >= 4) {
      int idle = i + io;
      int total = u + n + s + i + io + irq + sirq;
      int dtotal = total - p->prev_total;
      int didle = idle - p->prev_idle;
      if (dtotal > 0) {
        int pct = 100 * (dtotal - didle) / dtotal;
        snprintf(p->txt, sizeof(p->txt), "CPU %d%%", pct);
      }
      p->prev_total = total; p->prev_idle = idle;
    }
  }
  fclose(f);
}
static int cpu_measure(widget_t *w, int h) { return 64; }
static void cpu_draw(widget_t *w, cairo_t *cr, int x, int y, int h) {
  cpu_priv_t *p = (cpu_priv_t*)w->priv;
  widget_icon_glyph(cr, "▸", x, h, 0.5, 0.7, 0.9);
  widget_text(cr, p->txt, x + 16, h, "Sans 9", 0.8, 0.8, 0.82);
}
widget_t *w_cpu_create(const char *opts) {
  cpu_priv_t *p = (cpu_priv_t*)calloc(1, sizeof(*p));
  snprintf(p->txt, sizeof(p->txt), "CPU --");
  widget_t *w = (widget_t*)calloc(1, sizeof(*w));
  w->type = "cpu"; w->priv = p;
  w->menu_open = cpu_menu;
  w->measure = cpu_measure; w->draw = cpu_draw; w->update = cpu_update;
  return w;
}

/* ---------------- memory ---------------- */

typedef struct { char txt[32]; } mem_priv_t;
static void mem_update(widget_t *w) {
  mem_priv_t *p = (mem_priv_t*)w->priv;
  long total = 0, avail = 0;
  FILE *f = fopen("/proc/meminfo", "r");
  if (!f) return;
  char k[32]; long v;
  while (fscanf(f, "%31s %ld kB", k, &v) == 2) {
    if (!strcmp(k, "MemTotal:")) total = v;
    else if (!strcmp(k, "MemAvailable:")) avail = v;
  }
  fclose(f);
  if (total > 0) {
    long used = total - avail;
    snprintf(p->txt, sizeof(p->txt), "MEM %d%%", (int)(100 * used / total));
  }
}
static int mem_measure(widget_t *w, int h) { return 70; }
static void mem_draw(widget_t *w, cairo_t *cr, int x, int y, int h) {
  mem_priv_t *p = (mem_priv_t*)w->priv;
  widget_icon_glyph(cr, "▤", x, h, 0.6, 0.6, 0.9);
  widget_text(cr, p->txt, x + 16, h, "Sans 9", 0.8, 0.8, 0.82);
}
widget_t *w_mem_create(const char *opts) {
  mem_priv_t *p = (mem_priv_t*)calloc(1, sizeof(*p));
  snprintf(p->txt, sizeof(p->txt), "MEM --");
  widget_t *w = (widget_t*)calloc(1, sizeof(*w));
  w->type = "mem"; w->priv = p;
  w->menu_open = mem_menu;
  w->measure = mem_measure; w->draw = mem_draw; w->update = mem_update;
  return w;
}

/* ---------------- temperature ---------------- */

typedef struct { char txt[32]; } temp_priv_t;
static void temp_update(widget_t *w) {
  temp_priv_t *p = (temp_priv_t*)w->priv;
  int mt = read_file_int("/sys/class/thermal/thermal_zone0/temp", -1);
  if (mt > 0) snprintf(p->txt, sizeof(p->txt), "%d°C", mt / 1000);
  else snprintf(p->txt, sizeof(p->txt), "--°C");
}
static int temp_measure(widget_t *w, int h) { return 56; }
static void temp_draw(widget_t *w, cairo_t *cr, int x, int y, int h) {
  temp_priv_t *p = (temp_priv_t*)w->priv;
  widget_icon_glyph(cr, "♨", x, h, 0.9, 0.6, 0.4);
  widget_text(cr, p->txt, x + 16, h, "Sans 9", 0.8, 0.8, 0.82);
}
widget_t *w_temp_create(const char *opts) {
  temp_priv_t *p = (temp_priv_t*)calloc(1, sizeof(*p));
  snprintf(p->txt, sizeof(p->txt), "--°C");
  widget_t *w = (widget_t*)calloc(1, sizeof(*w));
  w->type = "temp"; w->priv = p;
  w->menu_open = temp_menu;
  w->measure = temp_measure; w->draw = temp_draw; w->update = temp_update;
  return w;
}

/* ---------------- disk ---------------- */

typedef struct { char txt[32]; } disk_priv_t;
static void disk_update(widget_t *w) {
  disk_priv_t *p = (disk_priv_t*)w->priv;
  struct statvfs st;
  if (statvfs("/", &st) == 0) {
    unsigned long total = st.f_blocks * st.f_frsize;
    unsigned long free = st.f_bavail * st.f_frsize;
    int used = (int)(100 * (total - free) / total);
    snprintf(p->txt, sizeof(p->txt), "SSD %d%%", used);
  }
}
static int disk_measure(widget_t *w, int h) { return 64; }
static void disk_draw(widget_t *w, cairo_t *cr, int x, int y, int h) {
  disk_priv_t *p = (disk_priv_t*)w->priv;
  widget_icon_glyph(cr, "▥", x, h, 0.5, 0.8, 0.6);
  widget_text(cr, p->txt, x + 16, h, "Sans 9", 0.8, 0.8, 0.82);
}
widget_t *w_disk_create(const char *opts) {
  disk_priv_t *p = (disk_priv_t*)calloc(1, sizeof(*p));
  snprintf(p->txt, sizeof(p->txt), "SSD --");
  widget_t *w = (widget_t*)calloc(1, sizeof(*w));
  w->type = "disk"; w->priv = p;
  w->menu_open = disk_menu;
  w->measure = disk_measure; w->draw = disk_draw; w->update = disk_update;
  return w;
}

/* ---------------- battery ---------------- */

typedef struct { char txt[32]; int lvl; bool charging; } bat_priv_t;
static void bat_update(widget_t *w) {
  bat_priv_t *p = (bat_priv_t*)w->priv;
  p->lvl = read_file_int("/sys/class/power_supply/BAT0/capacity", -1);
  char *st = read_file_str("/sys/class/power_supply/BAT0/status");
  p->charging = st && !strncmp(st, "Charging", 8);
  free(st);
  if (p->lvl < 0) snprintf(p->txt, sizeof(p->txt), "BAT ?");
  else snprintf(p->txt, sizeof(p->txt), "%s%d%%", p->charging ? "+" : "", p->lvl);
}
static int bat_measure(widget_t *w, int h) { return 64; }
static void bat_draw(widget_t *w, cairo_t *cr, int x, int y, int h) {
  bat_priv_t *p = (bat_priv_t*)w->priv;
  const char *g = p->lvl < 20 ? "▮" : (p->lvl < 50 ? "▮" : (p->lvl < 80 ? "▮" : "▮"));
  double r = p->lvl < 20 ? 0.9 : 0.5, g2 = p->lvl < 50 ? 0.8 : 0.9, b = 0.4;
  widget_icon_glyph(cr, g, x, h, r, g2, b);
  widget_text(cr, p->txt, x + 16, h, "Sans 9", 0.8, 0.8, 0.82);
}
widget_t *w_battery_create(const char *opts) {
  bat_priv_t *p = (bat_priv_t*)calloc(1, sizeof(*p));
  p->lvl = -1;
  widget_t *w = (widget_t*)calloc(1, sizeof(*w));
  w->type = "battery"; w->priv = p;
  w->menu_open = bat_menu;
  w->measure = bat_measure; w->draw = bat_draw; w->update = bat_update;
  return w;
}

/* ---------------- volume ---------------- */

typedef struct { char txt[32]; int vol; bool mute; } vol_priv_t;
static void vol_update(widget_t *w) {
  vol_priv_t *p = (vol_priv_t*)w->priv;
  char *s = read_cmd_str("pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null");
  p->vol = 0; p->mute = false;
  if (s) {
    if (strcasestr(s, "mute: yes")) p->mute = true;
    char *pc = strstr(s, "%");
    if (pc) p->vol = atoi(pc);
    free(s);
  }
  snprintf(p->txt, sizeof(p->txt), "%s%d%%", p->mute ? "M" : "", p->vol);
}
static int vol_measure(widget_t *w, int h) { return 64; }
static void vol_draw(widget_t *w, cairo_t *cr, int x, int y, int h) {
  vol_priv_t *p = (vol_priv_t*)w->priv;
  widget_icon_glyph(cr, p->mute ? "🔇" : "🔊", x, h, 0.6, 0.8, 0.9);
  widget_text(cr, p->txt, x + 18, h, "Sans 9", 0.8, 0.8, 0.82);
}
static bool vol_click(widget_t *w, int btn, int x, int y) {
  if (btn != 1) return false;
  vol_priv_t *p = (vol_priv_t*)w->priv;
  if (p->mute) system("pactl set-sink-mute @DEFAULT_SINK@ 0 &");
  else system("pactl set-sink-mute @DEFAULT_SINK@ 1 &");
  return true;
}
widget_t *w_volume_create(const char *opts) {
  vol_priv_t *p = (vol_priv_t*)calloc(1, sizeof(*p));
  widget_t *w = (widget_t*)calloc(1, sizeof(*w));
  w->type = "volume"; w->priv = p;
  w->menu_open = vol_menu;
  w->measure = vol_measure; w->draw = vol_draw; w->update = vol_update; w->click = vol_click;
  return w;
}

/* ---------------- network ---------------- */

typedef struct { char txt[64]; } net_priv_t;
static void net_update(widget_t *w) {
  net_priv_t *p = (net_priv_t*)w->priv;
  char *s = read_cmd_str("nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes' | cut -d: -f2");
  if (s && *s) snprintf(p->txt, sizeof(p->txt), "%s", s);
  else {
    char *eth = read_cmd_str("nmcli -t -f STATE dev ethernet 2>/dev/null | head -1");
    if (eth && strstr(eth, "connected")) snprintf(p->txt, sizeof(p->txt), "LAN");
    else snprintf(p->txt, sizeof(p->txt), "off");
    free(eth);
  }
  free(s);
}
static int net_measure(widget_t *w, int h) { return 92; }
static void net_draw(widget_t *w, cairo_t *cr, int x, int y, int h) {
  net_priv_t *p = (net_priv_t*)w->priv;
  widget_icon_glyph(cr, "📶", x, h, 0.5, 0.9, 0.6);
  widget_text(cr, p->txt, x + 18, h, "Sans 9", 0.8, 0.8, 0.82);
}
widget_t *w_network_create(const char *opts) {
  net_priv_t *p = (net_priv_t*)calloc(1, sizeof(*p));
  snprintf(p->txt, sizeof(p->txt), "off");
  widget_t *w = (widget_t*)calloc(1, sizeof(*w));
  w->type = "network"; w->priv = p;
  w->menu_open = net_menu;
  w->measure = net_measure; w->draw = net_draw; w->update = net_update;
  return w;
}

/* ---------------- media ---------------- */

typedef struct { char txt[96]; bool playing; } media_priv_t;
static void media_update(widget_t *w) {
  media_priv_t *p = (media_priv_t*)w->priv;
  char *artist = read_cmd_str("playerctl metadata artist 2>/dev/null");
  char *title = read_cmd_str("playerctl metadata title 2>/dev/null");
  char *st = read_cmd_str("playerctl status 2>/dev/null");
  p->playing = st && !strncmp(st, "Playing", 7);
  if ((artist && *artist) || (title && *title))
    snprintf(p->txt, sizeof(p->txt), "%s - %s", artist && *artist ? artist : "?", title && *title ? title : "");
  else snprintf(p->txt, sizeof(p->txt), "");
  free(artist); free(title); free(st);
}
static int media_measure(widget_t *w, int h) {
  media_priv_t *p = (media_priv_t*)w->priv;
  return (int)(strlen(p->txt) * 6) + 20;
}
static void media_draw(widget_t *w, cairo_t *cr, int x, int y, int h) {
  media_priv_t *p = (media_priv_t*)w->priv;
  if (!p->txt[0]) return;
  widget_icon_glyph(cr, p->playing ? "▶" : "❚❚", x, h, 0.9, 0.8, 0.4);
  widget_text(cr, p->txt, x + 18, h, "Sans 9", 0.85, 0.85, 0.88);
}
static bool media_click(widget_t *w, int btn, int x, int y) {
  if (btn != 1) return false;
  system("playerctl play-pause &");
  return true;
}
widget_t *w_media_create(const char *opts) {
  media_priv_t *p = (media_priv_t*)calloc(1, sizeof(*p));
  widget_t *w = (widget_t*)calloc(1, sizeof(*w));
  w->type = "media"; w->priv = p;
  w->menu_open = media_menu;
  w->measure = media_measure; w->draw = media_draw; w->update = media_update; w->click = media_click;
  return w;
}

/* ---------------- clock ---------------- */

typedef struct { char fmt[32]; char txt[64]; } clk_priv_t;
static void clk_update(widget_t *w) {
  clk_priv_t *p = (clk_priv_t*)w->priv;
  time_t now = time(NULL);
  strftime(p->txt, sizeof(p->txt), p->fmt, localtime(&now));
}
static int clk_measure(widget_t *w, int h) {
  clk_priv_t *p = (clk_priv_t*)w->priv;
  return (int)(strlen(p->txt) * 7) + 16;
}
static void clk_draw(widget_t *w, cairo_t *cr, int x, int y, int h) {
  clk_priv_t *p = (clk_priv_t*)w->priv;
  widget_text(cr, p->txt, x, h, "Sans 10", 0.85, 0.85, 0.85);
}
widget_t *w_clock_create(const char *opts) {
  clk_priv_t *p = (clk_priv_t*)calloc(1, sizeof(*p));
  char buf[32];
  if (opt_get(opts, "format", buf, sizeof(buf))) snprintf(p->fmt, sizeof(p->fmt), "%s", buf);
  else strcpy(p->fmt, "%H:%M");
  widget_t *w = (widget_t*)calloc(1, sizeof(*w));
  w->type = "clock"; w->priv = p;
  w->menu_open = clk_menu;
  w->measure = clk_measure; w->draw = clk_draw; w->update = clk_update;
  return w;
}

/* ---------------- power ---------------- */

typedef struct { char cmd[128]; } pwr_priv_t;
static int pwr_measure(widget_t *w, int h) { return 22; }
static void pwr_draw(widget_t *w, cairo_t *cr, int x, int y, int h) {
  widget_icon_glyph(cr, "⏻", x + 4, h, 0.9, 0.5, 0.5);
}
static bool pwr_click(widget_t *w, int btn, int x, int y) {
  if (btn != 1) return false;
  pwr_priv_t *p = (pwr_priv_t*)w->priv;
  if (p->cmd[0]) system(p->cmd);
  return true;
}
widget_t *w_power_create(const char *opts) {
  pwr_priv_t *p = (pwr_priv_t*)calloc(1, sizeof(*p));
  char buf[128];
  if (opt_get(opts, "cmd", buf, sizeof(buf))) snprintf(p->cmd, sizeof(p->cmd), "%s &", buf);
  else snprintf(p->cmd, sizeof(p->cmd), "loginctl poweroff &");
  widget_t *w = (widget_t*)calloc(1, sizeof(*w));
  w->type = "power"; w->priv = p;
  w->measure = pwr_measure; w->draw = pwr_draw; w->click = pwr_click;
  w->menu_open = pwr_menu;
  return w;
}

/* ---------------- settings (pinned, cannot be removed) ---------------- */

// host-shell callbacks (NULL if unsupported); see widget.h
static void act_reload(void *a) { (void)a; if (g_widget_reload_cb) g_widget_reload_cb(); }
static void act_restart(void *a) { (void)a; if (g_widget_restart_cb) g_widget_restart_cb(); }
static void act_quit(void *a) { (void)a; if (g_widget_quit_cb) g_widget_quit_cb(); }

static int open_menu(widget_t *w, int ax, int ay, mb_t *b);

static int set_measure(widget_t *w, int h) { (void)w; (void)h; return 22; }
static void set_draw(widget_t *w, cairo_t *cr, int x, int y, int h) {
  (void)w; (void)y;
  widget_icon_glyph(cr, "⚙", x + 4, h, 0.80, 0.80, 0.85);
}
static int set_menu(widget_t *w, int ax, int ay) {
  (void)w;
  mb_t b = {0};
  mb_add(&b, mi("Panel Settings", NULL, NULL));
  mb_sep(&b);
  {
    menu_item_t it = mi("Reload Configuration", NULL, NULL);
    it.activate = act_reload;
    mb_add(&b, it);
  }
  mb_add(&b, mi("Edit widgets.conf",
                NULL, "xdg-open ~/.config/fltk-panel/widgets.conf &"));
  mb_sep(&b);
  {
    menu_item_t it = mi("Restart Shell", NULL, NULL);
    it.activate = act_restart;
    mb_add(&b, it);
  }
  {
    menu_item_t it = mi("Quit Shell", NULL, NULL);
    it.activate = act_quit;
    mb_add(&b, it);
  }
  return open_menu(w, ax, ay, &b);
}
widget_t *w_settings_create(const char *opts) {
  (void)opts;
  widget_t *w = (widget_t*)calloc(1, sizeof(*w));
  w->type = "settings";
  w->measure = set_measure;
  w->draw = set_draw;
  w->menu_open = set_menu;
  return w;
}

/* ---------------- widget menus (popup on click) ---------------- */

static int open_menu(widget_t *w, int ax, int ay, mb_t *b) {
  struct panel_ctx *c = (struct panel_ctx*)w->ctx;
  int sw = c ? c->screen_w : 1920;
  menu_open(ax, ay, b->a, b->n, sw);
  free(b->a);
  return 1;
}

static int ws_menu(widget_t *w, int ax, int ay) {
  ws_priv_t *p = (ws_priv_t*)w->priv;
  mb_t b = {0};
  mb_add(&b, mi("Workspaces", NULL, NULL));
  mb_sep(&b);
  char copy[64]; strncpy(copy, p->labels, sizeof(copy)-1); copy[sizeof(copy)-1]=0;
  char *tok = strtok(copy, " ");
  while (tok) { if (*tok && *tok != ' ') mb_add(&b, mi(tok, NULL, NULL)); tok = strtok(NULL, " "); }
  return open_menu(w, ax, ay, &b);
}

static int tl_menu(widget_t *w, int ax, int ay) {
  struct panel_ctx *c = (struct panel_ctx*)w->ctx;
  g_menu_seat = c ? c->seat : NULL;
  mb_t b = {0};
  mb_add(&b, mi("Windows", NULL, NULL));
  mb_sep(&b);
  int n = c ? *c->count : 0;
  struct toplevel_info *t = c ? c->toplevels : NULL;
  if (n == 0) mb_add(&b, mi("(none)", NULL, NULL));
  for (int i = 0; i < n; i++) {
    const char *title = t[i].title[0] ? t[i].title : (t[i].app_id[0] ? t[i].app_id : "?");
    menu_item_t it = mi(title, t[i].focused ? "active" : NULL, NULL);
    it.activate = act_focus;
    it.arg = t[i].handle;
    mb_add(&b, it);
  }
  return open_menu(w, ax, ay, &b);
}

static int run_menu(widget_t *w, int ax, int ay) {
  mb_t b = {0};
  mb_add(&b, mi("Applications", NULL, NULL));
  mb_sep(&b);
  mb_add(&b, mi("Terminal", NULL, "foot &"));
  mb_add(&b, mi("File Manager", NULL, "pcmanfm &"));
  mb_add(&b, mi("Web Browser", NULL, "firefox &"));
  mb_add(&b, mi("Text Editor", NULL, "gedit &"));
  mb_sep(&b);
  mb_add(&b, mi("Search… (fuzzel)", NULL, "fuzzel &"));
  return open_menu(w, ax, ay, &b);
}

static int stat_menu(widget_t *w, int ax, int ay, const char *name, const char *val) {
  mb_t b = {0};
  mb_add(&b, mi(name, val, NULL));
  mb_sep(&b);
  mb_add(&b, mi("Open System Monitor", NULL, "gnome-system-monitor &"));
  return open_menu(w, ax, ay, &b);
}

static int cpu_menu(widget_t *w, int ax, int ay) {
  cpu_priv_t *p = (cpu_priv_t*)w->priv;
  return stat_menu(w, ax, ay, "CPU", p->txt);
}
static int mem_menu(widget_t *w, int ax, int ay) {
  mem_priv_t *p = (mem_priv_t*)w->priv;
  return stat_menu(w, ax, ay, "Memory", p->txt);
}
static int temp_menu(widget_t *w, int ax, int ay) {
  temp_priv_t *p = (temp_priv_t*)w->priv;
  return stat_menu(w, ax, ay, "Temperature", p->txt);
}
static int disk_menu(widget_t *w, int ax, int ay) {
  disk_priv_t *p = (disk_priv_t*)w->priv;
  return stat_menu(w, ax, ay, "Disk", p->txt);
}

static int bat_menu(widget_t *w, int ax, int ay) {
  char cap[32] = "?", status[32] = "?";
  FILE *f = fopen("/sys/class/power_supply/BAT0/capacity", "r");
  if (f) { if (fscanf(f, "%31s", cap) == 1) {} fclose(f); }
  f = fopen("/sys/class/power_supply/BAT0/status", "r");
  if (f) { if (fscanf(f, "%31s", status) == 1) {} fclose(f); }
  char detail[64]; snprintf(detail, sizeof(detail), "%s%% %s", cap, status);
  mb_t b = {0};
  mb_add(&b, mi("Battery", detail, NULL));
  mb_sep(&b);
  mb_add(&b, mi("Suspend", NULL, "systemctl suspend &"));
  mb_add(&b, mi("Reboot", NULL, "systemctl reboot &"));
  mb_add(&b, mi("Shutdown", NULL, "systemctl poweroff &"));
  return open_menu(w, ax, ay, &b);
}

static int vol_menu(widget_t *w, int ax, int ay) {
  (void)w;
  char muted[16] = "no";
  char *s = read_cmd_str("pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null");
  if (s) { if (strstr(s, "yes")) strcpy(muted, "yes"); free(s); }
  char detail[32]; snprintf(detail, sizeof(detail), "muted: %s", muted);
  mb_t b = {0};
  mb_add(&b, mi("Volume", detail, NULL));
  mb_sep(&b);
  mb_add(&b, mi("Mute / Unmute", NULL, "pactl set-sink-mute @DEFAULT_SINK@ toggle &"));
  mb_sep(&b);
  mb_add(&b, mi("0%", NULL, "pactl set-sink-volume @DEFAULT_SINK@ 0% &"));
  mb_add(&b, mi("25%", NULL, "pactl set-sink-volume @DEFAULT_SINK@ 25% &"));
  mb_add(&b, mi("50%", NULL, "pactl set-sink-volume @DEFAULT_SINK@ 50% &"));
  mb_add(&b, mi("75%", NULL, "pactl set-sink-volume @DEFAULT_SINK@ 75% &"));
  mb_add(&b, mi("100%", NULL, "pactl set-sink-volume @DEFAULT_SINK@ 100% &"));
  mb_sep(&b);
  mb_add(&b, mi("Open Mixer", NULL, "pavucontrol &"));
  return open_menu(w, ax, ay, &b);
}

static int net_menu(widget_t *w, int ax, int ay) {
  (void)w;
  mb_t b = {0};
  mb_add(&b, mi("Network", NULL, NULL));
  mb_sep(&b);
  // active connections -> disconnect
  char *active = read_cmd_str("nmcli -t -f NAME con show --active 2>/dev/null");
  if (active && *active) {
    char *line = strtok(active, "\n");
    while (line && b.n < 28) {
      char cmd[256]; snprintf(cmd, sizeof(cmd), "nmcli con down id '%s' &", line);
      char label[160]; snprintf(label, sizeof(label), "Disconnect %s", line);
      mb_add(&b, mi(label, "on", cmd));
      line = strtok(NULL, "\n");
    }
  }
  mb_sep(&b);
  // available connections -> connect
  char *avail = read_cmd_str("nmcli -t -f NAME con show 2>/dev/null");
  if (avail && *avail) {
    char *line = strtok(avail, "\n");
    while (line && b.n < 40) {
      char cmd[256]; snprintf(cmd, sizeof(cmd), "nmcli con up id '%s' &", line);
      char label[160]; snprintf(label, sizeof(label), "Connect %s", line);
      mb_add(&b, mi(label, NULL, cmd));
      line = strtok(NULL, "\n");
    }
  }
  free(active); free(avail);
  return open_menu(w, ax, ay, &b);
}

static int media_menu(widget_t *w, int ax, int ay) {
  (void)w;
  mb_t b = {0};
  mb_add(&b, mi("Media", NULL, NULL));
  mb_sep(&b);
  mb_add(&b, mi("Play / Pause", NULL, "playerctl play-pause &"));
  mb_add(&b, mi("Next", NULL, "playerctl next &"));
  mb_add(&b, mi("Previous", NULL, "playerctl previous &"));
  mb_sep(&b);
  mb_add(&b, mi("Stop", NULL, "playerctl stop &"));
  return open_menu(w, ax, ay, &b);
}

static int clk_menu(widget_t *w, int ax, int ay) {
  (void)w;
  time_t now = time(NULL);
  char date[64]; strftime(date, sizeof(date), "%A %d %B %Y", localtime(&now));
  mb_t b = {0};
  mb_add(&b, mi("Date", date, NULL));
  mb_sep(&b);
  mb_add(&b, mi("Screenshot", NULL, "grim ~/Pictures/$(date +%s).png &"));
  mb_add(&b, mi("Lock Screen", NULL, "loginctl lock-session &"));
  return open_menu(w, ax, ay, &b);
}

static int pwr_menu(widget_t *w, int ax, int ay) {
  (void)w;
  mb_t b = {0};
  mb_add(&b, mi("Power", NULL, NULL));
  mb_sep(&b);
  mb_add(&b, mi("Suspend", NULL, "systemctl suspend &"));
  mb_add(&b, mi("Reboot", NULL, "systemctl reboot &"));
  mb_add(&b, mi("Shutdown", NULL, "systemctl poweroff &"));
  mb_sep(&b);
  mb_add(&b, mi("Lock Screen", NULL, "loginctl lock-session &"));
  return open_menu(w, ax, ay, &b);
}
