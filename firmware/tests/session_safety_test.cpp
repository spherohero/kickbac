// Synthetic session clocks and payloads; never an ADC or real upload.
#include <cassert>
#include <cstring>
#include <iostream>
#include <string>
#include "session_safety.hpp"

int main() {
    using namespace kickbac;
    const char* armed = R"({"device_id":"kb-demo-01","active_session":{"id":"3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b","device_id":"kb-demo-01","status":"ARMED","expires_at":"2026-10-18T00:31:01.123456+00:00"}})";
    PollSnapshot snapshot;
    assert(poll_response(200, armed, snapshot) == PollState::Armed);
    assert(std::strcmp(snapshot.id, "3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b") == 0);
    assert(std::strcmp(snapshot.expires_at, "2026-10-18T00:31:01.123456+00:00") == 0);
    std::int64_t expiry = 0;
    assert(utc_epoch_ms(snapshot.expires_at, expiry));
    std::int64_t value = 99;
    assert(utc_epoch_ms("1970-01-01T00:00:00Z", value) && value == 0);
    assert(utc_epoch_ms("2000-02-29T00:00:00Z", value) && value == 951782400000LL);
    for (const char* bad : {"2026-02-29T00:00:00Z", "2100-02-29T00:00:00Z",
            "2026-13-01T00:00:00Z", "2026-10-18T24:00:00Z", "2026-10-18T00:60:00Z",
            "2026-10-18T00:00:60Z", "2026-00-00T00:00:00Z"}) {
        assert(!utc_epoch_ms(bad, value));
    }
    PollSnapshot invalid = snapshot;
    assert(poll_response(503, armed, invalid) == PollState::Invalid);
    assert(invalid.id[0] == '\0' && invalid.expires_at[0] == '\0');
    std::string malformed(armed);
    malformed.replace(malformed.find("2026-10-18"), 10, "2026-02-30");
    assert(poll_response(200, malformed.c_str(), invalid) == PollState::Invalid);

    SessionFence fence;
    SessionTicket ticket;
    assert(!fence.begin(ticket, 100, expiry - 60000));
    assert(fence.observe(snapshot, 100, expiry - 60000));
    assert(fence.begin(ticket, 100, expiry - 60000));
    assert(fence.matches(ticket, 5099, expiry - 55001));
    assert(!fence.matches(ticket, 5100, expiry - 55000)); // stale poll fences old acquisition
    assert(fence.observe(snapshot, 5100, expiry - 55000));
    assert(!fence.matches(ticket, 5100, expiry - 55000)); // cannot revive a stale ticket
    assert(fence.begin(ticket, 5100, expiry - 55000));
    snapshot.state = PollState::Sampling;
    assert(fence.observe(snapshot, 6000, expiry - 54100));
    assert(fence.matches(ticket, 6000, expiry - 54100));
    SessionTicket blocked;
    assert(!fence.begin(blocked, 6000, expiry - 54100)); // no restart into SAMPLING
    snapshot.state = PollState::Armed;
    assert(!fence.observe(snapshot, 6100, expiry - 54000)); // impossible regression
    assert(!fence.matches(ticket, 6100, expiry - 54000));

    fence = SessionFence{}; // independent synthetic clock scenario
    assert(fence.observe(snapshot, 10000, expiry - 1000));
    assert(fence.begin(ticket, 10000, expiry - 1000));
    assert(!fence.matches(ticket, 11000, expiry - 2000)); // backwards UTC cannot extend monotonic deadline
    assert(!fence.observe(snapshot, 11000, expiry - 2000));
    assert(!fence.begin(ticket, 11000, expiry - 2000)); // nor issue a NEW ticket after expiry
    assert(!fence.observe(snapshot, 11000, expiry)); // exact expiry rejected
    assert(!fence.observe(snapshot, 11000, 0)); // unavailable clock rejected
    fence = SessionFence{};
    assert(!fence.observe(snapshot, 11000, expiry - 60001)); // bounded server session
    fence = SessionFence{};
    assert(fence.observe(snapshot, UINT32_MAX - 999U, expiry - 2000));
    assert(fence.begin(ticket, UINT32_MAX - 999U, expiry - 2000));
    assert(fence.matches(ticket, 0, expiry - 1000));
    assert(!fence.matches(ticket, 1000, expiry));

    fence = SessionFence{};
    assert(fence.observe(snapshot, 100, expiry - 60000));
    assert(fence.begin(ticket, 100, expiry - 60000));
    PollSnapshot other = snapshot;
    other.id[0] = '4';
    assert(fence.observe(other, 200, expiry - 59900));
    assert(!fence.matches(ticket, 200, expiry - 59900)); // never transfer to next user/session
    assert(fence.begin(ticket, 200, expiry - 59900));
    PollSnapshot changed_expiry = other;
    std::strcpy(changed_expiry.expires_at, "2026-10-18T00:31:02Z");
    assert(!fence.observe(changed_expiry, 300, expiry - 59800));
    assert(!fence.matches(ticket, 300, expiry - 59800));
    assert(fence.observe(other, 400, expiry - 59700));
    assert(fence.begin(ticket, 400, expiry - 59700));
    PollSnapshot idle;
    idle.state = PollState::Idle;
    assert(!fence.observe(idle, 500, expiry - 59600));
    assert(!fence.matches(ticket, 500, expiry - 59600));

    // Opaque, immutable pending bytes: construction/measurement semantics are NOT implemented here.
    FrozenUpload pending;
    const char* id = "026af7c9-d605-4291-a1db-5b230e10ef43";
    const char* payload = R"({"measurement_id":"026af7c9-d605-4291-a1db-5b230e10ef43","session_id":"3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b","fixture_only":true})";
    assert(pending.seal(snapshot.id, id, payload));
    assert(std::strcmp(pending.body(), payload) == 0);
    assert(std::strcmp(pending.session_id(), snapshot.id) == 0);
    assert(std::strcmp(pending.measurement_id(), id) == 0);
    assert(!pending.seal(other.id, id, payload));
    assert(!pending.acknowledge(201, "different", snapshot.id));
    assert(!pending.acknowledge(503, id, snapshot.id));
    assert(pending.ready() && std::strcmp(pending.body(), payload) == 0);
    assert(pending.acknowledge(200, id, snapshot.id));
    assert(!pending.ready() && pending.body()[0] == '\0');
    assert(!pending.seal(other.id, id, payload)); // payload/session mismatch
    assert(!pending.seal(snapshot.id, "invalid", payload));
    assert(!pending.seal(snapshot.id, id, std::string(769, 'x').c_str()));
    assert(pending.seal(snapshot.id, id, payload));
    assert(pending.acknowledge(201, id, snapshot.id));
    std::cout << "PASS: retained identity/expiry, calendar validation, session fencing, monotonic expiry/wrap and immutable retry bytes (synthetic fixtures)\n";
}
