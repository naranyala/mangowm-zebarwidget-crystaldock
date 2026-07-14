#include <gtest/gtest.h>
#include "system_info.h"

// Test the CPU stat parser
TEST(SystemInfoTest, ParseCpuStat) {
    uint64_t prev_idle = 0;
    uint64_t prev_total = 0;

    // Simulate first reading
    const char* stat1 = "cpu 100 0 50 850 0 0 0 0\n"; // user=100, sys=50, idle=850, total=1000
    double usage1 = SystemInfo::parse_cpu_stat(stat1, prev_idle, prev_total);
    // On first run, it compares against 0, so diff_total = 1000, diff_idle = 850
    // Usage = (1.0 - 850/1000) * 100 = 15%
    EXPECT_DOUBLE_EQ(usage1, 15.0);
    EXPECT_EQ(prev_idle, 850);
    EXPECT_EQ(prev_total, 1000);

    // Simulate second reading, 1000 ticks later
    // 100 new user ticks, 900 new idle ticks -> total 2000, idle 1750
    const char* stat2 = "cpu 200 0 50 1750 0 0 0 0\n";
    double usage2 = SystemInfo::parse_cpu_stat(stat2, prev_idle, prev_total);
    
    // diff_total = 1000, diff_idle = 900
    // Usage = (1.0 - 900/1000) * 100 = 10%
    EXPECT_DOUBLE_EQ(usage2, 10.0);
    EXPECT_EQ(prev_idle, 1750);
    EXPECT_EQ(prev_total, 2000);
}

// Test the Memory info parser
TEST(SystemInfoTest, ParseMemInfo) {
    const char* meminfo_mock = 
        "MemTotal:       16301308 kB\n"
        "MemFree:         4385108 kB\n"
        "MemAvailable:   10012345 kB\n"
        "Buffers:          218320 kB\n"
        "Cached:          4443196 kB\n"
        "SwapCached:            0 kB\n";

    uint64_t total_kb = 0;
    uint64_t available_kb = 0;

    SystemInfo::parse_meminfo(meminfo_mock, total_kb, available_kb);

    EXPECT_EQ(total_kb, 16301308);
    EXPECT_EQ(available_kb, 10012345);
}

// Test time format (basic check)
TEST(SystemInfoTest, TimeFormat) {
    std::string t = SystemInfo::current_time("%H:%M");
    // Ensure it's not empty and has a colon
    EXPECT_FALSE(t.empty());
    EXPECT_NE(t.find(':'), std::string::npos);
}
