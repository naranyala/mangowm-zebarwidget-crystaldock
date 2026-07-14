#pragma once
// system_info.h - Read system information from /proc and system APIs
//
// Provides static methods to read CPU usage, memory, battery, and time.
// All methods are self-contained and read directly from procfs.

#include <string>
#include <cstdint>

struct SystemInfo {
    // CPU usage as percentage (0-100). Computes delta between calls.
    static double cpu_usage();

    // Memory info
    static double memory_usage_percent();
    static double memory_total_gb();
    static double memory_used_gb();

    // Formatted time strings
    static std::string current_time(const char* fmt = "%H:%M:%S");
    static std::string current_date(const char* fmt = "%a %b %d");

    // Battery (returns -1 if no battery found)
    static int battery_percent();
    static bool battery_charging();

    // --- Exposed for testing ---
    static double parse_cpu_stat(const char* stat_line, uint64_t& prev_idle, uint64_t& prev_total);
    static void parse_meminfo(const char* meminfo_content, uint64_t& total_kb, uint64_t& available_kb);
};
