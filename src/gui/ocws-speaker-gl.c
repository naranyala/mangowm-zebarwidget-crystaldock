// ocws-speaker-gl: OpenGL ES speaker visual widget for OCWS
//
// A GTK4 window embedding a GtkGLArea running a real OpenGL ES 2.0 context.
// Audio is provided by the ocws audio_stream module, which captures the
// default sink's monitor (whatever the system is playing) and reports the
// active playback stream. Left/right RMS levels pulse two speaker visuals.
//
// Build: see build.zig (ocws-speaker-gl target). Run: ocws-speaker-gl

#include <gtk/gtk.h>
#include <GLES2/gl2.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
// ponytail: relative include avoids pulling in src/libocws/string.h
// (which would shadow the system <string.h> when -Isrc/libocws is set).
#include "../libocws/audio_stream.h"

// ---- Audio state ---------------------------------------------------------
static float g_rmsL = 0.0f;
static float g_rmsR = 0.0f;
static GtkWidget *g_window = NULL;
// ---- Shaders -----------------------------------------------------------
// Same speaker shader body, compiled as GLSL ES (GLES) or desktop GL
// depending on the context GTK actually gives us, so it never silently
// fails to compile on the wrong profile.
#define FRAG_BODY \
    "uniform vec2  u_res;\n" \
    "uniform float u_time;\n" \
    "uniform float u_levelL;\n" \
    "uniform float u_levelR;\n" \
    "vec3 speaker(vec2 p, vec2 c, float R, float lvl, float t) {\n" \
    "    vec2 d = p - c;\n" \
    "    float r = length(d);\n" \
    "    vec3 col = vec3(0.0);\n" \
    "    vec3 tint = mix(vec3(0.15,0.5,1.0), vec3(1.0,0.35,0.45),\n" \
    "                    0.5 + 0.5*sin(t*2.0));\n" \
    "    float ringR = R*0.95;\n" \
    "    col += smoothstep(0.05*R, 0.0, abs(r-ringR)) * tint * (0.4+lvl);\n" \
    "    float coneR = R*(0.25 + 0.55*lvl);\n" \
    "    col += smoothstep(0.03*R, 0.0, abs(r-coneR)) * vec3(0.95,0.95,1.0) * (0.5+lvl);\n" \
    "    col += smoothstep(R*0.13, R*0.10, r) * vec3(1.0);\n" \
    "    float rip = 0.0;\n" \
    "    for (int i=0;i<3;i++) {\n" \
    "        float ph = fract(t*0.6 + float(i)*0.33);\n" \
    "        float rr = R*(0.4 + ph*(0.8 + lvl*1.6));\n" \
    "        rip += smoothstep(0.035*R, 0.0, abs(r-rr)) * (1.0-ph) * 0.6;\n" \
    "    }\n" \
    "    col += rip * tint * (0.3+lvl);\n" \
    "    return col;\n" \
    "}\n" \
    "void main() {\n" \
    "    vec2 p = gl_FragCoord.xy;\n" \
    "    vec2 res = u_res;\n" \
    "    vec3 bg = mix(vec3(0.04,0.05,0.09), vec3(0.01,0.02,0.04), p.y/res.y);\n" \
    "    vec3 col = bg;\n" \
    "    float R = min(res.x, res.y) * 0.18;\n" \
    "    float cy = res.y * 0.5;\n" \
    "    col += speaker(p, vec2(res.x*0.27, cy), R, u_levelL, u_time);\n" \
    "    col += speaker(p, vec2(res.x*0.73, cy), R, u_levelR, u_time + 1.7);\n" \
    "    gl_FragColor = vec4(col, 1.0);\n" \
    "}\n"

static const char *VERT_SRC =
    "attribute vec2 a_pos;\n"
    "void main() { gl_Position = vec4(a_pos, 0.0, 1.0); }\n";

