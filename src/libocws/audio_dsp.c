#include "audio_dsp.h"
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define MAX_FFT_SIZE 4096

// Thread-local scratch buffers to avoid malloc/free in high-speed audio loops
static _Thread_local float real_buf[MAX_FFT_SIZE];
static _Thread_local float imag_buf[MAX_FFT_SIZE];

void audio_dsp_apply_hann_window(float *buffer, int n) {
    for (int i = 0; i < n; i++) {
        float multiplier = 0.5f * (1.0f - cosf(2.0f * M_PI * i / (n - 1)));
        buffer[i] *= multiplier;
    }
}

float audio_dsp_rms(const float *buffer, int n) {
    if (n <= 0) return 0.0f;
    float sum = 0.0f;
    for (int i = 0; i < n; i++) {
        sum += buffer[i] * buffer[i];
    }
    return sqrtf(sum / n);
}

float audio_dsp_peak(const float *buffer, int n) {
    float peak = 0.0f;
    for (int i = 0; i < n; i++) {
        float val = fabsf(buffer[i]);
        if (val > peak) peak = val;
    }
    return peak;
}

void audio_dsp_magnitudes_to_db(float *magnitudes, int count) {
    for (int i = 0; i < count; i++) {
        if (magnitudes[i] < 1e-6f) {
            magnitudes[i] = -120.0f; // Noise floor
        } else {
            magnitudes[i] = 20.0f * log10f(magnitudes[i]);
        }
    }
}

void audio_dsp_fft(const float *in, float *magnitudes, int n) {
    // Basic validations: must be non-zero, power of two, and within scratch limits
    if (n <= 0 || n > MAX_FFT_SIZE || (n & (n - 1)) != 0) return;

    // Bit reversal permutation
    int j = 0;
    for (int i = 0; i < n; i++) {
        real_buf[i] = in[j];
        imag_buf[i] = 0.0f;
        
        int m = n / 2;
        while (m >= 1 && j >= m) {
            j -= m;
            m /= 2;
        }
        j += m;
    }

    // Radix-2 Cooley-Tukey algorithm
    for (int step = 1; step < n; step *= 2) {
        float theta = -M_PI / step;
        float wtemp = sinf(0.5f * theta);
        float wpr = -2.0f * wtemp * wtemp;
        float wpi = sinf(theta);
        float wr = 1.0f;
        float wi = 0.0f;
        
        for (int m = 0; m < step; m++) {
            for (int i = m; i < n; i += step * 2) {
                int j_idx = i + step;
                float treal = wr * real_buf[j_idx] - wi * imag_buf[j_idx];
                float timag = wr * imag_buf[j_idx] + wi * real_buf[j_idx];
                real_buf[j_idx] = real_buf[i] - treal;
                imag_buf[j_idx] = imag_buf[i] - timag;
                real_buf[i] += treal;
                imag_buf[i] += timag;
            }
            wtemp = wr;
            wr = wr * wpr - wi * wpi + wr;
            wi = wi * wpr + wtemp * wpi + wi;
        }
    }

    // Calculate normalized magnitudes (only first half due to Nyquist symmetry)
    for (int i = 0; i < n / 2; i++) {
        magnitudes[i] = sqrtf(real_buf[i] * real_buf[i] + imag_buf[i] * imag_buf[i]);
        // Normalize by N/2
        magnitudes[i] /= (n / 2.0f);
    }
}

void audio_dsp_compute_bands(const float *magnitudes, int fft_size, int sample_rate, float *bands, int num_bands) {
    if (num_bands <= 0) return;
    
    // We ignore the 0th bin (DC offset)
    int max_bin = fft_size / 2;
    float freq_resolution = (float)sample_rate / fft_size;
    
    // Define the logarithmic range (e.g. 20Hz to 20,000Hz)
    float min_freq = 20.0f;
    float max_freq = sample_rate / 2.0f;
    if (max_freq > 20000.0f) max_freq = 20000.0f; // Limit to human hearing
    
    float log_min = log10f(min_freq);
    float log_max = log10f(max_freq);
    float log_range = log_max - log_min;
    
    for (int i = 0; i < num_bands; i++) {
        // Calculate the frequency range for this band
        float start_log = log_min + (i / (float)num_bands) * log_range;
        float end_log = log_min + ((i + 1) / (float)num_bands) * log_range;
        
        float start_freq = powf(10.0f, start_log);
        float end_freq = powf(10.0f, end_log);
        
        int start_bin = (int)(start_freq / freq_resolution);
        int end_bin = (int)(end_freq / freq_resolution);
        
        if (start_bin < 1) start_bin = 1;
        if (end_bin > max_bin - 1) end_bin = max_bin - 1;
        if (end_bin < start_bin) end_bin = start_bin;
        
        // Average the magnitudes in this bin range
        float sum = 0.0f;
        int count = end_bin - start_bin + 1;
        for (int j = start_bin; j <= end_bin; j++) {
            sum += magnitudes[j];
        }
        bands[i] = sum / count;
    }
}

void audio_dsp_apply_psychoacoustic_scaling(float *bands, int num_bands) {
    for (int i = 0; i < num_bands; i++) {
        // Apply a gentle curve that boosts higher bands (+3dB/octave slope equivalent)
        // This makes treble visible alongside heavy bass
        float scale = 1.0f + (i / (float)num_bands) * 3.0f;
        bands[i] *= scale;
    }
}

void audio_dsp_smooth_decay(const float *current, float *previous, int num_bands, float attack, float decay) {
    for (int i = 0; i < num_bands; i++) {
        if (current[i] > previous[i]) {
            // Fast attack: jump up quickly
            previous[i] = previous[i] + attack * (current[i] - previous[i]);
        } else {
            // Smooth decay: fall down gently
            previous[i] = previous[i] + decay * (current[i] - previous[i]);
        }
    }
}
