#ifndef KICKBAC_DEVICE_TEST_ARDUINO_H
#define KICKBAC_DEVICE_TEST_ARDUINO_H
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

extern std::uint32_t fixture_now;
extern std::vector<std::string> fixture_lines;
class String {
public:
    explicit String(const char* value) : text(value) {}
    String& operator+=(const char* value) { text += value; return *this; }
    std::string text;
};
struct FixtureSerial {
    std::string input;
    int available() { return static_cast<int>(input.size()); }
    int read() { const int c = static_cast<unsigned char>(input.front()); input.erase(0, 1); return c; }
    void printf(const char* format, ...) {
        char buffer[512];
        va_list args;
        va_start(args, format);
        std::vsnprintf(buffer, sizeof(buffer), format, args);
        va_end(args);
        fixture_lines.emplace_back(buffer);
    }
};
extern FixtureSerial Serial;
inline unsigned long millis() { return fixture_now; }
#endif
