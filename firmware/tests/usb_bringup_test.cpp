// Host fixture: no physical USB, ADC, sensor or network evidence.
#include <Arduino.h>

#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <string>
#include <vector>

TestSerial Serial;
static std::uint32_t now_ms = 0;
static unsigned delay_calls = 0;
static std::vector<std::string> lines;

void TestSerial::begin(unsigned long value) { baud = value; }
void TestSerial::printf(const char* format, ...) {
    char buffer[256];
    va_list args;
    va_start(args, format);
    std::vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    lines.emplace_back(buffer);
}
unsigned long millis() { return now_ms; }
void delay(unsigned long milliseconds) {
    if (milliseconds != 1) std::exit(2);
    ++delay_calls;
}
void setup();
void loop();

static void require(bool value, const char* message) {
    if (!value) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}

int main() {
    setup();
    require(Serial.baud == 115200, "USB serial baud initialized");
    require(delay_calls == 0, "setup does not wait for a connected USB host");
    now_ms = 999;
    loop();
    require(lines.empty(), "no status flood before reporting interval");
    now_ms = 1000;
    loop();
    require(lines.size() == 1, "periodic USB diagnostic emitted");
    require(lines[0].find("uptime_ms=1000") != std::string::npos, "actual monotonic uptime logged");
    require(lines[0].find("sensor=disabled") != std::string::npos &&
            lines[0].find("network=disabled") != std::string::npos,
            "USB-only diagnostic explicitly labels disabled sensor and network");
    for (unsigned t = 1001; t < 2000; ++t) {
        now_ms = t;
        loop();
    }
    require(lines.size() == 1, "rapid loop calls do not flood USB");
    now_ms = 2000;
    loop();
    require(lines.size() == 2, "next interval emits exactly one status");
    now_ms = std::numeric_limits<std::uint32_t>::max() - 500U;
    loop();
    const auto before_wrap = lines.size();
    now_ms = 200;
    loop();
    require(lines.size() == before_wrap, "wrap does not bypass the report interval");
    now_ms = 600;
    loop();
    require(lines.size() == before_wrap + 1, "periodic USB status survives wrap");
    require(delay_calls > 0, "loop yields without waiting on USB availability");
    std::cout << "PASS: USB-only adapter scheduling and labels (host fixture)\n";
}
