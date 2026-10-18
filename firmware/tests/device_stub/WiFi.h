#ifndef KICKBAC_DEVICE_TEST_WIFI_H
#define KICKBAC_DEVICE_TEST_WIFI_H
#include <cstddef>
#include <cstring>
#include <string>
static const int WL_CONNECTED = 3;
extern std::string fixture_body;
struct FixtureWiFi { int status() { return WL_CONNECTED; } };
extern FixtureWiFi WiFi;
class WiFiClient {
public:
    void setTimeout(unsigned long) {}
    std::size_t readBytes(char* output, std::size_t count) {
        std::memcpy(output, fixture_body.data(), count);
        return count;
    }
};
#endif
