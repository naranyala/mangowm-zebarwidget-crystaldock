#include <gtk/gtk.h>
#include <epoxy/gl.h>
#include <pulse/simple.h>
#include <pulse/error.h>
#include <math.h>
#include <pthread.h>
#include <string.h>
#include "../libocws/audio_dsp.h"

#define NUM_SAMPLES 1024

enum WaveformStyle {
    STYLE_LINE,
    STYLE_FILLED,
    STYLE_MIRRORED,
    STYLE_DOTS
};
static enum WaveformStyle current_style = STYLE_LINE;

float audio_buffer[NUM_SAMPLES];
pthread_mutex_t audio_mutex = PTHREAD_MUTEX_INITIALIZER;

// Desktop GL 3.3 Core Profile Shaders
const char *vertex_shader_source =
    "#version 330 core\n"
    "in vec2 position;\n"
    "void main() {\n"
    "    gl_Position = vec4(position, 0.0, 1.0);\n"
    "}\n";

const char *fragment_shader_source =
    "#version 330 core\n"
    "uniform vec4 color;\n"
    "out vec4 fragColor;\n"
    "void main() {\n"
    "    fragColor = color;\n"
    "}\n";

GLuint program, vao, vbo;
GLint position_attr, color_uniform;

// GTK Color to pass to shader (fallback blue)
float r = 0.537f, g = 0.706f, b = 0.980f, a = 1.0f; 

// Background color (fallback dark gray/mocha)
float bg_r = 0.117f, bg_g = 0.117f, bg_b = 0.180f, bg_a = 0.85f;

// PulseAudio Capture Thread
void *audio_capture_thread(void *arg) {
    pa_sample_spec ss = {
        .format = PA_SAMPLE_FLOAT32LE,
        .rate = 44100,
        .channels = 1
    };
    
    // Automatically get default sink monitor
    char source_name[256] = {0};
    FILE *f = popen("pactl get-default-sink", "r");
    if (f) {
        if (fgets(source_name, sizeof(source_name), f)) {
            source_name[strcspn(source_name, "\n")] = 0;
            strcat(source_name, ".monitor");
        }
        pclose(f);
    }
    
    pa_buffer_attr attr;
    attr.maxlength = (uint32_t) -1;
    attr.tlength = (uint32_t) -1;
    attr.prebuf = (uint32_t) -1;
    attr.minreq = (uint32_t) -1;
    attr.fragsize = sizeof(float) * NUM_SAMPLES; // Force extremely low latency buffer

    int error;
    pa_simple *s = pa_simple_new(NULL, "ocws-waveform-gl", PA_STREAM_RECORD, 
                                 source_name[0] ? source_name : NULL, 
                                 "Record", &ss, NULL, &attr, &error);
    if (!s) {
        g_printerr("Audio capture failed: %s\n", pa_strerror(error));
        return NULL;
    }
    
    float temp_buffer[NUM_SAMPLES];
    while (1) {
        if (pa_simple_read(s, temp_buffer, sizeof(temp_buffer), &error) < 0) {
            g_printerr("Audio read failed: %s\n", pa_strerror(error));
            break;
        }
        
        pthread_mutex_lock(&audio_mutex);
        audio_dsp_apply_hann_window(temp_buffer, NUM_SAMPLES);
        memcpy(audio_buffer, temp_buffer, sizeof(temp_buffer));
        pthread_mutex_unlock(&audio_mutex);
    }
    
    pa_simple_free(s);
    return NULL;
}

static GLuint compile_shader(GLenum type, const char *source) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    
    GLint status;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    if (status == GL_FALSE) {
        char log[512];
        glGetShaderInfoLog(shader, sizeof(log), NULL, log);
        g_printerr("Shader compile error:\n%s\n", log);
    }
    return shader;
}

