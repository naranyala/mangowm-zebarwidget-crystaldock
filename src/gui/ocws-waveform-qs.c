// ocws-waveform-qs: C audio backend for the Quickshell waveform widget.
//
// Captures the system's active audio, downsamples it to 128 points,
// and rapidly serializes it into a JSON array at $XDG_RUNTIME_DIR/ocws-waveform-qs.json
//
// Build: see build.zig (ocws-waveform-qs target). Run: ocws-waveform-qs

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <pulse/simple.h>
#include <pulse/error.h>
#include "../libocws/audio_dsp.h"

#define NUM_SAMPLES 1024
#define OUT_SAMPLES 128

static volatile int g_running = 1;

static void on_signal(int sig) {
    (void)sig;
    g_running = 0;
}

static void state_path(char *path, size_t n) {
    const char *rt = getenv("XDG_RUNTIME_DIR");
    if (rt && *rt)
        snprintf(path, n, "%s/ocws-waveform-qs.json", rt);
    else
        snprintf(path, n, "/tmp/ocws-waveform-qs.json");
}

int main(int argc, char **argv) {
    const char *style_str = "line";
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--style=filled") == 0) style_str = "filled";
        else if (strcmp(argv[i], "--style=mirrored") == 0) style_str = "mirrored";
        else if (strcmp(argv[i], "--style=dots") == 0) style_str = "dots";
        else if (strcmp(argv[i], "--style=line") == 0) style_str = "line";
    }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    char path[512], tmp[512];
    state_path(path, sizeof(path));
    snprintf(tmp, sizeof(tmp), "%s.tmp", path);

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
    attr.fragsize = sizeof(float) * NUM_SAMPLES; // Low latency

    int error;
    pa_simple *s = pa_simple_new(NULL, "ocws-waveform-qs", PA_STREAM_RECORD, 
                                 source_name[0] ? source_name : NULL, 
                                 "Record", &ss, NULL, &attr, &error);
    if (!s) {
        fprintf(stderr, "ocws-waveform-qs: Audio capture failed: %s\n", pa_strerror(error));
        return 1;
    }

    float temp_buffer[NUM_SAMPLES];
    while (g_running) {
        if (pa_simple_read(s, temp_buffer, sizeof(temp_buffer), &error) < 0) {
            fprintf(stderr, "pa_simple_read() failed: %s\n", pa_strerror(error));
            break;
        }

        FILE *out = fopen(tmp, "w");
        if (out) {
            audio_dsp_apply_hann_window(temp_buffer, NUM_SAMPLES);
            fprintf(out, "{\"style\":\"%s\",\"data\":[", style_str);
            int chunk = NUM_SAMPLES / OUT_SAMPLES;
            for (int i = 0; i < OUT_SAMPLES; i++) {
                float avg = 0;
                for (int j = 0; j < chunk; j++) {
                    avg += temp_buffer[i * chunk + j];
                }
                avg /= chunk;
                fprintf(out, "%.4f%s", avg, (i == OUT_SAMPLES - 1) ? "" : ",");
            }
            fprintf(out, "]}\n");
            fclose(out);
            rename(tmp, path);
        }
    }

    pa_simple_free(s);
    return 0;
}
