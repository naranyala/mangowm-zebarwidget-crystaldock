#ifndef OCWS_AUDIO_ANALYSIS_H
#define OCWS_AUDIO_ANALYSIS_H

// ocws audio_analysis - feature extraction for OCWS audio widgets
//
// This module provides efficient extraction of audio features including:
//   - Raw PCM samples per channel (ring buffer)
//   - RMS and peak levels per channel
//   - FFT magnitude spectrum using FFTW3
//   - 4 equal frequency bands (bass, low-mid, high-mid, treble)
//   - Spectral centroid for brightness analysis
//
// Designed to work with either PulseAudio or PipeWire capture from the audio_stream module,
// this provides the underlying data for speaker visualization and other audio analysis.

#include <fftw3.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <pthread.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Configuration parameters
typedef struct {
    size_t fft_size;         // FFT window size in samples
    size_t ring_size;        // Raw buffer capacity (samples per channel)
    int sample_rate;         // Sample rate
    int channels;            // Number of channels
} audio_config_t;

// Feature extraction result
typedef struct {
    size_t ring_size;        // Capacity of raw buffer
    size_t fft_size;         // FFT window size used
    int sample_rate;         // Sample rate
    int channels;            // Number of channels

    // Raw PCM data (most recent samples at the end)
    const float* raw_l;      // Left channel data
    const float* raw_r;      // Right channel data
    size_t raw_count;        // Number of valid samples currently stored

    // Audio level measurements
    float rms_l;             // Root mean square level (0..1)
    float rms_r;             // Root mean square level (0..1)
    float peak_l;            // Peak level (0..1)
    float peak_r;            // Peak level (0..1)

    // Frequency domain
    const float* spectrum;   // Magnitude spectrum (FFT bins)
    size_t n_bins;           // Number of spectrum bins

    // Spectral analysis
    float band_lf;           // Low-frequency band (bass)
    float band_lmf;          // Low-mid frequency band
    float band_hmf;          // High-mid frequency band
    float band_hf;           // High-frequency band (treble)

    float centroid;          // Spectral centroid (brightness measure, 0..1)
    float flatness;          // Spectral flatness measure (roughness)
} audio_features_t;

// Configuration defaults for typical use
static inline audio_config_t audio_default_config(void) {
    audio_config_t c = {1024, 8192, 48000, 2};
    return c;
}
static const audio_config_t default_config = {1024, 8192, 48000, 2};

// Public API
int audio_analysis_init(const audio_config_t* config);
void audio_analysis_deinit(void);

// Process new audio samples (interleaved float buffer)
void audio_analysis_process(const float* samples, size_t n);

// Get the latest features (thread-safe)
void audio_analysis_get_features(audio_features_t* out);

// Reset internal buffers
void audio_analysis_reset(void);

// Backward-compat aliases (used by audio_stream.c)
void audio_analysis_push(const float *s, int n, int ch);
void audio_analysis_snapshot(audio_features_t *out);

#ifdef __cplusplus
}
#endif

#endif /* OCWS_AUDIO_ANALYSIS_H */
