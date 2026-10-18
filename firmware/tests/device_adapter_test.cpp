// Synthetic API/clock/USB fixtures, not physical network evidence.
#include <Arduino.h>
#include <WiFi.h>
#include <cassert>
#include <iostream>
#include <string>
#include <vector>

std::uint32_t fixture_now = 0;
std::vector<std::string> fixture_lines;
std::string fixture_body;
unsigned fixture_posts = 0;
unsigned fixture_gets = 0;
unsigned fixture_trusted_requests = 0;
bool fixture_rejected = false;
bool fixture_begin_ok = true;
unsigned fixture_begins = 0;
unsigned fixture_ends = 0;
unsigned fixture_reads = 0;
int fixture_wifi_status = WL_CONNECTED;
std::size_t fixture_read_limit = std::string::npos;
int fixture_status = 200;
int fixture_negative_status = 401;
int fixture_length = -2;
bool fixture_override_body = false;
bool fixture_override_heartbeat = true;
std::string fixture_response_body;
FixtureSerial Serial;
FixtureWiFi WiFi;

#include "../src/device_probe.cpp"

void reset_fixture() {
    credential.clear();
    failed = negative_checked = pass_reported = false;
    heartbeats = polls = 0;
    last_ready = last_heartbeat = last_poll = 0;
    std::memset(previous_seen, 0, sizeof(previous_seen));
    fixture_now = 0;
    fixture_lines.clear();
    fixture_body.clear();
    Serial.input.clear();
    fixture_posts = fixture_gets = fixture_trusted_requests = 0;
    fixture_begins = fixture_ends = fixture_reads = 0;
    fixture_rejected = false;
    fixture_begin_ok = true;
    fixture_wifi_status = WL_CONNECTED;
    fixture_read_limit = std::string::npos;
    fixture_status = 200;
    fixture_negative_status = 401;
    fixture_length = -2;
    fixture_override_body = false;
    fixture_override_heartbeat = true;
    fixture_response_body.clear();
}

void provision_fixture() {
    Serial.input = "KBD1" + std::string(43, 'x');
    device_probe_loop();
    assert(credential.ready());
    device_probe_loop();
}

void assert_latched_stop(const std::string& expected_line) {
    assert(failed && !credential.ready());
    for (std::size_t i = 0; i < 44; ++i) assert(credential.token()[i] == '\0');
    assert(!fixture_lines.empty() && fixture_lines.back() == expected_line);
    for (const auto& line : fixture_lines) {
        assert(line.find(std::string(43, 'x')) == std::string::npos);
        assert(line.find("PRIVATE_RESPONSE_SENTINEL") == std::string::npos);
    }
    const unsigned stopped_begins = fixture_begins;
    const unsigned stopped_posts = fixture_posts;
    const unsigned stopped_gets = fixture_gets;
    const auto stopped_lines = fixture_lines.size();
    // Restoring transport and relaying another credential cannot silently restart.
    fixture_begin_ok = true;
    fixture_wifi_status = WL_CONNECTED;
    fixture_status = 200;
    fixture_now = 50000;
    Serial.input = "KBD1" + std::string(43, 'x');
    device_probe_loop();
    device_probe_loop();
    assert(fixture_begins == stopped_begins);
    assert(fixture_posts == stopped_posts && fixture_gets == stopped_gets);
    assert(fixture_lines.size() == stopped_lines && !credential.ready());
}

void fault_matrix() {
    struct FaultCase {
        const char* name;
        int length;
        std::size_t read_limit;
        int status;
        bool begin_ok;
        bool override_body;
        const char* body;
        int expected_status;
        bool reads_body;
    };
    const FaultCase cases[] = {
        {"unknown length", -1, std::string::npos, 200, true, false, "", -2, false},
        {"empty body", 0, std::string::npos, 200, true, true, "", -2, false},
        {"oversized length", 769, std::string::npos, 200, true, false, "", -2, false},
        {"short read", -2, 5, 200, true, false, "", -3, true},
        {"zero-byte read", -2, 0, 200, true, false, "", -3, true},
        {"malformed JSON", -2, std::string::npos, 200, true, true,
         "{PRIVATE_RESPONSE_SENTINEL", 200, true},
        {"wrong identity", -2, std::string::npos, 200, true, true,
         "{\"device_id\":\"PRIVATE_RESPONSE_SENTINEL\",\"active_session\":null}", 200, true},
        {"begin failure", -2, std::string::npos, 200, false, false, "", -1, false},
        {"transport failure", -2, std::string::npos, -11, true, false, "", -11, false},
        {"server error", -2, std::string::npos, 503, true, false, "", 503, false},
        {"redirect", -2, std::string::npos, 302, true, false, "", 302, false},
        {"unauthorized", -2, std::string::npos, 401, true, false, "", 401, false}
    };
    for (const bool heartbeat : {true, false}) {
        for (const auto& fault : cases) {
            reset_fixture();
            provision_fixture();
            assert(!failed && heartbeats == 1 && polls == 1);
            const unsigned before_begins = fixture_begins;
            const unsigned before_ends = fixture_ends;
            const unsigned before_reads = fixture_reads;
            const unsigned before_posts = fixture_posts;
            const unsigned before_gets = fixture_gets;
            fixture_now = heartbeat ? 10000U : 2000U;
            fixture_length = fault.length;
            fixture_read_limit = fault.read_limit;
            fixture_status = fault.status;
            fixture_begin_ok = fault.begin_ok;
            fixture_override_body = fault.override_body;
            fixture_override_heartbeat = heartbeat;
            fixture_response_body = fault.body;
            if (heartbeat && std::strcmp(fault.name, "wrong identity") == 0) {
                fixture_response_body = "{\"device_id\":\"PRIVATE_RESPONSE_SENTINEL\",\"online\":true,"
                    "\"last_seen_at\":\"2026-10-18T00:00:10+00:00\"}";
            }
            device_probe_loop();
            const std::string stage = heartbeat ? "heartbeat" : "poll";
            assert_latched_stop("DEVICE_FAIL stage=" + stage + " status=" +
                std::to_string(fault.expected_status) + " credential=cleared uploads=disabled\n");
            assert(fixture_begins == before_begins + 1);
            assert(fixture_ends == before_ends + (fault.begin_ok ? 1U : 0U));
            assert(fixture_reads == before_reads + (fault.reads_body ? 1U : 0U));
            assert(fixture_posts == before_posts + (heartbeat && fault.begin_ok ? 1U : 0U));
            assert(fixture_gets == before_gets + (!heartbeat && fault.begin_ok ? 1U : 0U));
            assert(heartbeats == 1 && polls == 1 && !pass_reported);
            std::cout << "PASS: " << stage << " " << fault.name << " (synthetic fault)\n";
        }
    }
}

