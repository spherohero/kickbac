#include <Arduino.h>
#include <HTTPClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>

#include <cstdint>
#include <cstring>
#include "device_diagnostic.hpp"
#include "device_probe.hpp"
#include "tls_root.hpp"

#if !defined(ARDUINO_XIAO_ESP32S3) || !defined(KICKBAC_DEVICE_DIAGNOSTIC)
#error "Use the confirmed XIAO ESP32-S3 authenticated-device diagnostic target."
#endif

namespace {
kickbac::DeviceCredentialFrame credential;
bool failed = false;
bool negative_checked = false;
bool pass_reported = false;
unsigned heartbeats = 0;
unsigned polls = 0;
std::uint32_t last_ready = 0;
std::uint32_t last_heartbeat = 0;
std::uint32_t last_poll = 0;
char previous_seen[40] = {};

void stop_probe(const char* stage, int status) {
    credential.clear();
    failed = true;
    Serial.printf("DEVICE_FAIL stage=%s status=%d credential=cleared uploads=disabled\n", stage, status);
}

int request(bool heartbeat, bool authenticated, char (&body)[769]) {
    body[0] = '\0';
    WiFiClientSecure tls;
    tls.setCACert(KICKBAC_ISRG_ROOT_X1);
    tls.setHandshakeTimeout(12);
    HTTPClient http;
    http.setConnectTimeout(7000);
    http.setTimeout(7000);
    http.setReuse(false);
    http.setFollowRedirects(HTTPC_DISABLE_FOLLOW_REDIRECTS);
    const char* url = heartbeat ? "https://api.kickbac.vodka/v1/device/heartbeat"
                                : "https://api.kickbac.vodka/v1/device/session";
    if (!http.begin(tls, url)) return -1;
    if (authenticated) {
        String authorization("Bearer ");
        authorization += credential.token();
        http.addHeader("Authorization", authorization);
    }
    if (heartbeat) http.addHeader("Content-Type", "application/json");
    int status = heartbeat ? http.POST("{}") : http.GET();
    const int length = http.getSize();
    if (status == 200) {
        if (length < 1 || length > 768) status = -2;
        else {
            WiFiClient* stream = http.getStreamPtr();
            stream->setTimeout(7000);
            const std::size_t count = stream->readBytes(body, static_cast<std::size_t>(length));
            body[count] = '\0';
            if (count != static_cast<std::size_t>(length) || std::strlen(body) != count) status = -3;
        }
    }
    http.end();
    return status;
}
}  // namespace

void device_probe_loop() {
    if (failed) return;
    const auto now = static_cast<std::uint32_t>(millis());
    if (!credential.ready()) {
        credential.expire(now);
        if (now - last_ready >= 3000U) {
            last_ready = now;
            Serial.printf("device_ready credential_relay=ram_only sensor=disabled uploads=disabled\n");
        }
        while (Serial.available() > 0) {
            const int value = Serial.read();
            if (value >= 0 && credential.feed(static_cast<std::uint8_t>(value),
                                              static_cast<std::uint32_t>(millis()))) break;
        }
        return;
    }
    if (WiFi.status() != WL_CONNECTED) { stop_probe("wifi_lost", -1); return; }
    char body[769] = {};
    if (!negative_checked) {
        const int status = request(false, false, body);
        if (status != 401) { stop_probe("unauthenticated_poll", status); return; }
        Serial.printf("device_auth_negative status=401 rejected=1\n");
        negative_checked = true;
    }
    if (heartbeats == 0 || now - last_heartbeat >= 10000U) {
        const int status = request(true, true, body);
        char seen[40] = {};
        if (!kickbac::heartbeat_response_ok(status, body, seen)) {
            stop_probe("heartbeat", status);
            return;
        }
        if (heartbeats > 0 && std::strcmp(seen, previous_seen) <= 0) {
            stop_probe("heartbeat_not_advanced", status);
            return;
        }
        std::strcpy(previous_seen, seen);
        last_heartbeat = static_cast<std::uint32_t>(millis());
        ++heartbeats;
        Serial.printf("device_heartbeat number=%u status=200 online=1 last_seen_at=%s\n", heartbeats, seen);
    }
    if (polls == 0 || now - last_poll >= 2000U) {
        const int status = request(false, true, body);
        const kickbac::PollState state = kickbac::poll_response(status, body);
        if (state == kickbac::PollState::Invalid) { stop_probe("poll", status); return; }
        const char* label = state == kickbac::PollState::Idle ? "IDLE" :
                            (state == kickbac::PollState::Armed ? "ARMED" : "SAMPLING");
        last_poll = static_cast<std::uint32_t>(millis());
        ++polls;
        Serial.printf("device_poll number=%u status=200 active_state=%s actions=disabled\n", polls, label);
    }
    if (!pass_reported && heartbeats >= 3 && polls >= 3) {
        Serial.printf("DEVICE_PASS identity=kb-demo-01 heartbeats=%u polls=%u online_refresh=1 ongoing=1 uploads=disabled\n", heartbeats, polls);
        pass_reported = true;
    }
}
