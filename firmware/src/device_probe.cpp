#include <Arduino.h>
#include <HTTPClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>

#include <cstdint>
#include <cstring>
#include <ctime>
#include "device_diagnostic.hpp"
#include "device_probe.hpp"
#include "network_runtime.hpp"
#include "session_safety.hpp"
#include "tls_root.hpp"

#if !defined(ARDUINO_XIAO_ESP32S3) || !defined(KICKBAC_DEVICE_DIAGNOSTIC)
#error "Use the confirmed XIAO ESP32-S3 authenticated-device diagnostic target."
#endif

namespace {
kickbac::DeviceCredentialFrame credential;
kickbac::SessionFence session_fence;
kickbac::DeviceRecovery recovery;
bool failed = false;
bool negative_checked = false;
bool pass_reported = false;
unsigned heartbeats = 0;
unsigned polls = 0;
std::uint32_t last_ready = 0;
std::uint32_t last_heartbeat = 0;
std::uint32_t last_poll = 0;
char previous_seen[40] = {};

std::int64_t utc_upper_ms() {
    const std::time_t seconds = std::time(nullptr);
    return seconds > 0 ? static_cast<std::int64_t>(seconds) * 1000 + 999 : 0;
}

void stop_probe(const char* stage, int status) {
    session_fence.clear();
    recovery.clear();
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

void request_failed(bool heartbeat, int status) {
    session_fence.clear(); // Never resume any acquisition across a transport gap.
    const char* stage = heartbeat ? "heartbeat" : "poll";
    if (kickbac::retryable_device_status(status) &&
        recovery.schedule(heartbeat, static_cast<std::uint32_t>(millis()))) {
        Serial.printf("device_retry stage=%s status=%d number=%u wait_ms=%lu acquisition=invalidated\n",
                      stage, status, recovery.count(), static_cast<unsigned long>(recovery.wait_ms()));
        return;
    }
    stop_probe(stage, status);
}

bool perform_request(bool heartbeat) {
    char body[769] = {};
    const int status = request(heartbeat, true, body);
    if (heartbeat) {
        char seen[40] = {};
        if (!kickbac::heartbeat_response_ok(status, body, seen)) {
            request_failed(true, status);
            return false;
        }
        if (heartbeats > 0 && std::strcmp(seen, previous_seen) <= 0) {
            stop_probe("heartbeat_not_advanced", status);
            return false;
        }
        std::strcpy(previous_seen, seen);
        last_heartbeat = static_cast<std::uint32_t>(millis());
        ++heartbeats;
        Serial.printf("device_heartbeat number=%u status=200 online=1 last_seen_at=%s\n", heartbeats, seen);
    } else {
        kickbac::PollSnapshot snapshot;
        const kickbac::PollState state = kickbac::poll_response(status, body, snapshot);
        if (state == kickbac::PollState::Invalid) { request_failed(false, status); return false; }
        session_fence.observe(snapshot, static_cast<std::uint32_t>(millis()), utc_upper_ms());
        const char* label = state == kickbac::PollState::Idle ? "IDLE" :
                            (state == kickbac::PollState::Armed ? "ARMED" : "SAMPLING");
        last_poll = static_cast<std::uint32_t>(millis());
        ++polls;
        Serial.printf("device_poll number=%u status=200 active_state=%s actions=disabled\n", polls, label);
    }
    if (recovery.active()) {
        Serial.printf("device_recovered stage=%s retries=%u acquisition=requires_fresh_session\n",
                      heartbeat ? "heartbeat" : "poll", recovery.count());
        recovery.clear();
    }
    return true;
}
}  // namespace

void device_probe_loop() {
    if (failed) return;
    const auto now = static_cast<std::uint32_t>(millis());
    session_fence.tick(now, utc_upper_ms());
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
    if (recovery.active()) {
        if (recovery.due(now)) perform_request(recovery.heartbeat());
        return; // No other endpoint may mask/clear a failing endpoint's retry budget.
    }
    char body[769] = {};
    if (!negative_checked) {
        const int status = request(false, false, body);
        if (status != 401) { stop_probe("unauthenticated_poll", status); return; }
        Serial.printf("device_auth_negative status=401 rejected=1\n");
        negative_checked = true;
    }
    if (heartbeats == 0 || now - last_heartbeat >= 10000U) {
        if (!perform_request(true)) return;
    }
    if (polls == 0 || now - last_poll >= 2000U) {
        if (!perform_request(false)) return;
    }
    if (!pass_reported && heartbeats >= 3 && polls >= 3) {
        Serial.printf("DEVICE_PASS identity=kb-demo-01 heartbeats=%u polls=%u online_refresh=1 ongoing=1 uploads=disabled\n", heartbeats, polls);
        pass_reported = true;
    }
}
