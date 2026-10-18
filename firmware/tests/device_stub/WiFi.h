#ifndef KICKBAC_DEVICE_TEST_WIFI_H
#define KICKBAC_DEVICE_TEST_WIFI_H
#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstring>
#include <string>
static const int WL_CONNECTED = 3;
extern std::string fixture_body;
extern int fixture_wifi_status;
extern std::size_t fixture_read_limit;
extern unsigned fixture_reads;
struct FixtureWiFi { int status() { return fixture_wifi_status; } };
extern FixtureWiFi WiFi;
class WiFiClient {
public:
    void setTimeout(unsigned long value) { assert(value == 7000); }
    std::size_t readBytes(char* output, std::size_t count) {
        ++fixture_reads;
        const std::size_t available = std::min(fixture_body.size(), fixture_read_limit);
        const std::size_t received = std::min(count, available);
        std::memcpy(output, fixture_body.data(), received);
        return received;
    }
};
#endif