static void on_realize(GtkGLArea *area, gpointer user_data) {
    gtk_gl_area_make_current(area);
    if (gtk_gl_area_get_error(area) != NULL) return;
    
    GLuint vs = compile_shader(GL_VERTEX_SHADER, vertex_shader_source);
    GLuint fs = compile_shader(GL_FRAGMENT_SHADER, fragment_shader_source);
    
    program = glCreateProgram();
    glAttachShader(program, vs);
    glAttachShader(program, fs);
    glLinkProgram(program);
    
    position_attr = glGetAttribLocation(program, "position");
    color_uniform = glGetUniformLocation(program, "color");
    
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    
    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    
    glEnableVertexAttribArray(position_attr);
    glVertexAttribPointer(position_attr, 2, GL_FLOAT, GL_FALSE, 0, NULL);
    
    glBindVertexArray(0);
}

static void on_unrealize(GtkGLArea *area, gpointer user_data) {
    gtk_gl_area_make_current(area);
    glDeleteBuffers(1, &vbo);
    glDeleteVertexArrays(1, &vao);
    glDeleteProgram(program);
}

static gboolean on_render(GtkGLArea *area, GdkGLContext *context, gpointer user_data) {
    glClearColor(bg_r, bg_g, bg_b, bg_a);
    glClear(GL_COLOR_BUFFER_BIT);
    
    glUseProgram(program);
    glUniform4f(color_uniform, r, g, b, 1.0f);
    glBindVertexArray(vao);
    
    if (current_style == STYLE_LINE) {
        float vertices[NUM_SAMPLES * 2];
        pthread_mutex_lock(&audio_mutex);
        for (int i = 0; i < NUM_SAMPLES; i++) {
            vertices[i*2] = -1.0f + (2.0f * i) / (NUM_SAMPLES - 1);
            vertices[i*2 + 1] = audio_buffer[i] * 1.5f;
        }
        pthread_mutex_unlock(&audio_mutex);
        
        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);
        glLineWidth(2.0f);
        glDrawArrays(GL_LINE_STRIP, 0, NUM_SAMPLES);
        
    } else if (current_style == STYLE_DOTS) {
        float vertices[NUM_SAMPLES * 2];
        pthread_mutex_lock(&audio_mutex);
        for (int i = 0; i < NUM_SAMPLES; i++) {
            vertices[i*2] = -1.0f + (2.0f * i) / (NUM_SAMPLES - 1);
            vertices[i*2 + 1] = audio_buffer[i] * 1.5f;
        }
        pthread_mutex_unlock(&audio_mutex);
        
        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);
        glPointSize(3.0f);
        glDrawArrays(GL_POINTS, 0, NUM_SAMPLES);
        
    } else if (current_style == STYLE_FILLED) {
        float vertices[NUM_SAMPLES * 4];
        pthread_mutex_lock(&audio_mutex);
        for (int i = 0; i < NUM_SAMPLES; i++) {
            float x = -1.0f + (2.0f * i) / (NUM_SAMPLES - 1);
            vertices[i*4] = x;
            vertices[i*4+1] = -1.0f; // Bottom anchor
            vertices[i*4+2] = x;
            vertices[i*4+3] = audio_buffer[i] * 1.5f; // Peak
        }
        pthread_mutex_unlock(&audio_mutex);
        
        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, NUM_SAMPLES * 2);
        
    } else if (current_style == STYLE_MIRRORED) {
        float vertices[NUM_SAMPLES * 4];
        pthread_mutex_lock(&audio_mutex);
        for (int i = 0; i < NUM_SAMPLES; i++) {
            float x = -1.0f + (2.0f * i) / (NUM_SAMPLES - 1);
            float y = audio_buffer[i] * 1.5f;
            vertices[i*4] = x;
            vertices[i*4+1] = y; 
            vertices[i*4+2] = x;
            vertices[i*4+3] = -y; // Mirrored on Y-axis
        }
        pthread_mutex_unlock(&audio_mutex);
        
        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);
        glLineWidth(2.0f);
        glDrawArrays(GL_LINES, 0, NUM_SAMPLES * 2);
    }
    
    glBindVertexArray(0);
    glUseProgram(0);
    
    return TRUE;
}

static gboolean on_tick(GtkWidget *widget, GdkFrameClock *frame_clock, gpointer user_data) {
    gtk_widget_queue_draw(widget);
    return G_SOURCE_CONTINUE;
}

