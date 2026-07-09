#ifndef OCWS_AUDIO_DSP_H
#define OCWS_AUDIO_DSP_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * OCWS Audio DSP Module
 * 
 * Provides native, allocation-free digital signal processing capabilities 
 * including Hann windowing, RMS tracking, Peak tracking, and Radix-2 Fast 
 * Fourier Transforms (FFT) for audio visualization and analysis.
 */

// Applies a Hann window to the audio buffer to reduce spectral leakage before FFT
void audio_dsp_apply_hann_window(float *buffer, int n);

// Performs a Radix-2 Cooley-Tukey FFT.
// `in`: Raw audio samples. `n` MUST be a power of 2 and <= 4096.
// `magnitudes`: Output array. Must have capacity for at least `n/2` elements.
// The output represents the frequency spectrum magnitudes (0 to Nyquist).
void audio_dsp_fft(const float *in, float *magnitudes, int n);

// Calculates the Root Mean Square (RMS) volume of a buffer.
float audio_dsp_rms(const float *buffer, int n);

// Calculates the Peak volume (absolute maximum amplitude) of a buffer.
float audio_dsp_peak(const float *buffer, int n);

// Converts linear magnitudes to Decibels (dB). 
// Useful for logarithmic visualizers.
void audio_dsp_magnitudes_to_db(float *magnitudes, int count);

// Groups raw FFT magnitudes into logarithmic frequency bands (octaves).
// `magnitudes`: raw FFT output (size: fft_size/2).
// `fft_size`: original buffer size (e.g., 1024).
// `bands`: output array (size: num_bands).
void audio_dsp_compute_bands(const float *magnitudes, int fft_size, int sample_rate, float *bands, int num_bands);

// Applies a +3dB per octave slope to visually balance treble with bass.
void audio_dsp_apply_psychoacoustic_scaling(float *bands, int num_bands);

// Applies temporal smoothing (exponential decay) to eliminate flickering.
// `current`: the newly computed bands.
// `previous`: the smoothed state from the last frame (will be updated).
// `attack`/`decay`: speed coefficients (0.0 to 1.0). E.g., attack 0.8, decay 0.15.
void audio_dsp_smooth_decay(const float *current, float *previous, int num_bands, float attack, float decay);

#ifdef __cplusplus
}
#endif

#endif
