// system_info.cpp - Linux system info implementation via procfs

#include "system_info.h"
#include <cstdio>
#include <ctime>
#include <cstring>
#include <fstream>
#include <sstream>

// ============================================================================
// CPU usage — reads /proc/stat and computes delta between calls
// ============================================================================
double SystemInfo::parse_cpu_stat(const char* stat_line, uint64_t& prev_idle, uint64_t& prev_total) {
    uint64_t user, nice, system, idle, iowait, irq, softirq, steal;
    if (sscanf(stat_line, "cpu %lu %lu %lu %lu %lu %lu %lu %lu",
               &user, &nice, &system, &idle, &iowait, &irq, &softirq, &steal) < 4) {
        return 0.0;
    }

    uint64_t total_idle = idle + iowait;
    uint64_t total = user + nice + system + idle + iowait + irq + softirq + steal;

    uint64_t diff_idle  = total_idle - prev_idle;
    uint64_t diff_total = total - prev_total;

    prev_idle  = total_idle;
    prev_total = total;

    if (diff_total == 0) return 0.0;
    return (1.0 - (double)diff_idle / (double)diff_total) * 100.0;
}

double SystemInfo::cpu_usage() {
    static uint64_t prev_idle = 0, prev_total = 0;

    FILE* fp = fopen("/proc/stat", "r");
    if (!fp) return 0.0;

    char buf[256];
    if (!fgets(buf, sizeof(buf), fp)) { fclose(fp); return 0.0; }
    fclose(fp);

    return parse_cpu_stat(buf, prev_idle, prev_total);
}

// ============================================================================
// Memory — reads /proc/meminfo
// ============================================================================
void SystemInfo::parse_meminfo(const char* meminfo_content, uint64_t& total_kb, uint64_t& available_kb) {
    total_kb = available_kb = 0;
    std::stringstream ss(meminfo_content);
    std::string line;
    while (std::getline(ss, line)) {
        if (line.rfind("MemTotal:", 0) == 0)
            sscanf(line.c_str() + 9, "%lu", &total_kb);
        else if (line.rfind("MemAvailable:", 0) == 0)
            sscanf(line.c_str() + 13, "%lu", &available_kb);
    }
}

static void read_meminfo(uint64_t& total_kb, uint64_t& available_kb) {
    total_kb = available_kb = 0;
    std::ifstream f("/proc/meminfo");
    if (!f.is_open()) return;
    std::stringstream buffer;
    buffer << f.rdbuf();
    SystemInfo::parse_meminfo(buffer.str().c_str(), total_kb, available_kb);
}

double SystemInfo::memory_usage_percent() {
    uint64_t total, available;
    read_meminfo(total, available);
    if (total == 0) return 0.0;
    return (double)(total - available) / (double)total * 100.0;
}

double SystemInfo::memory_total_gb() {
    uint64_t total, available;
    read_meminfo(total, available);
    return (double)total / (1024.0 * 1024.0);
}

double SystemInfo::memory_used_gb() {
    uint64_t total, available;
    read_meminfo(total, available);
    return (double)(total - available) / (1024.0 * 1024.0);
}

// ============================================================================
// Time
// ============================================================================
std::string SystemInfo::current_time(const char* fmt) {
    time_t now = time(nullptr);
    struct tm* tm = localtime(&now);
    char buf[64];
    strftime(buf, sizeof(buf), fmt, tm);
    return buf;
}

std::string SystemInfo::current_date(const char* fmt) {
    return current_time(fmt);  // Same implementation, different default format
}

// ============================================================================
// Battery — reads from /sys/class/power_supply/BAT0/
// ============================================================================
int SystemInfo::battery_percent() {
    std::ifstream f("/sys/class/power_supply/BAT0/capacity");
    if (!f.is_open()) return -1;
    int val = -1;
    f >> val;
    return val;
}

bool SystemInfo::battery_charging() {
    std::ifstream f("/sys/class/power_supply/BAT0/status");
    if (!f.is_open()) return false;
    std::string status;
    f >> status;
    return (status == "Charging" || status == "Full");
}
