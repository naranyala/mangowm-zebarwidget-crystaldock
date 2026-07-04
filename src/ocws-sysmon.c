#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>

void get_cpu(unsigned long long *idle_out, unsigned long long *total_out) {
    FILE *f = fopen("/proc/stat", "r");
    if (!f) return;
    unsigned long long user, nice, system, idle, iowait, irq, softirq, steal;
    if (fscanf(f, "cpu %llu %llu %llu %llu %llu %llu %llu %llu", &user, &nice, &system, &idle, &iowait, &irq, &softirq, &steal) == 8) {
        *idle_out = idle + iowait;
        *total_out = user + nice + system + idle + iowait + irq + softirq + steal;
    }
    fclose(f);
}

void print_mem() {
    FILE *f = fopen("/proc/meminfo", "r");
    if (!f) return;
    char line[256];
    long total = 0, free = 0, buffers = 0, cached = 0, sreclaimable = 0, shmem = 0;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "MemTotal:", 9) == 0) sscanf(line, "MemTotal: %ld kB", &total);
        else if (strncmp(line, "MemFree:", 8) == 0) sscanf(line, "MemFree: %ld kB", &free);
        else if (strncmp(line, "Buffers:", 8) == 0) sscanf(line, "Buffers: %ld kB", &buffers);
        else if (strncmp(line, "Cached:", 7) == 0) sscanf(line, "Cached: %ld kB", &cached);
        else if (strncmp(line, "SReclaimable:", 13) == 0) sscanf(line, "SReclaimable: %ld kB", &sreclaimable);
        else if (strncmp(line, "Shmem:", 6) == 0) sscanf(line, "Shmem: %ld kB", &shmem);
    }
    fclose(f);
    long used = total - free - buffers - cached - sreclaimable + shmem;
    printf("MEM_TOT=%ld\n", total / 1024);
    printf("MEM_USED=%ld\n", used / 1024);
    printf("MEM_PCT=%.1f\n", (used * 100.0) / total);
}

void print_net() {
    FILE *f = fopen("/proc/net/dev", "r");
    if (!f) return;
    char line[512];
    unsigned long long total_rx = 0, total_tx = 0;
    while (fgets(line, sizeof(line), f)) {
        if (strstr(line, "lo:") || strstr(line, "Inter-") || strstr(line, " face")) continue;
        char *colon = strchr(line, ':');
        if (colon) {
            unsigned long long rx, tx;
            if (sscanf(colon + 1, "%llu %*u %*u %*u %*u %*u %*u %*u %llu", &rx, &tx) == 2) {
                total_rx += rx;
                total_tx += tx;
            }
        }
    }
    fclose(f);
    printf("NET_RX=%llu\n", total_rx);
    printf("NET_TX=%llu\n", total_tx);
}

void print_wifi() {
    DIR *d = opendir("/sys/class/net");
    if (d) {
        struct dirent *dir;
        while ((dir = readdir(d)) != NULL) {
            if (dir->d_name[0] == '.') continue;
            char path[256];
            snprintf(path, sizeof(path), "/sys/class/net/%s/wireless", dir->d_name);
            if (access(path, F_OK) == 0) {
                snprintf(path, sizeof(path), "/sys/class/net/%s/operstate", dir->d_name);
                FILE *f = fopen(path, "r");
                if (f) {
                    char state[64];
                    if (fscanf(f, "%63s", state) == 1) {
                        // up -> connected, down -> disconnected
                        if (strcmp(state, "up") == 0) printf("WIFI_STATE=connected\n");
                        else printf("WIFI_STATE=disconnected\n");
                    }
                    fclose(f);
                }
                break;
            }
        }
        closedir(d);
    }
}

void print_bluetooth() {
    DIR *d = opendir("/sys/class/rfkill");
    if (d) {
        struct dirent *dir;
        while ((dir = readdir(d)) != NULL) {
            if (strncmp(dir->d_name, "rfkill", 6) == 0) {
                char path[256], type[64];
                snprintf(path, sizeof(path), "/sys/class/rfkill/%s/type", dir->d_name);
                FILE *f = fopen(path, "r");
                if (f) { fscanf(f, "%63s", type); fclose(f); }
                
                if (strcmp(type, "bluetooth") == 0) {
                    int state = 0;
                    snprintf(path, sizeof(path), "/sys/class/rfkill/%s/state", dir->d_name);
                    f = fopen(path, "r");
                    if (f) { fscanf(f, "%d", &state); fclose(f); }
                    
                    if (state == 1) printf("BT_STATE=On\n");
                    else printf("BT_STATE=Off\n");
                    break;
                }
            }
        }
        closedir(d);
    }
}

void print_battery() {
    DIR *d = opendir("/sys/class/power_supply");
    if (!d) return;
    struct dirent *dir;
    while ((dir = readdir(d)) != NULL) {
        if (strncmp(dir->d_name, "BAT", 3) == 0) {
            char path[256];
            snprintf(path, sizeof(path), "/sys/class/power_supply/%s/capacity", dir->d_name);
            FILE *f = fopen(path, "r");
            if (f) {
                int cap;
                if (fscanf(f, "%d", &cap) == 1) printf("BAT_LVL=%d\n", cap);
                fclose(f);
            }
            snprintf(path, sizeof(path), "/sys/class/power_supply/%s/status", dir->d_name);
            f = fopen(path, "r");
            if (f) {
                char stat[64];
                if (fscanf(f, "%63s", stat) == 1) printf("BAT_STAT=%s\n", stat);
                fclose(f);
            }
            break; 
        }
    }
    closedir(d);
}

void print_brightness() {
    DIR *d = opendir("/sys/class/backlight");
    if (!d) return;
    struct dirent *dir;
    while ((dir = readdir(d)) != NULL) {
        if (dir->d_name[0] != '.') {
            char path[256];
            int max_b = 0, cur_b = 0;
            snprintf(path, sizeof(path), "/sys/class/backlight/%s/max_brightness", dir->d_name);
            FILE *f = fopen(path, "r");
            if (f) { fscanf(f, "%d", &max_b); fclose(f); }
            snprintf(path, sizeof(path), "/sys/class/backlight/%s/brightness", dir->d_name);
            f = fopen(path, "r");
            if (f) { fscanf(f, "%d", &cur_b); fclose(f); }
            if (max_b > 0) printf("BRIGHTNESS=%d\n", (cur_b * 100) / max_b);
            break; 
        }
    }
    closedir(d);
}

void print_temp() {
    FILE *f = fopen("/sys/class/thermal/thermal_zone0/temp", "r");
    if (f) {
        int temp;
        if (fscanf(f, "%d", &temp) == 1) {
            printf("TEMP=%d\n", temp / 1000);
        }
        fclose(f);
    }
}

int main() {
    unsigned long long idle, tot;
    get_cpu(&idle, &tot);
    
    // Output all stats in a simple KEY=VALUE format delimited by newlines
    printf("CPU_IDLE=%llu\n", idle);
    printf("CPU_TOT=%llu\n", tot);
    print_mem();
    print_net();
    print_wifi();
    print_bluetooth();
    print_battery();
    print_brightness();
    print_temp();
    
    return 0;
}