// Function to dynamically adopt the OCWS adaptive color palette
void load_adaptive_color() {
    char *path = g_build_filename(g_get_home_dir(), ".config", "ocws", "css", "theme.css", NULL);
    gchar *content = NULL;
    if (g_file_get_contents(path, &content, NULL, NULL)) {
        // Extract the accent color defined in the engine
        char *ptr = strstr(content, "@define-color accent #");
        if (ptr) {
            ptr += 22;
            int r_int = 0, g_int = 0, b_int = 0;
            if (sscanf(ptr, "%02x%02x%02x", &r_int, &g_int, &b_int) == 3) {
                r = r_int / 255.0f;
                g = g_int / 255.0f;
                b = b_int / 255.0f;
            }
        }
        
        // Extract the background color
        char *bg_ptr = strstr(content, "@define-color theme_bg_color #");
        if (bg_ptr) {
            bg_ptr += 30;
            int br = 0, bg = 0, bb = 0;
            if (sscanf(bg_ptr, "%02x%02x%02x", &br, &bg, &bb) == 3) {
                bg_r = br / 255.0f;
                bg_g = bg / 255.0f;
                bg_b = bb / 255.0f;
            }
        }
        
        // Extract the dynamic widget alpha
        char *alpha_ptr = strstr(content, "@define-color widget_alpha ");
        if (alpha_ptr) {
            alpha_ptr += 27;
            float alpha_val = 0.85f;
            if (sscanf(alpha_ptr, "%f", &alpha_val) == 1) {
                bg_a = alpha_val;
            }
        }
        g_free(content);
    }
    g_free(path);
}

static void activate(GtkApplication *app, gpointer user_data) {
    GtkWidget *window = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(window), "OCWS Waveform GL");
    gtk_window_set_default_size(GTK_WINDOW(window), 400, 100);
    
    // Disable window decorations (for placing on desktop/panel)
    gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
    gtk_window_set_keep_below(GTK_WINDOW(window), TRUE);
    
    // Enable transparent window background
    GdkScreen *screen = gtk_widget_get_screen(window);
    GdkVisual *visual = gdk_screen_get_rgba_visual(screen);
    if (visual) {
        gtk_widget_set_visual(window, visual);
    }
    gtk_widget_set_app_paintable(window, TRUE);
    
    GtkWidget *gl_area = gtk_gl_area_new();
    gtk_gl_area_set_has_alpha(GTK_GL_AREA(gl_area), TRUE);
    
    // Force Core profile
    gtk_gl_area_set_required_version(GTK_GL_AREA(gl_area), 3, 3);
    
    g_signal_connect(gl_area, "realize", G_CALLBACK(on_realize), NULL);
    g_signal_connect(gl_area, "unrealize", G_CALLBACK(on_unrealize), NULL);
    g_signal_connect(gl_area, "render", G_CALLBACK(on_render), NULL);
    
    gtk_container_add(GTK_CONTAINER(window), gl_area);
    gtk_widget_add_tick_callback(gl_area, on_tick, NULL, NULL);
    
    gtk_widget_show_all(window);
    
    // Launch audio capture in a background thread
    pthread_t thread;
    pthread_create(&thread, NULL, audio_capture_thread, NULL);
}

int main(int argc, char **argv) {
    // Parse style argument
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--style=filled") == 0) current_style = STYLE_FILLED;
        else if (strcmp(argv[i], "--style=mirrored") == 0) current_style = STYLE_MIRRORED;
        else if (strcmp(argv[i], "--style=dots") == 0) current_style = STYLE_DOTS;
        else if (strcmp(argv[i], "--style=line") == 0) current_style = STYLE_LINE;
    }

    // Hide arguments from GTK to prevent parsing errors
    int fake_argc = 1;
    char *fake_argv[] = { argv[0], NULL };

    load_adaptive_color();
    
    GtkApplication *app = gtk_application_new("org.ocws.waveform_gl", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(app), fake_argc, fake_argv);
    g_object_unref(app);
    
    return status;
}