static const char *FRAG_ES = "precision mediump float;\n" FRAG_BODY;
static const char *FRAG_GL = FRAG_BODY;

static GLuint g_program = 0;
static GLuint g_vbo = 0;
static GLint g_u_res = -1, g_u_time = -1, g_u_levelL = -1, g_u_levelR = -1;

static GLuint compile(GLenum type, const char *src) {
    GLuint sh = glCreateShader(type);
    glShaderSource(sh, 1, &src, NULL);
    glCompileShader(sh);
    GLint ok;
    glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetShaderInfoLog(sh, sizeof(log), NULL, log);
        g_printerr("ocws-speaker-gl: shader compile error: %s\n", log);
    }
    return sh;
}

static void build_program(int is_es) {
    const char *frag = is_es ? FRAG_ES : FRAG_GL;
    GLuint vs = compile(GL_VERTEX_SHADER, VERT_SRC);
    GLuint fs = compile(GL_FRAGMENT_SHADER, frag);
    g_program = glCreateProgram();
    glAttachShader(g_program, vs);
    glAttachShader(g_program, fs);
    glLinkProgram(g_program);
    glDeleteShader(vs);
    glDeleteShader(fs);

    GLint linked;
    glGetProgramiv(g_program, GL_LINK_STATUS, &linked);
    if (!linked) {
        char log[512];
        glGetProgramInfoLog(g_program, sizeof(log), NULL, log);
        g_printerr("ocws-speaker-gl: program link error: %s\n", log);
        glDeleteProgram(g_program);
        g_program = 0;
        return;
    }

    static const float quad[8] = { -1,-1, 1,-1, -1,1, 1,1 };
    glGenBuffers(1, &g_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, g_vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);

    g_u_res    = glGetUniformLocation(g_program, "u_res");
    g_u_time   = glGetUniformLocation(g_program, "u_time");
    g_u_levelL = glGetUniformLocation(g_program, "u_levelL");
    g_u_levelR = glGetUniformLocation(g_program, "u_levelR");
}

// ---- GTK GLArea callbacks ------------------------------------------------
static void on_realize(GtkGLArea *area, gpointer data) {
    (void)data;
    gtk_gl_area_make_current(area);
    if (gtk_gl_area_get_error(area)) {
        g_printerr("ocws-speaker-gl: failed to create GL context: %s\n",
            gtk_gl_area_get_error(area)->message);
        return;
    }
    const char *ver = (const char *)glGetString(GL_VERSION);
    int is_es = ver && strstr(ver, "OpenGL ES") != NULL;
    g_print("ocws-speaker-gl: GL context: %s (using %s shaders)\n",
        ver ? ver : "?", is_es ? "OpenGL ES" : "desktop GL");
    build_program(is_es);
    if (!g_program)
        g_printerr("ocws-speaker-gl: shader program unavailable; showing fallback.\n");
}

static void on_unrealize(GtkGLArea *area, gpointer data) {
    (void)data;
    gtk_gl_area_make_current(area);
    if (g_program) { glDeleteProgram(g_program); g_program = 0; }
    if (g_vbo) { glDeleteBuffers(1, &g_vbo); g_vbo = 0; }
}

static float smooth(float prev, float target, float k) {
    return prev + (target - prev) * k;
}