void boundary_and_wifi_cases() {
    for (const bool heartbeat : {true, false}) {
        reset_fixture();
        provision_fixture();
        fixture_now = heartbeat ? 10000U : 2000U;
        fixture_override_body = true;
        fixture_override_heartbeat = heartbeat;
        fixture_response_body = heartbeat ?
            "{\"device_id\":\"kb-demo-01\",\"online\":true,\"last_seen_at\":\"2026-10-18T00:00:10+00:00\"}" :
            "{\"device_id\":\"kb-demo-01\",\"active_session\":null}";
        // The exact upper bound is accepted, not accidentally rejected as oversized.
        fixture_response_body.resize(768, ' ');
        device_probe_loop();
        assert(!failed && credential.ready());
        assert(heartbeats == (heartbeat ? 2U : 1U) && polls == 2);
        assert(fixture_begins == fixture_ends);

        reset_fixture();
        provision_fixture();
        fixture_now = heartbeat ? 10000U : 2000U;
        fixture_override_body = true;
        fixture_override_heartbeat = heartbeat;
        fixture_response_body = heartbeat ?
            "{\"device_id\":\"kb-demo-01\",\"online\":true,\"last_seen_at\":\"2026-10-18T00:00:10+00:00\"}" :
            "{\"device_id\":\"kb-demo-01\",\"active_session\":null}";
        fixture_response_body.push_back('\0');
        fixture_response_body += "PRIVATE_RESPONSE_SENTINEL";
        device_probe_loop();
        assert_latched_stop(std::string("DEVICE_FAIL stage=") + (heartbeat ? "heartbeat" : "poll") +
            " status=-3 credential=cleared uploads=disabled\n");
    }
    reset_fixture();
    provision_fixture();
    const unsigned before_begins = fixture_begins;
    fixture_wifi_status = 0;
    device_probe_loop();
    assert_latched_stop("DEVICE_FAIL stage=wifi_lost status=-1 credential=cleared uploads=disabled\n");
    assert(fixture_begins == before_begins);

    reset_fixture();
    fixture_negative_status = 200;
    provision_fixture();
    assert_latched_stop("DEVICE_FAIL stage=unauthenticated_poll status=200 credential=cleared uploads=disabled\n");
    assert(fixture_posts == 0 && fixture_gets == 1);
    std::cout << "PASS: exact body bound, embedded NUL rejection, Wi-Fi loss and negative-auth gate (synthetic fixtures)\n";
}

int main() {
    device_probe_loop();
    assert(fixture_posts == 0 && fixture_gets == 0);
    Serial.input = "KBD1" + std::string(43, 'x');
    device_probe_loop();
    device_probe_loop();
    assert(fixture_posts == 1 && fixture_gets == 2); // Negative poll, heartbeat, authenticated poll.
    fixture_now = 1999;
    device_probe_loop();
    assert(fixture_posts == 1 && fixture_gets == 2);
    fixture_now = 2000;
    device_probe_loop();
    assert(fixture_posts == 1 && fixture_gets == 3); // Poll doesn't imply heartbeat.
    fixture_now = 9999;
    device_probe_loop();
    assert(fixture_posts == 1);
    fixture_now = 10000;
    device_probe_loop();
    assert(fixture_posts == 2);
    fixture_now = 20000;
    device_probe_loop();
    assert(fixture_posts == 3);
    bool passed = false;
    for (const auto& line : fixture_lines) {
        assert(line.find(std::string(43, 'x')) == std::string::npos);
        if (line.find("DEVICE_PASS ") == 0) passed = true;
    }
    assert(passed);
    fixture_now = 30000;
    device_probe_loop();
    assert(fixture_posts == 4); // Keepalive continues after first validation checkpoint.
    assert(fixture_trusted_requests == fixture_posts + fixture_gets);
    fixture_rejected = true;
    fixture_now = 40000;
    device_probe_loop();
    assert(failed && !credential.ready() && credential.token()[0] == '\0');
    const unsigned stopped_posts = fixture_posts;
    const unsigned stopped_gets = fixture_gets;
    fixture_now = 50000;
    device_probe_loop();
    assert(fixture_posts == stopped_posts && fixture_gets == stopped_gets);
    std::cout << "PASS: diagnostic negative auth, exact endpoints/bodies/TLS, heartbeat vs polling cadence, ongoing keepalive and revoked-credential stop (synthetic fixtures)\n";
    fault_matrix();
    boundary_and_wifi_cases();
}
