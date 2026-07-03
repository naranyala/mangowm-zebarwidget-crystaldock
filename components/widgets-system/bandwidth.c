/* widgets-system/bandwidth.c - Per-adapter bandwidth monitor
 *
 * Reads /sys/class/net/<iface>/statistics/ for rx/tx bytes.
 * Detects default route interface, up/down state, and calculates rates.
 * Outputs JSON or human-readable format for widget consumption.
 *
 * Build: gcc -O2 -o bandwidth bandwidth.c
 * Usage: bandwidth [--json] [--interval N] [--once] [--iface NAME]
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include <time.h>
#include <signal.h>
#include <stdint.h>
#include <sys/stat.h>

#define MAX_IFACES 32
#define IFACE_NAME_LEN 16
#define PATH_MAX_LEN 256

static volatile int running = 1;

typedef struct {
    char name[IFACE_NAME_LEN];
    int  is_up;
    int  is_default;       /* default route interface */
    int  is_loopback;
    int  is_wireless;
    uint64_t rx_bytes;
    uint64_t tx_bytes;
    uint64_t rx_packets;
    uint64_t tx_packets;
    uint64_t rx_errors;
    uint64_t tx_errors;
    /* Previous sample for rate calculation */
    uint64_t prev_rx_bytes;
    uint64_t prev_tx_bytes;
    double rx_rate;        /* bytes/sec */
    double tx_rate;        /* bytes/sec */
} iface_t;

typedef struct {
    iface_t ifaces[MAX_IFACES];
    int     count;
    uint64_t total_rx;
    uint64_t total_tx;
    double  total_rx_rate;
    double  total_tx_rate;
} bandwidth_state_t;

static void sighandler(int sig) {
    (void)sig;
    running = 0;
}

/* Read a single uint64 from /sys/class/net/<iface>/statistics/<file> */
static uint64_t read_stat(const char *iface, const char *stat_file) {
    char path[PATH_MAX_LEN];
    snprintf(path, sizeof(path), "/sys/class/net/%s/statistics/%s", iface, stat_file);

    FILE *f = fopen(path, "r");
    if (!f) return 0;

    uint64_t val = 0;
    if (fscanf(f, "%lu", &val) != 1) val = 0;
    fclose(f);
    return val;
}

/* Read operstate: "up" -> 1, else 0 */
static int read_operstate(const char *iface) {
    char path[PATH_MAX_LEN];
    snprintf(path, sizeof(path), "/sys/class/net/%s/operstate", iface);

    FILE *f = fopen(path, "r");
    if (!f) return 0;

    char buf[16] = {0};
    if (!fgets(buf, sizeof(buf), f)) {
        fclose(f);
        return 0;
    }
    fclose(f);

    buf[strcspn(buf, "\n")] = 0;
    return (strcmp(buf, "up") == 0) ? 1 : 0;
}

/* Check if interface has /sys/class/net/<iface>/wireless */
static int is_wireless(const char *iface) {
    char path[PATH_MAX_LEN];
    snprintf(path, sizeof(path), "/sys/class/net/%.128s/wireless", iface);
    struct stat st;
    return (stat(path, &st) == 0) ? 1 : 0;
}

/* Get default route interface via /proc/net/route */
static void detect_default_route(char *out, size_t len) {
    out[0] = '\0';

    FILE *f = fopen("/proc/net/route", "r");
    if (!f) return;

    char line[512];
    /* Skip header */
    if (!fgets(line, sizeof(line), f)) {
        fclose(f);
        return;
    }

    while (fgets(line, sizeof(line), f)) {
        char iface[IFACE_NAME_LEN] = {0};
        unsigned long dest = 0;

        if (sscanf(line, "%15s %lx", iface, &dest) == 2) {
            /* destination 0x00000000 = default route */
            if (dest == 0) {
                strncpy(out, iface, len - 1);
                out[len - 1] = '\0';
                break;
            }
        }
    }
    fclose(f);
}

