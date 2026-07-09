// audio_analysis — audio feature extraction using FFTW3
// Implements the public API declared in audio_analysis.h.

#include "audio_analysis.h"
#include <fftw3.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <pthread.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif
#define AA_NBANDS 4

static int g_ready = 0;
static int g_rate = 48000, g_ch = 2, g_ring = 8192, g_fft = 1024, g_bins = 512;
static float *g_ring_l = NULL, *g_ring_r = NULL;
static int g_wpos = 0, g_count = 0;
static double *g_fft_in = NULL;
static fftw_complex *g_fft_out = NULL;
static fftw_plan g_plan = NULL;
static float *g_spec = NULL;
static float g_rms_l = 0, g_rms_r = 0, g_peak_l = 0, g_peak_r = 0;
static float g_bands[AA_NBANDS];
static float g_centroid = 0;
static pthread_mutex_t g_mtx = PTHREAD_MUTEX_INITIALIZER;

int audio_analysis_init(const audio_config_t *cfg) {
    if (g_ready) return 0;
    if (!cfg) cfg = &default_config;
    g_fft  = (int)cfg->fft_size;
    g_ring = (int)cfg->ring_size;
    g_rate = cfg->sample_rate;
    g_ch   = cfg->channels;
    if (g_fft < 64)  g_fft = 1024;
    if (g_ring < 64) g_ring = 8192;
    if (g_rate < 1)  g_rate = 48000;
    if (g_ch < 1)    g_ch = 2;
    g_bins = g_fft / 2;

    g_ring_l = calloc((size_t)g_ring, sizeof(float));
    g_ring_r = calloc((size_t)g_ring, sizeof(float));
    g_fft_in  = fftw_alloc_real((size_t)g_fft);
    g_fft_out = fftw_alloc_complex((size_t)(g_bins + 1));
    g_spec    = calloc((size_t)g_bins, sizeof(float));
    if (!g_ring_l || !g_ring_r || !g_fft_in || !g_fft_out || !g_spec) {
        audio_analysis_deinit();
        return -1;
    }
    g_plan = fftw_plan_dft_r2c_1d(g_fft, g_fft_in, g_fft_out, FFTW_ESTIMATE);
    if (!g_plan) { audio_analysis_deinit(); return -1; }

    g_ready = 1;
    return 0;
}

void audio_analysis_process(const float *s, size_t n) {
    if (!g_ready || !s || n == 0) return;
    pthread_mutex_lock(&g_mtx);

    double sl = 0, sr = 0, pl = 0, pr = 0;
    size_t c = 0;
    for (size_t i = 0; i + 1 < n; i += (size_t)g_ch) {
        float l = s[i];
        float r = g_ch > 1 ? s[i + 1] : s[i];
        g_ring_l[g_wpos] = l;
        g_ring_r[g_wpos] = r;
        g_wpos = (g_wpos + 1) % g_ring;
        if (g_count < g_ring) g_count++;
        sl += (double)l * l;
        sr += (double)r * r;
        double al = fabs((double)l);
        double ar = fabs((double)r);
        if (al > pl) pl = al;
        if (ar > pr) pr = ar;
        c++;
    }
    g_rms_l  = c > 0 ? (float)sqrt(sl / (double)c) : 0;
    g_rms_r  = c > 0 ? (float)sqrt(sr / (double)c) : 0;
    g_peak_l = (float)pl;
    g_peak_r = (float)pr;

    int take = g_count < g_fft ? g_count : g_fft;
    int start = (g_wpos - take + g_ring) % g_ring;
    for (int k = 0; k < g_fft; k++) {
        int idx = (start + k) % g_ring;
        double mono = (g_ring_l[idx] + g_ring_r[idx]) * 0.5;
        double w = 0.5 * (1.0 - cos(2.0 * M_PI * (double)k / (double)(g_fft - 1)));
        g_fft_in[k] = mono * w;
    }
    fftw_execute(g_plan);

    double sum = 0, wsum = 0;
    for (int k = 0; k < g_bins; k++) {
        double re = g_fft_out[k][0];
        double im = g_fft_out[k][1];
        float mag = (float)sqrt(re * re + im * im) / (float)g_fft;
        g_spec[k] = mag;
        sum  += (double)mag;
        wsum += (double)k * (double)mag;
    }
    for (int b = 0; b < AA_NBANDS; b++) {
        int a = (b * g_bins) / AA_NBANDS;
        int z = ((b + 1) * g_bins) / AA_NBANDS;
        double acc = 0;
        for (int k = a; k < z; k++) acc += (double)g_spec[k];
        g_bands[b] = (float)(z > a ? acc / (double)(z - a) : 0);
    }
    g_centroid = sum > 0 ? (float)(wsum / sum) / (float)g_bins : 0;

    pthread_mutex_unlock(&g_mtx);
}

void audio_analysis_get_features(audio_features_t *out) {
    if (!out) return;
    pthread_mutex_lock(&g_mtx);
    out->ring_size   = (size_t)g_ring;
    out->fft_size    = (size_t)g_fft;
    out->sample_rate = g_rate;
    out->channels    = g_ch;
    out->raw_l       = g_ring_l;
    out->raw_r       = g_ring_r;
    out->raw_count   = (size_t)g_count;
    out->rms_l       = g_rms_l;
    out->rms_r       = g_rms_r;
    out->peak_l      = g_peak_l;
    out->peak_r      = g_peak_r;
    out->spectrum    = g_spec;
    out->n_bins      = (size_t)g_bins;
    out->band_lf     = g_bands[0];
    out->band_lmf    = g_bands[1];
    out->band_hmf    = g_bands[2];
    out->band_hf     = g_bands[3];
    out->centroid    = g_centroid;
    out->flatness    = 0;
    pthread_mutex_unlock(&g_mtx);
}

void audio_analysis_reset(void) {
    pthread_mutex_lock(&g_mtx);
    if (g_ring_l) memset(g_ring_l, 0, (size_t)g_ring * sizeof(float));
    if (g_ring_r) memset(g_ring_r, 0, (size_t)g_ring * sizeof(float));
    if (g_spec)   memset(g_spec, 0, (size_t)g_bins * sizeof(float));
    g_wpos = g_count = 0;
    g_rms_l = g_rms_r = g_peak_l = g_peak_r = 0;
    memset(g_bands, 0, sizeof(g_bands));
    g_centroid = 0;
    pthread_mutex_unlock(&g_mtx);
}

void audio_analysis_deinit(void) {
    if (g_plan) { fftw_destroy_plan(g_plan); g_plan = NULL; }
    if (g_fft_in) { fftw_free(g_fft_in); g_fft_in = NULL; }
    if (g_fft_out) { fftw_free(g_fft_out); g_fft_out = NULL; }
    free(g_ring_l); g_ring_l = NULL;
    free(g_ring_r); g_ring_r = NULL;
    free(g_spec);   g_spec = NULL;
    g_ready = 0;
}

// backward compat aliases for audio_stream.c
void audio_analysis_push(const float *s, int n, int ch) {
    (void)ch;
    audio_analysis_process(s, (size_t)n);
}

void audio_analysis_snapshot(audio_features_t *o) {
    audio_analysis_get_features(o);
}
