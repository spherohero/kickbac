#ifndef KICKBAC_DEVICE_TEST_HTTP_H
#define KICKBAC_DEVICE_TEST_HTTP_H
#include "Arduino.h"
#include "WiFiClientSecure.h"
#include <cassert>
#include <cstring>
static const int HTTPC_DISABLE_FOLLOW_REDIRECTS = 0;
extern unsigned fixture_posts;
extern unsigned fixture_gets;
extern bool fixture_rejected;
class HTTPClient {
public:
    void setConnectTimeout(unsigned value) { assert(value == 7000); }
    void setTimeout(unsigned value) { assert(value == 7000); }
    void setReuse(bool value) { assert(!value); }
    void setFollowRedirects(int value) { assert(value == HTTPC_DISABLE_FOLLOW_REDIRECTS); }
    bool begin(WiFiClientSecure&, const char* value) { url = value; return true; }
    void addHeader(const char* name, const char* value) {
        assert(std::strcmp(name, "Content-Type") == 0);
        assert(std::strcmp(value, "application/json") == 0);
        json_type = true;
    }
    void addHeader(const char* name, const String& value) {
        assert(std::strcmp(name, "Authorization") == 0);
        assert(value.text == "Bearer " + std::string(43, 'x'));
        authenticated = true;
    }
    int POST(const char* value) {
        assert(url == "https://api.kickbac.vodka/v1/device/heartbeat");
        assert(authenticated && json_type && std::strcmp(value, "{}") == 0);
        ++fixture_posts;
        if (fixture_rejected) return 401;
        char body[256];
        std::snprintf(body, sizeof(body), "{\"device_id\":\"kb-demo-01\",\"online\":true,\"last_seen_at\":\"2026-10-18T00:00:%02u+00:00\"}", fixture_now / 1000U);
        fixture_body = body;
        return 200;
    }
    int GET() {
        assert(url == "https://api.kickbac.vodka/v1/device/session");
        ++fixture_gets;
        if (!authenticated || fixture_rejected) return 401;
        fixture_body = "{\"device_id\":\"kb-demo-01\",\"active_session\":null}";
        return 200;
    }
    int getSize() { return static_cast<int>(fixture_body.size()); }
    WiFiClient* getStreamPtr() { return &stream; }
    void end() {}
private:
    bool authenticated = false;
    bool json_type = false;
    std::string url;
    WiFiClient stream;
};
#endif