/* Detect all interfaces from /sys/class/net */
static void detect_interfaces(bandwidth_state_t *state) {
    DIR *dir = opendir("/sys/class/net");
    if (!dir) return;

    char default_iface[IFACE_NAME_LEN] = {0};
    detect_default_route(default_iface, sizeof(default_iface));

    struct dirent *entry;
    state->count = 0;

    while ((entry = readdir(dir)) != NULL && state->count < MAX_IFACES) {
        if (entry->d_name[0] == '.') continue;

        iface_t *iface = &state->ifaces[state->count];
        memset(iface, 0, sizeof(iface_t));

        snprintf(iface->name, IFACE_NAME_LEN, "%s", entry->d_name);
        iface->is_loopback = (strcmp(entry->d_name, "lo") == 0) ? 1 : 0;
        iface->is_wireless = is_wireless(entry->d_name);
        iface->is_up = read_operstate(entry->d_name);
        iface->is_default = (default_iface[0] &&
                             strcmp(entry->d_name, default_iface) == 0) ? 1 : 0;

        iface->rx_bytes = read_stat(entry->d_name, "rx_bytes");
        iface->tx_bytes = read_stat(entry->d_name, "tx_bytes");
        iface->rx_packets = read_stat(entry->d_name, "rx_packets");
        iface->tx_packets = read_stat(entry->d_name, "tx_packets");
        iface->rx_errors = read_stat(entry->d_name, "rx_errors");
        iface->tx_errors = read_stat(entry->d_name, "tx_errors");

        iface->prev_rx_bytes = iface->rx_bytes;
        iface->prev_tx_bytes = iface->tx_bytes;

        state->count++;
    }
    closedir(dir);
}

/* Update byte counters and compute rates */
static void update_rates(bandwidth_state_t *state, double elapsed_sec) {
    state->total_rx = 0;
    state->total_tx = 0;
    state->total_rx_rate = 0;
    state->total_tx_rate = 0;

    for (int i = 0; i < state->count; i++) {
        iface_t *iface = &state->ifaces[i];

        iface->prev_rx_bytes = iface->rx_bytes;
        iface->prev_tx_bytes = iface->tx_bytes;

        iface->rx_bytes = read_stat(iface->name, "rx_bytes");
        iface->tx_bytes = read_stat(iface->name, "tx_bytes");
        iface->rx_packets = read_stat(iface->name, "rx_packets");
        iface->tx_packets = read_stat(iface->name, "tx_packets");
        iface->rx_errors = read_stat(iface->name, "rx_errors");
        iface->tx_errors = read_stat(iface->name, "tx_errors");
        iface->is_up = read_operstate(iface->name);

        if (elapsed_sec > 0 && iface->is_up && !iface->is_loopback) {
            iface->rx_rate = (double)(iface->rx_bytes - iface->prev_rx_bytes) / elapsed_sec;
            iface->tx_rate = (double)(iface->tx_bytes - iface->prev_tx_bytes) / elapsed_sec;
        } else {
            iface->rx_rate = 0;
            iface->tx_rate = 0;
        }

        if (!iface->is_loopback) {
            state->total_rx += iface->rx_bytes;
            state->total_tx += iface->tx_bytes;
            state->total_rx_rate += iface->rx_rate;
            state->total_tx_rate += iface->tx_rate;
        }
    }
}

/* Format bytes to human-readable string */
static void fmt_bytes(char *buf, size_t len, uint64_t bytes) {
    if (bytes >= (uint64_t)1 << 40)
        snprintf(buf, len, "%.2f TiB", (double)bytes / ((uint64_t)1 << 40));
    else if (bytes >= (uint64_t)1 << 30)
        snprintf(buf, len, "%.2f GiB", (double)bytes / ((uint64_t)1 << 30));
    else if (bytes >= (uint64_t)1 << 20)
        snprintf(buf, len, "%.2f MiB", (double)bytes / ((uint64_t)1 << 20));
    else if (bytes >= (uint64_t)1 << 10)
        snprintf(buf, len, "%.2f KiB", (double)bytes / ((uint64_t)1 << 10));
    else
        snprintf(buf, len, "%lu B", bytes);
}

/* Format rate to human-readable string */
static void fmt_rate(char *buf, size_t len, double bytes_per_sec) {
    if (bytes_per_sec >= 1.0 * (1 << 30))
        snprintf(buf, len, "%.2f GiB/s", bytes_per_sec / (1 << 30));
    else if (bytes_per_sec >= 1.0 * (1 << 20))
        snprintf(buf, len, "%.2f MiB/s", bytes_per_sec / (1 << 20));
    else if (bytes_per_sec >= 1.0 * (1 << 10))
        snprintf(buf, len, "%.2f KiB/s", bytes_per_sec / (1 << 10));
    else
        snprintf(buf, len, "%.0f B/s", bytes_per_sec);
}

