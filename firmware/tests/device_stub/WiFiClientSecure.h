#ifndef KICKBAC_DEVICE_TEST_TLS_H
#define KICKBAC_DEVICE_TEST_TLS_H
#include "WiFi.h"
#include <cassert>
extern unsigned fixture_trusted_requests;
class WiFiClientSecure : public WiFiClient {
public:
    void setCACert(const char* value) {
        assert(std::strstr(value, "-----BEGIN CERTIFICATE-----"));
        ++fixture_trusted_requests;
    }
    void setHandshakeTimeout(unsigned value) { assert(value == 12); }
};
#endif
