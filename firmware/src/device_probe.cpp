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
#include "saved_wifi.hpp"
#include "tls_root.hpp"
#if defined(KICKBAC_MOCK_UPLOAD)
#include <esp_system.h>
#include "mock_upload.hpp"
#endif

#if !defined(ARDUINO_XIAO_ESP32S3) || !defined(KICKBAC_DEVICE_DIAGNOSTIC)
#error "Use the confirmed XIAO ESP32-S3 authenticated-device diagnostic target."
#endif

namespace {
kickbac::DeviceCredentialFrame credential;
kickbac::SessionFence session_fence;
kickbac::DeviceRecovery recovery;
bool failed = false;
bool negative_checked = false;
bool negative_retry = false;
bool wifi_setup_requested = false;
kickbac::WifiSetupCommand wifi_setup_command;
bool pass_reported = false;
unsigned heartbeats = 0;
unsigned polls = 0;
std::uint32_t last_ready = 0;
std::uint32_t last_heartbeat = 0;
std::uint32_t last_poll = 0;
char previous_seen[40] = {};
#if defined(KICKBAC_MOCK_UPLOAD)
kickbac::MockUpload mock_upload;
kickbac::MockCommand mock_command;
std::uint32_t last_mock_ready = 0;
constexpr const char* upload_mode = "mock_only";
#else
constexpr const char* upload_mode = "disabled";
#endif

std::int64_t utc_upper_ms() {
    const std::time_t seconds = std::time(nullptr);
    return seconds > 0 ? static_cast<std::int64_t>(seconds) * 1000 + 999 : 0;
}

void stop_probe(const char* stage, int status) {
    negative_retry = false;
    session_fence.clear();
    recovery.clear();
#if defined(KICKBAC_MOCK_UPLOAD)
    mock_upload.hold();
#endif
    credential.clear();
    failed = true;
    Serial.printf("DEVICE_FAIL stage=%s status=%d credential=cleared uploads=%s\n", stage, status, upload_mode);
}

int request(bool heartbeat, bool authenticated, char (&body)[769], const char* payload = nullptr) {
    body[0] = '\0';
    WiFiClientSecure tls;
    tls.setCACert(KICKBAC_ISRG_ROOT_X1);
    tls.setHandshakeTimeout(12);
    HTTPClient http;
    http.setConnectTimeout(7000);
    http.setTimeout(7000);
    http.setReuse(false);
    http.setFollowRedirects(HTTPC_DISABLE_FOLLOW_REDIRECTS);
    const char* url = payload ? "https://api.kickbac.vodka/v1/device/measurements" :
                     (heartbeat ? "https://api.kickbac.vodka/v1/device/heartbeat"
                                : "https://api.kickbac.vodka/v1/device/session");
    if (!http.begin(tls, url)) return -1;
    if (authenticated) {
        String authorization("Bearer ");
        authorization += credential.token();
        http.addHeader("Authorization", authorization);
    }
    if (heartbeat || payload) http.addHeader("Content-Type", "application/json");
    int status = payload ? http.POST(payload) : (heartbeat ? http.POST("{}") : http.GET());
    const int length = http.getSize();
    if (status == 200 || (payload && status == 201)) {
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
bool perform_negative_check() {
    char body[769] = {};
    const int status = request(false, false, body);
    if (status == 401) {
        negative_checked = true;
        negative_retry = false;
        recovery.clear();
        Serial.printf("device_auth_negative status=401 rejected=1\n");
        return true;
    }
    if (kickbac::retryable_device_status(status)) {
        negative_retry = true;
        request_failed(false, status);
    } else stop_probe("unauthenticated_poll", status);
    return false;
}

#if defined(KICKBAC_MOCK_UPLOAD)
void service_mock_command() {
    for (unsigned count = 0; count < 32 && Serial.available() > 0; ++count) {
        const int byte = Serial.read();
        if (byte >= 0 && wifi_setup_command.feed(static_cast<std::uint8_t>(byte))) {
            wifi_setup_requested = true;
            mock_command = kickbac::MockCommand{};
            device_network_lost();
            return;
        }
        if (byte < 0 || !mock_command.feed(static_cast<std::uint8_t>(byte),
                                         static_cast<std::uint32_t>(millis()))) continue;
        kickbac::SessionTicket before_poll;
        if (recovery.active() || !session_fence.begin(before_poll, static_cast<std::uint32_t>(millis()), utc_upper_ms()) ||
            std::strcmp(before_poll.id, mock_command.session_id()) != 0 || !mock_upload.can_start(before_poll.id)) {
            Serial.printf("MOCK_BLOCKED reason=no_fresh_armed_session pending=%d\n", mock_upload.pending() ? 1 : 0);
            continue;
        }
        // A command binds to the current session BEFORE fresh server validation.
        // A changed session in the validation response is rejected, not adopted.
        if (!perform_request(false) || !session_fence.matches(before_poll,
                static_cast<std::uint32_t>(millis()), utc_upper_ms())) {
            Serial.printf("MOCK_BLOCKED reason=session_not_confirmed pending=%d\n", mock_upload.pending() ? 1 : 0);
            return;
        }
        std::uint8_t bytes[16] = {};
        esp_fill_random(bytes, sizeof(bytes));
        bytes[6] = static_cast<std::uint8_t>((bytes[6] & 0x0fU) | 0x40U);
        bytes[8] = static_cast<std::uint8_t>((bytes[8] & 0x3fU) | 0x80U);
        char id[37] = {};
        std::snprintf(id, sizeof(id), "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            static_cast<unsigned>(bytes[0]), static_cast<unsigned>(bytes[1]), static_cast<unsigned>(bytes[2]), static_cast<unsigned>(bytes[3]),
            static_cast<unsigned>(bytes[4]), static_cast<unsigned>(bytes[5]), static_cast<unsigned>(bytes[6]), static_cast<unsigned>(bytes[7]),
            static_cast<unsigned>(bytes[8]), static_cast<unsigned>(bytes[9]), static_cast<unsigned>(bytes[10]), static_cast<unsigned>(bytes[11]),
            static_cast<unsigned>(bytes[12]), static_cast<unsigned>(bytes[13]), static_cast<unsigned>(bytes[14]), static_cast<unsigned>(bytes[15]));
        if (!mock_upload.start(session_fence, id, static_cast<std::uint32_t>(millis()), utc_upper_ms())) {
            Serial.printf("MOCK_BLOCKED reason=session_not_confirmed pending=%d\n", mock_upload.pending() ? 1 : 0);
            return;
        }
        Serial.printf("MOCK_PENDING measurement_id=%s session_id=%s source=simulator\n",
                      mock_upload.measurement_id(), mock_upload.session_id());
    }
}

void service_mock_upload() {
    const auto now = static_cast<std::uint32_t>(millis());
    if (!mock_upload.due(now)) return;
    if (!mock_upload.authorize_send(session_fence, now, utc_upper_ms())) {
        Serial.printf("MOCK_BLOCKED reason=ticket_lost pending=%d\n", mock_upload.pending() ? 1 : 0);
        return;
    }
    char body[769] = {};
    const int status = request(false, true, body, mock_upload.payload());
    const auto result = mock_upload.result(status, body, static_cast<std::uint32_t>(millis()));
    if (result == kickbac::MockResult::Accepted) {
        session_fence.clear();
        Serial.printf("MOCK_ACCEPTED http=%d measurement_id=%s session_id=%s source=simulator\n", status,
                      mock_upload.measurement_id(), mock_upload.session_id());
        return;
    }
    session_fence.clear();
    if (status == 401 || status == 403) { stop_probe("mock_auth", status); return; }
    if (result == kickbac::MockResult::Retry) {
        Serial.printf("MOCK_RETRY number=%u wait_ms=%lu source=simulator\n", mock_upload.attempts(),
                      static_cast<unsigned long>(mock_upload.wait_ms()));
    } else Serial.printf("MOCK_BLOCKED reason=response_unaccepted pending=1\n");
}

void report_mock_ready() {
    const auto now = static_cast<std::uint32_t>(millis());
    kickbac::SessionTicket ticket;
    if (now - last_mock_ready >= 3000U && !recovery.active() &&
        session_fence.begin(ticket, now, utc_upper_ms()) && mock_upload.can_start(ticket.id)) {
        last_mock_ready = now;
        Serial.printf("MOCK_READY source=simulator armed=1 session_id=%s\n", ticket.id);
    }
}
#endif
}  // namespace

void device_network_lost() {
    negative_retry = false;
    session_fence.clear();
    recovery.clear();
#if defined(KICKBAC_MOCK_UPLOAD)
    mock_upload.hold();
    const bool pending = mock_upload.pending();
#else
    const bool pending = false;
#endif
    Serial.printf("device_network state=lost credential=ram_retained pending=%d\n", pending ? 1 : 0);
}

bool device_take_wifi_setup() {
    const bool requested = wifi_setup_requested;
    wifi_setup_requested = false;
    return requested;
}

void device_probe_loop() {
    if (failed) return;
    const auto now = static_cast<std::uint32_t>(millis());
    session_fence.tick(now, utc_upper_ms());
    if (!credential.ready()) {
        credential.expire(now);
        if (now - last_ready >= 3000U) {
            last_ready = now;
            Serial.printf("device_ready credential_relay=ram_only sensor=disabled uploads=%s\n", upload_mode);
        }
        while (Serial.available() > 0) {
            const int value = Serial.read();
            if (value >= 0 && wifi_setup_command.feed(static_cast<std::uint8_t>(value))) {
                wifi_setup_requested = true;
                return;
            }
            if (value >= 0 && credential.feed(static_cast<std::uint8_t>(value),
                                              static_cast<std::uint32_t>(millis()))) { wifi_setup_command.clear(); break; }
        }
        return;
    }
    if (WiFi.status() != WL_CONNECTED) { device_network_lost(); return; }
    if (recovery.active()) {
#if defined(KICKBAC_MOCK_UPLOAD)
        service_mock_command();
#endif
        if (recovery.due(now)) {
            if (negative_retry) perform_negative_check();
            else perform_request(recovery.heartbeat());
        }
        return; // No other endpoint may mask/clear a failing endpoint's retry budget.
    }
    if (!negative_checked) {
        if (!perform_negative_check()) return;
    }
    if (heartbeats == 0 || now - last_heartbeat >= 10000U) {
        if (!perform_request(true)) return;
    }
    if (polls == 0 || now - last_poll >= 2000U) {
        if (!perform_request(false)) return;
    }
    if (!pass_reported && heartbeats >= 3 && polls >= 3) {
        Serial.printf("DEVICE_PASS identity=kb-demo-01 heartbeats=%u polls=%u online_refresh=1 ongoing=1 uploads=%s\n", heartbeats, polls, upload_mode);
        pass_reported = true;
    }
#if defined(KICKBAC_MOCK_UPLOAD)
    service_mock_command();
    if (!failed && !recovery.active()) { service_mock_upload(); report_mock_ready(); }
#endif
}
