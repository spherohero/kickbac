#include <cassert>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <string>
#include "device_diagnostic.hpp"

int main() {
    kickbac::DeviceCredentialFrame frame;
    const std::string fixture = "KBD1" + std::string(43, 'x');
    for (std::size_t i = 0; i < fixture.size(); ++i) {
        const bool ready = frame.feed(static_cast<std::uint8_t>(fixture[i]), static_cast<std::uint32_t>(i));
        assert(ready == (i + 1 == fixture.size()));
    }
    assert(frame.ready());
    assert(std::strlen(frame.token()) == 43);
    assert(!frame.feed('x', 100));
    frame.clear();
    for (std::size_t i = 0; i < 44; ++i) assert(frame.token()[i] == '\0');
    assert(!frame.ready());
    for (char c : std::string("noiseKBD1abc")) frame.feed(static_cast<std::uint8_t>(c), 0);
    assert(!frame.expire(3000));
    assert(frame.expire(3001));
    assert(frame.token()[0] == '\0');
    for (char c : std::string("KBD1ab\r")) frame.feed(static_cast<std::uint8_t>(c), 4000);
    assert(!frame.ready());
    for (char c : fixture) frame.feed(static_cast<std::uint8_t>(c), 5000);
    assert(frame.ready());
    frame.clear();
    for (char c : std::string("KBD1abc")) frame.feed(static_cast<std::uint8_t>(c), UINT32_MAX - 1000U);
    assert(!frame.expire(1999));
    assert(frame.expire(2000));
    std::cout << "PASS: bounded device bearer USB frame, invalid input, clearing and timeout/wrap (fixture)\n";

    char seen[40] = {};
    const char* heartbeat = R"({"device_id":"kb-demo-01","online":true,"last_seen_at":"2026-10-18T00:30:01.123456+00:00"})";
    assert(kickbac::heartbeat_response_ok(200, heartbeat, seen));
    assert(std::strcmp(seen, "2026-10-18T00:30:01.123456+00:00") == 0);
    assert(!kickbac::heartbeat_response_ok(401, heartbeat, seen));
    assert(seen[0] == '\0');
    assert(!kickbac::heartbeat_response_ok(200, "{}", seen));
    assert(!kickbac::heartbeat_response_ok(200, R"({"device_id":"other","online":true,"last_seen_at":"x"})", seen));
    assert(!kickbac::heartbeat_response_ok(200, R"({"device_id":"kb-demo-01","online":"true","last_seen_at":"2026-10-18T00:30:01Z"})", seen));
    assert(!kickbac::heartbeat_response_ok(200, R"({"device_id":"kb-demo-01","online":false,"last_seen_at":"2026-10-18T00:30:01Z"})", seen));
    assert(!kickbac::heartbeat_response_ok(200, nullptr, seen));
    assert(!kickbac::heartbeat_response_ok(200, (std::string(1500, 'x')).c_str(), seen));
    assert(!kickbac::heartbeat_response_ok(200, R"({"device_id":"kb-demo-01","online":true,"last_seen_at":"not-a-timestamp"})", seen));
    using kickbac::PollState;
    const char* idle = R"({"device_id":"kb-demo-01","active_session":null})";
    assert(kickbac::poll_response(200, idle) == PollState::Idle);
    assert(kickbac::poll_response(401, idle) == PollState::Invalid);
    assert(kickbac::poll_response(200, R"({"device_id":"kb-demo-01"})") == PollState::Invalid);
    assert(kickbac::poll_response(200, R"({"device_id":"other","active_session":null})") == PollState::Invalid);
    const char* armed = R"({"device_id":"kb-demo-01","active_session":{"id":"3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b","device_id":"kb-demo-01","status":"ARMED","expires_at":"2026-10-18T00:31:01Z"}})";
    assert(kickbac::poll_response(200, armed) == PollState::Armed);
    std::string sampling(armed);
    sampling.replace(sampling.find("ARMED"), 5, "SAMPLING");
    assert(kickbac::poll_response(200, sampling.c_str()) == PollState::Sampling);
    sampling.replace(sampling.find("SAMPLING"), 8, "COMPLETE");
    assert(kickbac::poll_response(200, sampling.c_str()) == PollState::Invalid);
    assert(kickbac::poll_response(200, R"({"device_id":"kb-demo-01","active_session":null,"user_id":"fixture"})") == PollState::Invalid);
    assert(kickbac::poll_response(200, "<html>login</html>") == PollState::Invalid);
    assert(kickbac::poll_response(200, nullptr) == PollState::Invalid);
    std::cout << "PASS: identity-bound heartbeat and idle/active device polling JSON validation (fixtures)\n";
    return 0;
}