static gboolean on_render(GtkGLArea *area, GdkGLContext *ctx) {
    (void)ctx;
    int w = gtk_widget_get_width(GTK_WIDGET(area));
    int h = gtk_widget_get_height(GTK_WIDGET(area));
    glViewport(0, 0, w, h);
    glClearColor(0.01f, 0.02f, 0.04f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    audio_stream_levels(&g_rmsL, &g_rmsR);
    float rmsL = g_rmsL, rmsR = g_rmsR;

    // RMS -> 0..1, with a gentle idle animation when silent.
    static float lvlL = 0, lvlR = 0;
    float t = (float)g_get_monotonic_time() / 1e6f;
    float aL = fminf(1.0f, rmsL * 4.0f);
    float aR = fminf(1.0f, rmsR * 4.0f);
    float idle = 0.12f * (0.5f + 0.5f * sinf(t * 1.5f));
    if (aL < idle) aL = idle;
    if (aR < idle) aR = idle;
    lvlL = smooth(lvlL, aL, 0.2f);
    lvlR = smooth(lvlR, aR, 0.2f);

    // Reflect the active playback stream in the window title.
    static char last_active[256];
    const char *active = audio_stream_active();
    if (strcmp(active, last_active) != 0) {
        strncpy(last_active, active, sizeof(last_active) - 1);
        char title[300];
        snprintf(title, sizeof(title), "OCWS Speaker GL%s%s",
            *active ? " — " : "", active);
        gtk_window_set_title(GTK_WINDOW(g_window), title);
    }

    // Fallback: if the shader program is unavailable, paint a pulsing
    // colour so the widget is never a silent black void.
    if (!g_program || g_u_res < 0) {
        float k = 0.3f + 0.3f * sinf(t * 2.0f);
        glClearColor(k * lvlL, 0.05f, k * lvlR + 0.1f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        return FALSE;
    }

    glUseProgram(g_program);
    glBindBuffer(GL_ARRAY_BUFFER, g_vbo);
    GLint loc = glGetAttribLocation(g_program, "a_pos");
    glEnableVertexAttribArray(loc);
    glVertexAttribPointer(loc, 2, GL_FLOAT, GL_FALSE, 0, 0);

    glUniform2f(g_u_res, (float)w, (float)h);
    glUniform1f(g_u_time, t);
    glUniform1f(g_u_levelL, lvlL);
    glUniform1f(g_u_levelR, lvlR);

    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glDisableVertexAttribArray(loc);
    return FALSE;
}

static void activate(GtkApplication *app, gpointer data) {
    (void)data;
    g_print("ocws-speaker-gl: window activating...\n");
    GtkWidget *window = gtk_application_window_new(app);
    g_window = window;
    gtk_window_set_title(GTK_WINDOW(window), "OCWS Speaker GL");
    gtk_window_set_default_size(GTK_WINDOW(window), 640, 360);

    GtkWidget *header = gtk_header_bar_new();
    gtk_header_bar_set_show_title_buttons(GTK_HEADER_BAR(header), TRUE);
    gtk_window_set_titlebar(GTK_WINDOW(window), header);

    GtkWidget *area = gtk_gl_area_new();
    // Prefer OpenGL ES; fall back to desktop GL so it always renders.
    gtk_gl_area_set_allowed_apis(GTK_GL_AREA(area),
        GDK_GL_API_GLES | GDK_GL_API_GL);
    gtk_gl_area_set_auto_render(GTK_GL_AREA(area), TRUE);
    g_signal_connect(area, "realize", G_CALLBACK(on_realize), NULL);
    g_signal_connect(area, "unrealize", G_CALLBACK(on_unrealize), NULL);
    g_signal_connect(area, "render", G_CALLBACK(on_render), NULL);

    gtk_window_set_child(GTK_WINDOW(window), area);
    gtk_window_present(GTK_WINDOW(window));
}

int main(int argc, char **argv) {
    // Prefer the Wayland backend so GTK can obtain an EGL/OpenGL ES
    // context (labwc/wlroots are GLES compositors). Only override if the
    // user has not explicitly chosen a backend.
    if (getenv("WAYLAND_DISPLAY") && !getenv("GDK_BACKEND"))
        setenv("GDK_BACKEND", "wayland", 1);

    if (audio_stream_init() != 0)
        g_printerr("ocws-speaker-gl: audio module failed to init; running on idle animation.\n");

    GtkApplication *app = gtk_application_new("org.ocws.speakergl", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);

    audio_stream_deinit();
    return status;
}