/* Print human-readable output */
static void print_human(const bandwidth_state_t *state, const char *filter_iface) {
    char rx_str[32], tx_str[32], rx_rate_str[32], tx_rate_str[32];

    printf("\033[1m%-12s %5s %5s  %-14s %-14s %-14s %-14s\033[0m\n",
           "IFACE", "UP", "TYPE", "RX TOTAL", "TX TOTAL", "RX RATE", "TX RATE");
    printf("%-12s %5s %5s  %-14s %-14s %-14s %-14s\n",
           "----", "--", "----", "--------", "--------", "--------", "--------");

    for (int i = 0; i < state->count; i++) {
        const iface_t *iface = &state->ifaces[i];

        if (filter_iface && strcmp(iface->name, filter_iface) != 0)
            continue;

        /* Skip loopback unless it's the only one */
        if (iface->is_loopback && state->count > 1 && !filter_iface)
            continue;

        fmt_bytes(rx_str, sizeof(rx_str), iface->rx_bytes);
        fmt_bytes(tx_str, sizeof(tx_str), iface->tx_bytes);
        fmt_rate(rx_rate_str, sizeof(rx_rate_str), iface->rx_rate);
        fmt_rate(tx_rate_str, sizeof(tx_rate_str), iface->tx_rate);

        const char *type_str = iface->is_wireless ? "wifi" : "eth";
        const char *up_str = iface->is_up ? "\033[32mup\033[0m" : "\033[31mdn\033[0m";
        const char *marker = iface->is_default ? " *" : "  ";

        printf("%s%-12s %5s %5s  %-14s %-14s %-14s %-14s\n",
               marker, iface->name, up_str, type_str,
               rx_str, tx_str, rx_rate_str, tx_rate_str);
    }

    /* Sum */
    fmt_bytes(rx_str, sizeof(rx_str), state->total_rx);
    fmt_bytes(tx_str, sizeof(tx_str), state->total_tx);
    fmt_rate(rx_rate_str, sizeof(rx_rate_str), state->total_rx_rate);
    fmt_rate(tx_rate_str, sizeof(tx_rate_str), state->total_tx_rate);

    printf("\033[1m%-12s      %-14s %-14s %-14s %-14s\033[0m\n",
           "TOTAL", rx_str, tx_str, rx_rate_str, tx_rate_str);
    printf("\033[2m(default route = *)\033[0m\n");
}

/* Print JSON output */
static void print_json(const bandwidth_state_t *state, const char *filter_iface) {
    printf("{\n");
    printf("  \"interfaces\": [\n");

    int printed = 0;
    for (int i = 0; i < state->count; i++) {
        const iface_t *iface = &state->ifaces[i];

        if (filter_iface && strcmp(iface->name, filter_iface) != 0)
            continue;
        if (iface->is_loopback && state->count > 1 && !filter_iface)
            continue;

        if (printed) printf(",\n");
        printf("    {\n");
        printf("      \"name\": \"%s\",\n", iface->name);
        printf("      \"up\": %s,\n", iface->is_up ? "true" : "false");
        printf("      \"default\": %s,\n", iface->is_default ? "true" : "false");
        printf("      \"wireless\": %s,\n", iface->is_wireless ? "true" : "false");
        printf("      \"rx_bytes\": %lu,\n", iface->rx_bytes);
        printf("      \"tx_bytes\": %lu,\n", iface->tx_bytes);
        printf("      \"rx_packets\": %lu,\n", iface->rx_packets);
        printf("      \"tx_packets\": %lu,\n", iface->tx_packets);
        printf("      \"rx_errors\": %lu,\n", iface->rx_errors);
        printf("      \"tx_errors\": %lu,\n", iface->tx_errors);
        printf("      \"rx_rate\": %.2f,\n", iface->rx_rate);
        printf("      \"tx_rate\": %.2f\n", iface->tx_rate);
        printf("    }");
        printed++;
    }

    printf("\n  ],\n");
    printf("  \"total\": {\n");
    printf("    \"rx_bytes\": %lu,\n", state->total_rx);
    printf("    \"tx_bytes\": %lu,\n", state->total_tx);
    printf("    \"rx_rate\": %.2f,\n", state->total_rx_rate);
    printf("    \"tx_rate\": %.2f\n", state->total_tx_rate);
    printf("  },\n");
    printf("  \"count\": %d\n", state->count);
    printf("}\n");
}

