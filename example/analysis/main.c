// Usage example for the new audio_analysis module
// Consolidates audio feature extraction using PipeWire (monitor source)

#include "audio_analysis.h"
#include <stdio.h>
#include <unistd.h>

int main(void) {
    if (audio_analysis_init(1024, 8192, 48000, 2) != 0) {
        fprintf(stderr, "Failed to init analysis\n");
        return 1;
    }

    printf("Audio analysis ready. Feed samples and pull features.\n");
    printf("  - Sample size: rate=48000Hz, fft_size=1024, channels=2\n");
    printf("  - Raw ring buffer: 8192 samples per channel\n");
    printf("  - Spectral bands: 4 (bass, low-mid, high-mid, treble)\n");
    printf("  - FFT bins: %d (up to Nyquist)\n", 1024/2);

    // Simulate feeding samples from PipeWire capture
    float dummy[4096]; // 2s @48kHz stereo = 4096 f32 values
    for (int i = 0; i < 4096; i++) {
        float val = (i % 123) / 123.0f * 2.0f - 1.0f;
        dummy[i] = (i % 2 == 0) ? val : -val;
    }
    audio_analysis_push(dummy, 4096, 2);

    // Snapshot features for inspection
    audio_features_t feats;
    audio_analysis_snapshot(&feats);

    printf("\n=== Snapshot ===\n");
    printf("  Rate: %d Hz, Channels: %d\n", feats.rate, feats.channels);
    printf("  RMS L/R: %.6f / %.6f\n", feats.rms_l, feats.rms_r);
    printf("  Peak L/R: %.6f / %.6f\n", feats.peak_l, feats.peak_r);

    printf("  Spectral bands:\n");
    const char *labels[] = { "bass", "low-mid", "high-mid", "treble" };
    for (int b = 0; b < AA_NBANDS; b++) {
        printf("    %s: %.6f\n", labels[b], feats.bands[b]);
    }
    printf("  Spectral centroid: %.3f (bins\n", feats.centroid);

    printf("  FFT magnitude at low bins (0-3): ");
    for (int k = 0; k < 4 && k < feats.n_bins; k++)
        printf("%.2f ", feats.spectrum[k]);
    printf("\n");

    // Clean up
    audio_analysis_deinit();
    return 0;
}
