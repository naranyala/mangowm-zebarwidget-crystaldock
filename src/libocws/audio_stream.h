#ifndef OCWS_AUDIO_STREAM_H
#define OCWS_AUDIO_STREAM_H

#include "audio_analysis.h"

/*
 * ocws audio_stream — proper PulseAudio capture/monitor module.
 *
 * Resolves the default sink's monitor source (system output) and opens a
 * stereo capture, so the visualiser reacts to whatever the system is
 * playing. Also tracks the currently active playback stream's name for a
 * "now playing" label. A richer feature extractor (raw PCM ring,
 * RMS/peak, FFT spectrum, bands, centroid) is fed from the same
 * capture via audio_analysis; pull it with audio_stream_snapshot().
 */

/* Connect, resolve the monitor source, open capture. 0 on success, -1 fail. */
int  audio_stream_init(void);

/* Tear down capture and PulseAudio connection. */
void audio_stream_deinit(void);

/* Latest stereo RMS levels (roughly 0..1). Thread-safe. */
void audio_stream_levels(float *left, float *right);

/* Name of the active playback stream ("" if nothing playing). Static buffer. */
const char *audio_stream_active(void);

/* Raw + spectral snapshot (raw PCM ring, RMS/peak, FFT spectrum,
 * bands, centroid). See audio_analysis.h. Thread-safe. */
void audio_stream_snapshot(audio_features_t *out);

#endif