/* Print one-shot (for scripts/pipes) */
static void print_oneliner(const bandwidth_state_t *state) {
    /* Find default iface */
    const iface_t *def = NULL;
    for (int i = 0; i < state->count; i++) {
        if (state->ifaces[i].is_default) {
            def = &state->ifaces[i];
            break;
        }
    }

    char rx_str[32], tx_str[32], rx_rate_str[32], tx_rate_str[32];
    fmt_bytes(rx_str, sizeof(rx_str), state->total_rx);
    fmt_bytes(tx_str, sizeof(tx_str), state->total_tx);
    fmt_rate(rx_rate_str, sizeof(rx_rate_str), state->total_rx_rate);
    fmt_rate(tx_rate_str, sizeof(tx_rate_str), state->total_tx_rate);

    if (def) {
        printf("%s: %s / %s (total: %s / %s)\n",
               def->name, rx_rate_str, tx_rate_str, rx_str, tx_str);
    } else {
        printf("no connection: total %s / %s\n", rx_str, tx_str);
    }
}

static void usage(void) {
    printf("bandwidth - Per-adapter bandwidth monitor\n\n");
    printf("Usage:\n");
    printf("  bandwidth              Continuously update (1s interval)\n");
    printf("  bandwidth --once       Single snapshot\n");
    printf("  bandwidth --json       JSON output\n");
    printf("  bandwidth --json --once Single JSON snapshot\n");
    printf("  bandwidth --oneliner   One-line summary for scripts\n");
    printf("  bandwidth --iface eth0 Filter to specific interface\n");
    printf("  bandwidth --interval N Update interval in seconds\n");
    printf("  bandwidth --help       This help\n");
}

int main(int argc, char *argv[]) {
    int json_mode = 0;
    int once_mode = 0;
    int oneliner_mode = 0;
    int interval = 1;
    const char *filter_iface = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--json") == 0)
            json_mode = 1;
        else if (strcmp(argv[i], "--once") == 0)
            once_mode = 1;
        else if (strcmp(argv[i], "--oneliner") == 0)
            oneliner_mode = 1;
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage();
            return 0;
        } else if (strcmp(argv[i], "--iface") == 0 && i + 1 < argc) {
            filter_iface = argv[++i];
        } else if (strcmp(argv[i], "--interval") == 0 && i + 1 < argc) {
            interval = atoi(argv[++i]);
            if (interval < 1) interval = 1;
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            usage();
            return 1;
        }
    }

    signal(SIGINT, sighandler);
    signal(SIGTERM, sighandler);

    bandwidth_state_t state;
    memset(&state, 0, sizeof(state));

    /* Initial detection */
    detect_interfaces(&state);

    if (state.count == 0) {
        fprintf(stderr, "No network interfaces found\n");
        return 1;
    }

    /* First read (baseline) */
    update_rates(&state, 0);
    if (once_mode) {
        if (oneliner_mode)
            print_oneliner(&state);
        else if (json_mode)
            print_json(&state, filter_iface);
        else
            print_human(&state, filter_iface);
        return 0;
    }

    /* Continuous mode */
    struct timespec last, now;
    clock_gettime(CLOCK_MONOTONIC, &last);

    while (running) {
        sleep(interval);
        clock_gettime(CLOCK_MONOTONIC, &now);
        double elapsed = (now.tv_sec - last.tv_sec) + (now.tv_nsec - last.tv_nsec) / 1e9;
        last = now;

        /* Re-detect default route in case it changed */
        char default_iface[IFACE_NAME_LEN] = {0};
        detect_default_route(default_iface, sizeof(default_iface));
        for (int i = 0; i < state.count; i++) {
            state.ifaces[i].is_default = (default_iface[0] &&
                strcmp(state.ifaces[i].name, default_iface) == 0) ? 1 : 0;
        }

        update_rates(&state, elapsed);

        if (oneliner_mode) {
            printf("\r");
            print_oneliner(&state);
            fflush(stdout);
        } else if (json_mode) {
            print_json(&state, filter_iface);
        } else {
            /* Clear screen for continuous display */
            printf("\033[2J\033[H");
            print_human(&state, filter_iface);
        }
    }

    return 0;
}
