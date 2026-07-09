// usage_guide.c — integrates the new audio_analysis module for end users who want raw/FFT features.
//
// This example shows how to spin up the PipeWire capture via audio_stream, feed the analysis module,
// and pull snapshots for downstream processing (visualization, analysis, etc.).
//
// All major components are thread-safe and should reside in the same process:
//   - audio_stream (PulseAudio/PipeWire capture, active-stream detection)  
//   - audio_analysis (FFT, RMS, spectral bands, streaming feature extraction)
//
// Use this to:
//   * Build `ocws-speaker-gl`, `ocws-speaker-qs`, or any new utility
//   * Run the example: `cc usage_guide.c -I./src/libocws -o usage_guide $(pkg-config --cflags gcc) $(pkg-config --libs ...)`
//   * While audio plays, polling `audio_stream_snapshot()` gives you:
//       - Raw PCM rings per channel (float)
//       - RMS and peak levels
//       - FFT magnitude (log-scale friendly)
//       - 4 band averages (bass/1k/2k/4k~16kHz)
//       - Spectral centroid (brightness)
//
// The Qt/Quickshell `OcwsAudioQS.qml` can stay unchanged; it pulls the same JSON fields.

// include headers
#include "libocws/audio_stream.h"   // catch: backward compatibility; rename later if desired
#include "libocws/audio_analysis.h" // our core extractor
#include <stdio.h>
#include <unistd.h>

int main(void) {
    // 1. Set up the PipeWire capture (default sink's monitor) + PulseAudio active-stream lookup
    if (audio_stream_init() != 0) {
        fprintf(stderr, "init failed\n");
        return 1;
    }

    // 2. Print initial active stream and a quick summary
    printf("Audio capture ready.\n");
    printf("Active stream: '%s'\n", audio_stream_active());

    // 3. Display feature definitions of analysis
    const audio_analysis_params *aa = audio_analysis_params_get();
    printf("\nAnalysis parameters:\n");
    printf("  sample_rate:       %d\n", aa->rate);
    printf("  channels:          %d\n", aa->channels);
    printf("  fft_size:          %d\n", aa->fft_size);
    printf("  band_count:        %d\n", aa->n_bands);
    printf("  buffer_ring_size:  %d samples\n", aa->ring_size);

    // 4. Show how to pull a snapshot (the holy grail for downstream UI/analysis)
    audio_features_t feats;
    audio_analysis_snapshot(&feats);

    printf("\n--- Example snapshot (first 5 seconds) ---\n");
    printf("  RMS levels: L=%.6f, R=%.6f\n", feats.rms_l, feats.rms_r);
    printf("  Peak levels: L=%.6f, R=%.6f\n", feats.peak_l, feats.peak_r);
    printf("  Active stream: '%s'\n", audio_stream_active());

    // 5. Drop a small helper to dump the raw PCM rings if a downstream app wants it
    const float *ring_l = feats.raw_l;
    const float *ring_r = feats.raw_r;
    int ring_len = feats.raw_count;
    printf("  Raw PCM ring[0..3]: % .4f % .4f % .4f % .4f\n", ring_l[0], ring_r[0], ring_l[1], ring_r[1]);

    // 6. Look at spectral bands in dB (simple conversion)
    printf("  Spectral bands (log approx):\n");
    const char *band_labels[] = { "bass", "low-mid", "high-mid", "treble" };
    for (int b = 0; b < feats.n_bands; b++) {
        double dB = 20.0 * log10(feats.bands[b] > 0 ? feats.bands[b] : 1e-12);
        printf("    %s: %.1f dB\n", band_labels[b], dB);
    }

    // 7. Quick “normalized centroid” (brightness)
    printf("  Spectral centroid (bins): %.1f\n", feats.centroid);

    // 8. FFT snapshot (first 4 bins)
    printf("  FFT magnitude (first 4 bins): ");
    for (int k = 0; k < 4 && k < feats.n_bins; k++) {
        printf("%.3f ", feats.spectrum[k]);
    }
    printf("\n\n");

    // 9. Explicit demonstration: feed some samples via the analysis module
    //    (in the real app, this comes directly from PipeWire capture)
    printf("> Feed synthetic signal to analysis...\n");
    float dummy_signal[4096]; // 2s @48kHz stereo = 4096 f32 values
    for (int i = 0; i < 4096; i++) {
        float val = (i % 123) / 123.0f * 2.0f - 1.0f;
        dummy_signal[i] = (i % 2 == 0) ? val : -val;
    }
    audio_analysis_push(dummy_signal, 4096, 2);

    // 10. Pull again after feeding; features are now more than startup zeros
    audio_analysis_snapshot(&feats);
    printf("  After feeding: RMS L=%.6f, R=%.6f\n", feats.rms_l, feats.rms_r);

    // 11. Teardown when done
    audio_stream_deinit();
    audio_analysis_deinit();
    return 0;
}
