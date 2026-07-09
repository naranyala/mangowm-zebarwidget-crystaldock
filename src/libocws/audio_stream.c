#include "audio_stream.h"
#include "audio_analysis.h"
#include <pulse/pulseaudio.h>
#include <pulse/simple.h>
#include <pthread.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <unistd.h>
#include <glib.h>

static volatile int g_running = 0;
static pa_threaded_mainloop *g_ml = NULL;
static pa_context *g_ctx = NULL;
static pa_simple *g_mon = NULL;
static char g_monitor[256];
static char g_active[256];
static float g_lvlL = 0.0f, g_lvlR = 0.0f;
static int g_monitor_ready = 0;
static pthread_mutex_t g_mtx = PTHREAD_MUTEX_INITIALIZER;

static void set_active(const char *name) {
    pthread_mutex_lock(&g_mtx);
    snprintf(g_active, sizeof(g_active), "%s", name ? name : "");
    pthread_mutex_unlock(&g_mtx);
}

static int g_seen = 0;
static void sink_input_cb(pa_context *c, const pa_sink_input_info *i,
                          int eol, void *u) {
    (void)c; (void)u;
    if (eol) {
        if (!g_seen) set_active("");
        return;
    }
    if (i->corked) return;
    g_seen = 1;
    const char *media = pa_proplist_gets(i->proplist, PA_PROP_MEDIA_NAME);
    const char *app = pa_proplist_gets(i->proplist, PA_PROP_APPLICATION_NAME);
    set_active(media && *media ? media : (app ? app : ""));
}

static void scan_streams(pa_context *c) {
    g_seen = 0;
    pa_context_get_sink_input_info_list(c, sink_input_cb, NULL);
}

static void sink_info_cb(pa_context *c, const pa_sink_info *i,
                          int eol, void *u) {
    (void)c; (void)u;
    if (eol || !i) return;
    snprintf(g_monitor, sizeof(g_monitor), "%s.monitor", i->name);
    g_monitor_ready = 1;
    pa_threaded_mainloop_signal(g_ml, 0);
}

static void server_info_cb(pa_context *c, const pa_server_info *i, void *u) {
    (void)u;
    if (!i) return;
    pa_context_get_sink_info_by_name(c, i->default_sink_name, sink_info_cb, NULL);
}

static void subscribe_cb(pa_context *c, pa_subscription_event_type_t t,
                          uint32_t idx, void *u) {
    (void)t; (void)idx; (void)u;
    scan_streams(c);
}

static void state_cb(pa_context *c, void *u) {
    (void)u;
    if (pa_context_get_state(c) != PA_CONTEXT_READY) return;
    pa_context_get_server_info(c, server_info_cb, NULL);
    scan_streams(c);
    pa_context_subscribe(c, PA_SUBSCRIPTION_MASK_SINK_INPUT, NULL, NULL);
}

// capture thread: reads from monitor source via PulseAudio simple API
static void *capture_thread(void *arg) {
    (void)arg;
    pa_sample_spec ss = { .format = PA_SAMPLE_FLOAT32LE, .rate = 48000, .channels = 2 };
    int error;
    while (g_running) {
        if (g_monitor[0]) {
            pa_simple *s = pa_simple_new(NULL, "ocws-speaker", PA_STREAM_RECORD,
                                         g_monitor, "monitor", &ss, NULL, NULL, &error);
            if (s) {
                if (g_mon) pa_simple_free(g_mon);
                g_mon = s;
                break;
            }
        }
        usleep(500000);
    }
    float buf[4096];
    while (g_running && g_mon) {
        if (pa_simple_read(g_mon, buf, sizeof(buf), &error) < 0) {
            g_printerr("ocws-speaker: read error: %s\n", pa_strerror(error));
            break;
        }
        double sL = 0, sR = 0;
        uint32_t c = 0;
        for (uint32_t i = 0; i + 1 < 4096; i += 2) {
            float l = buf[i], r = buf[i+1];
            sL += (double)l * l;
            sR += (double)r * r;
            c++;
        }
        pthread_mutex_lock(&g_mtx);
        g_lvlL = c ? (float)sqrt(sL / c) : 0.0f;
        g_lvlR = c ? (float)sqrt(sR / c) : 0.0f;
        pthread_mutex_unlock(&g_mtx);
        audio_analysis_process(buf, 4096);
    }
    return NULL;
}

int audio_stream_init(void) {
    g_running = 1;
    g_ml = pa_threaded_mainloop_new();
    if (!g_ml) return -1;
    pa_mainloop_api *api = pa_threaded_mainloop_get_api(g_ml);
    g_ctx = pa_context_new(api, "ocws-speaker");
    if (!g_ctx) { pa_threaded_mainloop_free(g_ml); g_ml = NULL; return -1; }
    pa_context_set_state_callback(g_ctx, state_cb, NULL);
    pa_context_set_subscribe_callback(g_ctx, subscribe_cb, NULL);
    pa_context_connect(g_ctx, NULL, 0, NULL);
    pa_threaded_mainloop_start(g_ml);

    pa_threaded_mainloop_lock(g_ml);
    while (!g_monitor_ready &&
           pa_context_get_state(g_ctx) != PA_CONTEXT_FAILED &&
           pa_context_get_state(g_ctx) != PA_CONTEXT_TERMINATED)
        pa_threaded_mainloop_wait(g_ml);
    pa_threaded_mainloop_unlock(g_ml);

    if (audio_analysis_init(&((audio_config_t){.fft_size=1024, .ring_size=8192, .sample_rate=48000, .channels=2})) != 0)
        g_printerr("ocws-speaker: audio_analysis init failed.\n");

    pthread_t tid;
    pthread_create(&tid, NULL, capture_thread, NULL);
    pthread_detach(tid);

    return g_monitor_ready ? 0 : -1;
}

void audio_stream_deinit(void) {
    g_running = 0;
    if (g_mon) { pa_simple_free(g_mon); g_mon = NULL; }
    audio_analysis_deinit();
    if (g_ctx) { pa_context_disconnect(g_ctx); pa_context_unref(g_ctx); g_ctx = NULL; }
    if (g_ml) { pa_threaded_mainloop_stop(g_ml); pa_threaded_mainloop_free(g_ml); g_ml = NULL; }
}

const char *audio_stream_active(void) {
    static char buf[256];
    pthread_mutex_lock(&g_mtx);
    snprintf(buf, sizeof(buf), "%s", g_active);
    pthread_mutex_unlock(&g_mtx);
    return buf;
}

void audio_stream_levels(float *l, float *r) {
    pthread_mutex_lock(&g_mtx);
    *l = g_lvlL;
    *r = g_lvlR;
    pthread_mutex_unlock(&g_mtx);
}

void audio_stream_snapshot(audio_features_t *out) {
    audio_analysis_get_features(out);
}
