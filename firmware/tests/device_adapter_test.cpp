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
FixtureSerial Serial;
FixtureWiFi WiFi;

#include "../src/device_probe.cpp"

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
}
